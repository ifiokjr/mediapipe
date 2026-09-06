import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:mp_core/mp_core.dart';
import 'package:mp_core/native.dart' as native;

import 'function_calling.dart';
import 'image_generator.dart';
import 'llm_inference.dart';
import 'options.dart';
import 'rag.dart';
import 'runtime.dart';

const MethodChannel _methods = MethodChannel('dev.ifiokjr.mp_genai/methods');
const EventChannel _events = EventChannel('dev.ifiokjr.mp_genai/events');

final _MobileGenAiBridge _bridge = _MobileGenAiBridge();

/// Android adapter backed by MediaPipe Tasks GenAI.
final class MobileGenAiRuntime implements GenAiRuntime {
  /// Creates the Android platform adapter.
  const MobileGenAiRuntime();

  @override
  Future<FunctionCallingBackend> createGenerativeModel(GenerativeModelOptions options) =>
      _MobileFunctionCallingModel.create(options);

  @override
  Future<ImageGeneratorBackend> createImageGenerator(ImageGeneratorOptions options) =>
      _MobileImageGenerator.create(options);

  @override
  Future<RagPipelineBackend> createRagPipeline(RagPipelineOptions options) =>
      _MobileRagPipeline.create(options);

  @override
  Future<LlmInferenceBackend> createLlmInference(LlmInferenceOptions options) async {
    final _ResolvedLlmConfiguration configuration = await _resolveLlmConfiguration(options);
    try {
      final int handle = await _bridge.createTask(
        'llm.create',
        configuration.arguments,
        task: 'LlmInference',
      );
      return _MobileLlmInference(handle, configuration.resources);
    } on Object {
      await configuration.release();
      rethrow;
    }
  }
}

final class _ResolvedLlmConfiguration {
  const _ResolvedLlmConfiguration(this.arguments, this.resources);

  final Map<String, Object?> arguments;
  final List<_ModelLease> resources;

  Future<void> release() =>
      Future.wait(resources.map((_ModelLease resource) => resource.release()));
}

Future<_ResolvedLlmConfiguration> _resolveLlmConfiguration(LlmInferenceOptions options) async {
  final _ModelLease model = await _resolveModelFile(options.baseOptions.modelAsset);
  final List<_ModelLease> resources = <_ModelLease>[model];
  try {
    final _ModelLease? visionEncoder = await _resolveOptionalModel(
      options.visionModelOptions?.encoder,
    );
    if (visionEncoder != null) resources.add(visionEncoder);
    final _ModelLease? visionAdapter = await _resolveOptionalModel(
      options.visionModelOptions?.adapter,
    );
    if (visionAdapter != null) resources.add(visionAdapter);
    return _ResolvedLlmConfiguration(<String, Object?>{
      'modelPath': model.path,
      'maxTokens': options.maxTokens,
      'maxTopK': options.maxTopK,
      'maxNumImages': options.maxNumImages,
      'supportedLoraRanks': options.supportedLoraRanks,
      'preferredBackend': options.preferredBackend.name,
      'visionEncoderPath': visionEncoder?.path,
      'visionAdapterPath': visionAdapter?.path,
      'maxAudioSequenceLength': options.audioModelOptions?.maxAudioSequenceLength,
    }, resources);
  } on Object {
    await Future.wait(resources.map((_ModelLease resource) => resource.release()));
    rethrow;
  }
}

final class _ModelLease {
  _ModelLease(this.path, [this.temporaryDirectory]);

  final String path;
  final Directory? temporaryDirectory;
  var _references = 1;

  _ModelLease retain() {
    if (_references <= 0) throw StateError('Cannot retain a released model file.');
    _references++;
    return this;
  }

  Future<void> release() async {
    if (_references <= 0) return;
    _references--;
    if (_references != 0) return;
    final Directory? directory = temporaryDirectory;
    if (directory != null && directory.existsSync()) {
      directory.deleteSync(recursive: true);
    }
  }
}

Future<_ModelLease?> _resolveOptionalModel(ModelAsset? asset) async =>
    asset == null ? null : _resolveModelFile(asset);

Future<_ModelLease> _resolveModelFile(ModelAsset asset) async {
  final ModelAsset resolved = await native.resolveNativeModelAsset(asset);
  switch (resolved) {
    case ModelAssetPath(:final path):
      final File file = File(path).absolute;
      if (!file.existsSync()) {
        throw MpException(MpStatus.notFound, 'The model file does not exist: ${file.path}');
      }
      return _ModelLease(file.path);
    case ModelAssetBytes(:final bytes, :final name):
      final Directory directory = await Directory.systemTemp.createTemp('mp_genai_model_');
      final String rawName = name?.split(RegExp(r'[/\\]')).lastOrNull ?? 'model.task';
      final String safeName = rawName.replaceAll(RegExp('[^A-Za-z0-9._-]'), '_');
      final File file = File('${directory.path}${Platform.pathSeparator}$safeName');
      try {
        file.writeAsBytesSync(bytes, flush: true);
        return _ModelLease(file.path, directory);
      } on Object {
        directory.deleteSync(recursive: true);
        rethrow;
      }
    case ModelAssetUri():
      throw const MpException(
        MpStatus.failedPrecondition,
        'The native model URI was not resolved.',
      );
  }
}

abstract base class _MobileLlmTask implements MpTask {
  _MobileLlmTask(this.handle, this.taskName);

  final int handle;
  final String taskName;
  bool _closed = false;
  bool _busy = false;
  Future<void>? _activeOperation;

  @override
  bool get isClosed => _closed;

  void ensureAvailable() {
    if (_closed) throw MpTaskClosedError(taskName);
    if (_busy) {
      throw MpException(
        MpStatus.failedPrecondition,
        '$taskName already has an active operation.',
        task: taskName,
      );
    }
  }

  Future<T> runExclusive<T>(Future<T> Function() operation) {
    ensureAvailable();
    _busy = true;
    final Future<T> result = operation().whenComplete(() => _busy = false);
    _activeOperation = result.then<void>((_) {}, onError: (Object _, StackTrace _) {});
    return result;
  }

  void trackGeneration(Future<void> done) {
    ensureAvailable();
    _busy = true;
    _activeOperation = done.whenComplete(() => _busy = false);
  }

  Future<void> waitForActiveOperation() async => _activeOperation;

  void markClosed() => _closed = true;
}

final class _MobileLlmInference extends _MobileLlmTask implements LlmInferenceBackend {
  _MobileLlmInference(int handle, this._resources) : super(handle, 'LlmInference');

  final List<_ModelLease> _resources;

  @override
  Future<LlmSessionBackend> createSession(LlmSessionOptions options) => runExclusive(() async {
    if (options.numResponses != 1) {
      throw MpException(
        MpStatus.unimplemented,
        'Android MediaPipe LLM sessions support one response at a time.',
        task: taskName,
      );
    }
    final _ModelLease? lora = await _resolveOptionalModel(options.loraAsset);
    try {
      final int sessionHandle = await _bridge.createTask('llm.createSession', <String, Object?>{
        'handle': handle,
        ..._sessionOptionsMap(options, loraPath: lora?.path),
      }, task: 'LlmSession');
      return _MobileLlmSession(sessionHandle, lora);
    } on Object {
      await lora?.release();
      rethrow;
    }
  });

  @override
  Future<int> sizeInTokens(String text) => runExclusive(
    () => _bridge.invokeInt('llm.sizeInTokens', <String, Object?>{
      'handle': handle,
      'text': text,
    }, task: taskName),
  );

  @override
  Future<void> close() async {
    if (isClosed) return;
    markClosed();
    await waitForActiveOperation();
    try {
      await _bridge.invokeVoid('llm.close', <String, Object?>{'handle': handle}, task: taskName);
    } finally {
      await Future.wait(_resources.map((_ModelLease resource) => resource.release()));
    }
  }
}

final class _MobileLlmSession extends _MobileLlmTask implements LlmSessionBackend {
  _MobileLlmSession(int handle, this._lora) : super(handle, 'LlmSession');

  final _ModelLease? _lora;

  @override
  Future<void> addQueryChunk(String text) => runExclusive(
    () => _bridge.invokeVoid('llm.addQuery', <String, Object?>{
      'handle': handle,
      'text': text,
    }, task: taskName),
  );

  @override
  Future<void> addImage(MpImage image) => runExclusive(() {
    if (image case MpImageUint8(:final data)) {
      return _bridge.invokeVoid('llm.addImage', <String, Object?>{
        'handle': handle,
        'width': image.width,
        'height': image.height,
        'format': image.format.name,
        'data': data,
      }, task: taskName);
    }
    throw MpException(
      MpStatus.unimplemented,
      'Android LLM image input supports only 8-bit sRGB, sRGBA, or grayscale images.',
      task: taskName,
    );
  });

  @override
  Future<void> addAudio(Uint8List wavBytes) => runExclusive(
    () => _bridge.invokeVoid('llm.addAudio', <String, Object?>{
      'handle': handle,
      'data': wavBytes,
    }, task: taskName),
  );

  @override
  Future<LlmGeneration> generate() async {
    ensureAvailable();
    final _GenerationOperation operation = _bridge.startGeneration(handle);
    trackGeneration(operation.done);
    return LlmGeneration(
      chunks: operation.stream,
      response: operation.response,
      cancel: () =>
          _bridge.invokeVoid('llm.cancel', <String, Object?>{'handle': handle}, task: taskName),
    );
  }

  @override
  Future<int> sizeInTokens(String text) => runExclusive(
    () => _bridge.invokeInt('llm.sessionSizeInTokens', <String, Object?>{
      'handle': handle,
      'text': text,
    }, task: taskName),
  );

  @override
  Future<LlmSessionBackend> clone() => runExclusive(() async {
    final int cloneHandle = await _bridge.createTask('llm.cloneSession', <String, Object?>{
      'handle': handle,
    }, task: taskName);
    return _MobileLlmSession(cloneHandle, _lora?.retain());
  });

  @override
  Future<void> updateOptions(LlmSessionOptions options) => runExclusive(
    () => _bridge.invokeVoid('llm.updateSession', <String, Object?>{
      'handle': handle,
      ..._sessionOptionsMap(options, includeImmutable: false),
    }, task: taskName),
  );

  @override
  Future<void> close() async {
    if (isClosed) return;
    markClosed();
    await waitForActiveOperation();
    try {
      await _bridge.invokeVoid('llm.closeSession', <String, Object?>{
        'handle': handle,
      }, task: taskName);
    } finally {
      await _lora?.release();
    }
  }
}

final class _MobileFunctionCallingModel extends _MobileLlmTask implements FunctionCallingBackend {
  _MobileFunctionCallingModel._(int handle, this._resources) : super(handle, 'GenerativeModel');

  final List<_ModelLease> _resources;

  static Future<_MobileFunctionCallingModel> create(GenerativeModelOptions options) async {
    final _ResolvedLlmConfiguration configuration = await _resolveLlmConfiguration(
      options.inferenceOptions,
    );
    final List<_ModelLease> resources = configuration.resources;
    _ModelLease? lora;
    try {
      final LlmSessionOptions sessionOptions = options.sessionOptions ?? LlmSessionOptions();
      if (sessionOptions.numResponses != 1) {
        throw const MpException(
          MpStatus.unimplemented,
          'Android function calling supports one response at a time.',
          task: 'GenerativeModel',
        );
      }
      lora = await _resolveOptionalModel(sessionOptions.loraAsset);
      if (lora != null) resources.add(lora);
      final int handle = await _bridge.createTask('functionCalling.create', <String, Object?>{
        ...configuration.arguments,
        ..._sessionOptionsMap(sessionOptions, loraPath: lora?.path),
        'formatter': options.formatter.name,
        'addPromptTemplate': options.addPromptTemplate,
        'systemInstruction': ?_contentMap(options.systemInstruction),
        'tools': options.tools.map(_toolMap).toList(growable: false),
      }, task: 'GenerativeModel');
      return _MobileFunctionCallingModel._(handle, resources);
    } on Object {
      await configuration.release();
      rethrow;
    }
  }

  @override
  Future<GenerateContentResponse> generateContent(List<GenAiContent> contents) =>
      runExclusive(() async {
        final Map<Object?, Object?> result = await _bridge.invokeMap(
          'functionCalling.generateContent',
          <String, Object?>{
            'handle': handle,
            'contents': contents.map(_contentMap).toList(growable: false),
          },
          task: taskName,
        );
        return _readGenerateContentResponse(result, taskName);
      });

  @override
  Future<FunctionCallingChatBackend> startChat() => runExclusive(() async {
    final int chatHandle = await _bridge.createTask('functionCalling.startChat', <String, Object?>{
      'handle': handle,
    }, task: 'FunctionCallingChat');
    return _MobileFunctionCallingChat(chatHandle);
  });

  @override
  Future<void> close() async {
    if (isClosed) return;
    markClosed();
    await waitForActiveOperation();
    try {
      await _bridge.invokeVoid('functionCalling.close', <String, Object?>{
        'handle': handle,
      }, task: taskName);
    } finally {
      await Future.wait(_resources.map((_ModelLease resource) => resource.release()));
    }
  }
}

final class _MobileFunctionCallingChat extends _MobileLlmTask
    implements FunctionCallingChatBackend {
  _MobileFunctionCallingChat(int handle) : super(handle, 'FunctionCallingChat');

  @override
  Future<GenerateContentResponse> sendMessage(GenAiContent content) => runExclusive(() async {
    final Map<Object?, Object?> result = await _bridge.invokeMap(
      'functionCalling.sendMessage',
      <String, Object?>{'handle': handle, 'content': _contentMap(content)},
      task: taskName,
    );
    return _readGenerateContentResponse(result, taskName);
  });

  @override
  Future<ChatRewindResult> rewind() => runExclusive(() async {
    final Map<Object?, Object?> result = await _bridge.invokeMap(
      'functionCalling.rewind',
      <String, Object?>{'handle': handle},
      task: taskName,
    );
    final Object? sent = result['lastSent'];
    final Object? received = result['lastReceived'];
    if (sent is! Map<Object?, Object?> || received is! Map<Object?, Object?>) {
      throw MpException(MpStatus.internal, '$taskName returned an invalid rewind result.');
    }
    return ChatRewindResult(
      lastSent: _readContent(sent, taskName),
      lastReceived: _readContent(received, taskName),
    );
  });

  @override
  Future<List<GenAiContent>> history() => runExclusive(() async {
    final List<Object?> result = await _bridge.invokeList(
      'functionCalling.history',
      <String, Object?>{'handle': handle},
      task: taskName,
    );
    return result
        .map((Object? value) {
          if (value is! Map<Object?, Object?>) {
            throw MpException(MpStatus.internal, '$taskName returned invalid history.');
          }
          return _readContent(value, taskName);
        })
        .toList(growable: false);
  });

  @override
  Future<GenAiContent> last() => runExclusive(() async {
    final Map<Object?, Object?> result = await _bridge.invokeMap(
      'functionCalling.last',
      <String, Object?>{'handle': handle},
      task: taskName,
    );
    return _readContent(result, taskName);
  });

  @override
  Future<FunctionCallingChatBackend> clone() => runExclusive(() async {
    final int cloneHandle = await _bridge.createTask('functionCalling.cloneChat', <String, Object?>{
      'handle': handle,
    }, task: taskName);
    return _MobileFunctionCallingChat(cloneHandle);
  });

  @override
  Future<void> enableConstraint(FunctionCallingConstraint constraint) => runExclusive(
    () => _bridge.invokeVoid('functionCalling.enableConstraint', <String, Object?>{
      'handle': handle,
      'constraint': _constraintMap(constraint),
    }, task: taskName),
  );

  @override
  Future<void> disableConstraint() => runExclusive(
    () => _bridge.invokeVoid('functionCalling.disableConstraint', <String, Object?>{
      'handle': handle,
    }, task: taskName),
  );

  @override
  Future<void> close() async {
    if (isClosed) return;
    markClosed();
    await waitForActiveOperation();
    await _bridge.invokeVoid('functionCalling.closeChat', <String, Object?>{
      'handle': handle,
    }, task: taskName);
  }
}

Map<String, Object?>? _contentMap(GenAiContent? content) => content == null
    ? null
    : <String, Object?>{
        'role': content.role,
        'parts': content.parts.map(_partMap).toList(growable: false),
      };

Map<String, Object?> _partMap(GenAiPart part) => switch (part) {
  GenAiTextPart(:final text) => <String, Object?>{'kind': 'text', 'text': text},
  GenAiFunctionCallPart(:final call) => <String, Object?>{
    'kind': 'functionCall',
    'name': call.name,
    'value': call.arguments,
  },
  GenAiFunctionResponsePart(:final response) => <String, Object?>{
    'kind': 'functionResponse',
    'name': response.name,
    'value': response.response,
  },
};

Map<String, Object?> _toolMap(FunctionTool tool) => <String, Object?>{
  'declarations': tool.declarations.map(_declarationMap).toList(growable: false),
};

Map<String, Object?> _declarationMap(FunctionDeclaration declaration) => <String, Object?>{
  'name': declaration.name,
  'description': declaration.description,
  'parameters': ?_schemaMap(declaration.parameters),
  'response': ?_schemaMap(declaration.response),
};

Map<String, Object?>? _schemaMap(FunctionSchema? schema) => schema == null
    ? null
    : <String, Object?>{
        'type': schema.type.name,
        'format': schema.format,
        'title': schema.title,
        'description': schema.description,
        'nullable': schema.nullable,
        'enumValues': schema.enumValues,
        'items': ?_schemaMap(schema.items),
        'minItems': schema.minItems,
        'maxItems': schema.maxItems,
        'properties': schema.properties.map(
          (String name, FunctionSchema property) =>
              MapEntry<String, Object?>(name, _schemaMap(property)),
        ),
        'requiredProperties': schema.requiredProperties,
        'minimum': schema.minimum,
        'maximum': schema.maximum,
        'anyOf': schema.anyOf.map(_schemaMap).toList(growable: false),
        'propertyOrdering': schema.propertyOrdering,
      };

Map<String, Object?> _constraintMap(FunctionCallingConstraint constraint) => switch (constraint) {
  ToolCallOnlyConstraint(:final prefix, :final suffix) => <String, Object?>{
    'kind': 'toolCallOnly',
    'prefix': prefix,
    'suffix': suffix,
  },
  TextAndOrConstraint(:final stopPhrasePrefix, :final stopPhraseSuffix, :final constraintSuffix) =>
    <String, Object?>{
      'kind': 'textAndOr',
      'stopPhrasePrefix': stopPhrasePrefix,
      'stopPhraseSuffix': stopPhraseSuffix,
      'constraintSuffix': constraintSuffix,
    },
  TextUntilConstraint(:final stopPhrase, :final constraintSuffix) => <String, Object?>{
    'kind': 'textUntil',
    'stopPhrase': stopPhrase,
    'constraintSuffix': constraintSuffix,
  },
};

GenerateContentResponse _readGenerateContentResponse(Map<Object?, Object?> result, String task) {
  final Object? rawCandidates = result['candidates'];
  if (rawCandidates is! List<Object?>) {
    throw MpException(MpStatus.internal, '$task returned invalid candidates.', task: task);
  }
  return GenerateContentResponse(
    rawCandidates.map((Object? value) {
      if (value is! Map<Object?, Object?>) {
        throw MpException(MpStatus.internal, '$task returned an invalid candidate.', task: task);
      }
      return GenAiCandidate(_readContent(value, task));
    }),
  );
}

GenAiContent _readContent(Map<Object?, Object?> value, String task) {
  final Object? role = value['role'];
  final Object? rawParts = value['parts'];
  if (role is! String || rawParts is! List<Object?>) {
    throw MpException(MpStatus.internal, '$task returned invalid content.', task: task);
  }
  return GenAiContent(
    role: role,
    parts: rawParts.map((Object? rawPart) {
      if (rawPart is! Map<Object?, Object?>) {
        throw MpException(MpStatus.internal, '$task returned an invalid content part.', task: task);
      }
      final Object? name = rawPart['name'];
      final Object? rawValue = rawPart['value'];
      return switch (rawPart['kind']) {
        'text' when rawPart['text'] is String => GenAiTextPart(rawPart['text']! as String),
        'functionCall' when name is String && rawValue is Map<Object?, Object?> =>
          GenAiFunctionCallPart(
            FunctionCall(name: name, arguments: _stringKeyedMap(rawValue, task)),
          ),
        'functionResponse' when name is String && rawValue is Map<Object?, Object?> =>
          GenAiFunctionResponsePart(
            FunctionResponse(name: name, response: _stringKeyedMap(rawValue, task)),
          ),
        _ => throw MpException(
          MpStatus.internal,
          '$task returned an unknown content part.',
          task: task,
        ),
      };
    }),
  );
}

Map<String, Object?> _stringKeyedMap(Map<Object?, Object?> value, String task) {
  final Map<String, Object?> result = <String, Object?>{};
  for (final MapEntry<Object?, Object?> entry in value.entries) {
    if (entry.key is! String) {
      throw MpException(MpStatus.internal, '$task returned a non-string object key.', task: task);
    }
    result[entry.key! as String] = _platformJson(entry.value, task);
  }
  return result;
}

Object? _platformJson(Object? value, String task) => switch (value) {
  null || bool() || String() || num() => value,
  List<Object?>() => value.map((Object? item) => _platformJson(item, task)).toList(growable: false),
  Map<Object?, Object?>() => _stringKeyedMap(value, task),
  _ => throw MpException(
    MpStatus.internal,
    '$task returned a non-JSON function value.',
    task: task,
  ),
};

final class _MobileRagPipeline extends _MobileLlmTask implements RagPipelineBackend {
  _MobileRagPipeline._(int handle, this._resources) : super(handle, 'RagPipeline');

  final List<_ModelLease> _resources;

  static Future<_MobileRagPipeline> create(RagPipelineOptions options) async {
    final _ResolvedLlmConfiguration configuration = await _resolveLlmConfiguration(
      options.inferenceOptions,
    );
    final List<_ModelLease> resources = configuration.resources;
    Future<String> resolve(ModelAsset asset) async {
      final _ModelLease resource = await _resolveModelFile(asset);
      resources.add(resource);
      return resource.path;
    }

    try {
      final LlmSessionOptions sessionOptions = options.sessionOptions ?? LlmSessionOptions();
      if (sessionOptions.numResponses != 1) {
        throw const MpException(
          MpStatus.unimplemented,
          'Android RAG supports one response at a time.',
          task: 'RagPipeline',
        );
      }
      final _ModelLease? lora = await _resolveOptionalModel(sessionOptions.loraAsset);
      if (lora != null) resources.add(lora);
      final Map<String, Object?> embedding = switch (options.embeddingModel) {
        GeckoEmbeddingModelOptions(
          model: final ModelAsset model,
          tokenizer: final ModelAsset? tokenizer,
          useGpu: final bool useGpu,
        ) =>
          <String, Object?>{
            'kind': 'gecko',
            'modelPath': await resolve(model),
            'tokenizerPath': tokenizer == null ? null : await resolve(tokenizer),
            'useGpu': useGpu,
          },
        GemmaEmbeddingModelOptions(
          model: final ModelAsset model,
          tokenizer: final ModelAsset tokenizer,
          useGpu: final bool useGpu,
        ) =>
          <String, Object?>{
            'kind': 'gemma',
            'modelPath': await resolve(model),
            'tokenizerPath': await resolve(tokenizer),
            'useGpu': useGpu,
          },
      };
      final Map<String, Object?> vectorStore = switch (options.vectorStore) {
        InMemoryVectorStoreOptions() => <String, Object?>{'kind': 'memory'},
        SqliteVectorStoreOptions(
          embeddingDimensions: final int embeddingDimensions,
          databasePath: final String databasePath,
          tableName: final String? tableName,
          textColumnName: final String? textColumnName,
          embeddingsColumnName: final String? embeddingsColumnName,
          columns: final List<RagSqliteColumn> columns,
        ) =>
          <String, Object?>{
            'kind': 'sqlite',
            'embeddingDimensions': embeddingDimensions,
            'databasePath': File(databasePath).absolute.path,
            'tableName': tableName,
            'textColumnName': textColumnName,
            'embeddingsColumnName': embeddingsColumnName,
            'columns': columns
                .map(
                  (RagSqliteColumn column) => <String, Object?>{
                    'name': column.name,
                    'sqlType': column.sqlType,
                    'keyType': column.keyType.name,
                    'autoIncrement': column.autoIncrement,
                    'nullable': column.nullable,
                  },
                )
                .toList(growable: false),
          },
      };
      final int handle = await _bridge.createTask('rag.create', <String, Object?>{
        ...configuration.arguments,
        ..._sessionOptionsMap(sessionOptions, loraPath: lora?.path),
        'embedding': embedding,
        'vectorStore': vectorStore,
        'promptTemplate': options.promptTemplate,
      }, task: 'RagPipeline');
      return _MobileRagPipeline._(handle, resources);
    } on Object {
      await configuration.release();
      rethrow;
    }
  }

  @override
  Future<bool> record(RagDocument document) => runExclusive(
    () => _bridge.invokeBool('rag.record', <String, Object?>{
      'handle': handle,
      'document': _ragDocumentMap(document),
    }, task: taskName),
  );

  @override
  Future<bool> recordAll(List<RagDocument> documents) => runExclusive(
    () => _bridge.invokeBool('rag.recordAll', <String, Object?>{
      'handle': handle,
      'documents': documents.map(_ragDocumentMap).toList(growable: false),
    }, task: taskName),
  );

  @override
  Future<List<RagRetrievalEntity>> retrieve(String query, RagRetrievalOptions options) =>
      runExclusive(() async {
        final List<Object?> entities = await _bridge.invokeList('rag.retrieve', <String, Object?>{
          'handle': handle,
          'query': query,
          ..._ragRetrievalMap(options),
        }, task: taskName);
        return entities
            .map((Object? raw) {
              if (raw is! Map<Object?, Object?>) {
                throw MpException(MpStatus.internal, '$taskName returned an invalid entity.');
              }
              final Object? text = raw['text'];
              final Object? rawEmbedding = raw['embedding'];
              final Object? rawMetadata = raw['metadata'];
              if (text is! String ||
                  rawEmbedding is! List<Object?> ||
                  rawMetadata is! Map<Object?, Object?>) {
                throw MpException(MpStatus.internal, '$taskName returned an invalid entity.');
              }
              final List<double> embedding = rawEmbedding
                  .map((Object? value) {
                    if (value is num) return value.toDouble();
                    throw MpException(
                      MpStatus.internal,
                      '$taskName returned an invalid embedding.',
                    );
                  })
                  .toList(growable: false);
              return RagRetrievalEntity(
                text: text,
                embedding: embedding,
                metadata: _stringKeyedMap(rawMetadata, taskName),
              );
            })
            .toList(growable: false);
      });

  @override
  Future<String> generate(String query, RagRetrievalOptions options) => runExclusive(
    () => _bridge.invokeString('rag.generate', <String, Object?>{
      'handle': handle,
      'query': query,
      ..._ragRetrievalMap(options),
    }, task: taskName),
  );

  @override
  Stream<RagGenerationChunk> generateStreaming(String query, RagRetrievalOptions options) {
    ensureAvailable();
    final _RagStreamOperation operation = _bridge.startRagGeneration(handle, query, options);
    trackGeneration(operation.done);
    return operation.stream;
  }

  @override
  Future<void> close() async {
    if (isClosed) return;
    markClosed();
    await waitForActiveOperation();
    try {
      await _bridge.invokeVoid('rag.close', <String, Object?>{'handle': handle}, task: taskName);
    } finally {
      await Future.wait(_resources.map((_ModelLease resource) => resource.release()));
    }
  }
}

Map<String, Object?> _ragDocumentMap(RagDocument document) => <String, Object?>{
  'text': document.text,
  'metadata': document.metadata,
  'embeddingText': document.embeddingText,
};

Map<String, Object?> _ragRetrievalMap(RagRetrievalOptions options) => <String, Object?>{
  'topK': options.topK,
  'minSimilarityScore': options.minSimilarityScore,
  'task': options.task.name,
};

final class _MobileImageGenerator extends _MobileLlmTask implements ImageGeneratorBackend {
  _MobileImageGenerator._(int handle, this._resources) : super(handle, 'ImageGenerator');

  final List<_ModelLease> _resources;

  static Future<_MobileImageGenerator> create(ImageGeneratorOptions options) async {
    final Directory modelDirectory = Directory(options.modelDirectory).absolute;
    if (!modelDirectory.existsSync()) {
      throw MpException(
        MpStatus.notFound,
        'The image-generator model directory does not exist: ${modelDirectory.path}',
        task: 'ImageGenerator',
      );
    }
    final List<_ModelLease> resources = <_ModelLease>[];
    Future<String?> resolve(ModelAsset? asset) async {
      if (asset == null) return null;
      final _ModelLease resource = await _resolveModelFile(asset);
      resources.add(resource);
      return resource.path;
    }

    try {
      final ImageGeneratorConditionOptions? conditions = options.conditions;
      final Map<String, Object?> arguments = <String, Object?>{
        'modelDirectory': modelDirectory.path,
        'modelType': options.modelType.name,
        'loraWeightsPath': await resolve(options.loraWeights),
      };
      if (conditions?.face case final FaceConditionOptions face) {
        arguments['faceCondition'] = <String, Object?>{
          'pluginModelPath': await resolve(face.pluginModel.modelAsset),
          'faceModelPath': await resolve(face.faceModel.modelAsset),
          'minFaceDetectionConfidence': face.minFaceDetectionConfidence,
          'minFacePresenceConfidence': face.minFacePresenceConfidence,
        };
      }
      if (conditions?.edge case final EdgeConditionOptions edge) {
        arguments['edgeCondition'] = <String, Object?>{
          'pluginModelPath': await resolve(edge.pluginModel.modelAsset),
          'threshold1': edge.threshold1,
          'threshold2': edge.threshold2,
          'apertureSize': edge.apertureSize,
          'l2Gradient': edge.l2Gradient,
        };
      }
      if (conditions?.depth case final DepthConditionOptions depth) {
        arguments['depthCondition'] = <String, Object?>{
          'pluginModelPath': await resolve(depth.pluginModel.modelAsset),
          'depthModelPath': await resolve(depth.depthModel.modelAsset),
        };
      }
      final int handle = await _bridge.createTask(
        'imageGenerator.create',
        arguments,
        task: 'ImageGenerator',
      );
      return _MobileImageGenerator._(handle, resources);
    } on Object {
      await Future.wait(resources.map((_ModelLease resource) => resource.release()));
      rethrow;
    }
  }

  @override
  Future<ImageGeneratorResult> generate(
    String prompt, {
    required int iterations,
    required int seed,
    ImageGeneratorCondition? condition,
  }) => runExclusive(
    () => _invokeResult('imageGenerator.generate', <String, Object?>{
      'handle': handle,
      'prompt': prompt,
      'iterations': iterations,
      'seed': seed,
      ...?_conditionMap(condition),
    }),
  );

  @override
  Future<void> setInputs(
    String prompt, {
    required int iterations,
    required int seed,
    ImageGeneratorCondition? condition,
  }) => runExclusive(
    () => _bridge.invokeVoid('imageGenerator.setInputs', <String, Object?>{
      'handle': handle,
      'prompt': prompt,
      'iterations': iterations,
      'seed': seed,
      ...?_conditionMap(condition),
    }, task: taskName),
  );

  @override
  Future<ImageGeneratorResult?> execute({required bool showResult}) => runExclusive(() async {
    final Map<Object?, Object?>? result = await _bridge.invokeOptionalMap(
      'imageGenerator.execute',
      <String, Object?>{'handle': handle, 'showResult': showResult},
      task: taskName,
    );
    return result == null ? null : _readResult(result);
  });

  @override
  Future<MpImage> createConditionImage(MpImage image, ImageGeneratorConditionType type) =>
      runExclusive(() async {
        final Map<Object?, Object?> result = await _bridge.invokeMap(
          'imageGenerator.createConditionImage',
          <String, Object?>{
            'handle': handle,
            'conditionType': type.name,
            'image': _imageMap(image),
          },
          task: taskName,
        );
        return _readImage(result, taskName);
      });

  Future<ImageGeneratorResult> _invokeResult(String method, Map<String, Object?> arguments) async {
    final Map<Object?, Object?> result = await _bridge.invokeMap(method, arguments, task: taskName);
    return _readResult(result);
  }

  ImageGeneratorResult _readResult(Map<Object?, Object?> result) {
    final Object? generated = result['generatedImage'];
    if (generated is! Map<Object?, Object?>) {
      throw MpException(
        MpStatus.internal,
        '$taskName returned an invalid generated image.',
        task: taskName,
      );
    }
    final Object? rawCondition = result['conditionImage'];
    final Object? timestamp = result['timestampMs'];
    if (timestamp is! num) {
      throw MpException(
        MpStatus.internal,
        '$taskName returned an invalid timestamp.',
        task: taskName,
      );
    }
    return ImageGeneratorResult(
      generatedImage: _readImage(generated, taskName),
      conditionImage: rawCondition is Map<Object?, Object?>
          ? _readImage(rawCondition, taskName)
          : null,
      timestamp: Duration(milliseconds: timestamp.toInt()),
    );
  }

  @override
  Future<void> close() async {
    if (isClosed) return;
    markClosed();
    await waitForActiveOperation();
    try {
      await _bridge.invokeVoid('imageGenerator.close', <String, Object?>{
        'handle': handle,
      }, task: taskName);
    } finally {
      await Future.wait(_resources.map((_ModelLease resource) => resource.release()));
    }
  }
}

Map<String, Object?>? _conditionMap(ImageGeneratorCondition? condition) => condition == null
    ? null
    : <String, Object?>{'conditionType': condition.type.name, 'image': _imageMap(condition.image)};

Map<String, Object?> _imageMap(MpImage image) {
  if (image case MpImageUint8(:final data)) {
    if (image.format case MpImageFormat.srgb || MpImageFormat.srgba || MpImageFormat.gray8) {
      return <String, Object?>{
        'width': image.width,
        'height': image.height,
        'format': image.format.name,
        'data': data,
      };
    }
  }
  throw const MpException(
    MpStatus.unimplemented,
    'Android image generation supports only 8-bit sRGB, sRGBA, or grayscale images.',
    task: 'ImageGenerator',
  );
}

MpImage _readImage(Map<Object?, Object?> value, String task) {
  final Object? width = value['width'];
  final Object? height = value['height'];
  final Object? data = value['data'];
  if (width is! num || height is! num || data is! Uint8List) {
    throw MpException(MpStatus.internal, '$task returned invalid image data.', task: task);
  }
  return MpImage.uint8(
    width: width.toInt(),
    height: height.toInt(),
    format: MpImageFormat.srgba,
    data: data,
  );
}

Map<String, Object?> _sessionOptionsMap(
  LlmSessionOptions options, {
  String? loraPath,
  bool includeImmutable = true,
}) => <String, Object?>{
  'topK': options.topK,
  'topP': options.topP,
  'temperature': options.temperature,
  'randomSeed': options.randomSeed,
  if (includeImmutable) 'loraPath': loraPath,
  if (includeImmutable)
    if (options.graphOptions case final LlmGraphOptions graph) ...<String, Object?>{
      'includeTokenCostCalculator': graph.includeTokenCostCalculator,
      'enableVisionModality': graph.enableVisionModality,
      'enableAudioModality': graph.enableAudioModality,
    },
  if (includeImmutable)
    if (options.constraintHandle case final int handle) 'constraintHandle': handle,
  if (includeImmutable)
    if (options.promptTemplates case final PromptTemplates templates)
      'promptTemplates': <String, Object?>{
        'userPrefix': templates.userPrefix,
        'userSuffix': templates.userSuffix,
        'modelPrefix': templates.modelPrefix,
        'modelSuffix': templates.modelSuffix,
        'systemPrefix': templates.systemPrefix,
        'systemSuffix': templates.systemSuffix,
      },
};

final class _GenerationOperation {
  const _GenerationOperation({required this.stream, required this.response, required this.done});

  final Stream<LlmGenerationChunk> stream;
  final Future<String> response;
  final Future<void> done;
}

abstract interface class _PendingPlatformStream {
  void add(Map<Object?, Object?> event);

  void complete();

  void fail(Object error, [StackTrace? stackTrace]);
}

final class _PendingGeneration implements _PendingPlatformStream {
  final StreamController<LlmGenerationChunk> controller = StreamController<LlmGenerationChunk>();
  final Completer<String> response = Completer<String>();
  final StringBuffer text = StringBuffer();
  bool terminal = false;

  @override
  void add(Map<Object?, Object?> event) {
    if (terminal) return;
    final Object? rawText = event['text'];
    final Object? rawDone = event['isDone'];
    if (rawText is! String || rawDone is! bool) {
      fail(const MpException(MpStatus.internal, 'LlmSession returned an invalid stream event.'));
      return;
    }
    text.write(rawText);
    controller.add(LlmGenerationChunk(text: rawText, isDone: rawDone));
  }

  @override
  void complete() {
    if (terminal) return;
    terminal = true;
    response.complete(text.toString());
    unawaited(controller.close());
  }

  @override
  void fail(Object error, [StackTrace? stackTrace]) {
    if (terminal) return;
    terminal = true;
    response.completeError(error, stackTrace);
    controller.addError(error, stackTrace);
    unawaited(controller.close());
  }
}

final class _RagStreamOperation {
  const _RagStreamOperation(this.stream, this.done);

  final Stream<RagGenerationChunk> stream;
  final Future<void> done;
}

final class _PendingRagGeneration implements _PendingPlatformStream {
  final StreamController<RagGenerationChunk> controller = StreamController<RagGenerationChunk>();
  final Completer<void> completion = Completer<void>();
  bool terminal = false;

  @override
  void add(Map<Object?, Object?> event) {
    if (terminal) return;
    final Object? text = event['text'];
    final Object? isDone = event['isDone'];
    if (text is! String || isDone is! bool) {
      fail(const MpException(MpStatus.internal, 'RagPipeline returned an invalid stream event.'));
      return;
    }
    controller.add(RagGenerationChunk(text: text, isDone: isDone));
  }

  @override
  void complete() {
    if (terminal) return;
    terminal = true;
    completion.complete();
    unawaited(controller.close());
  }

  @override
  void fail(Object error, [StackTrace? stackTrace]) {
    if (terminal) return;
    terminal = true;
    completion.complete();
    controller.addError(error, stackTrace);
    unawaited(controller.close());
  }
}

final class _MobileGenAiBridge {
  _MobileGenAiBridge() {
    _events.receiveBroadcastStream().listen(_onEvent, onError: _onEventChannelError);
  }

  final Map<String, _PendingPlatformStream> _pending = <String, _PendingPlatformStream>{};
  var _nextRequest = 0;

  Future<int> createTask(
    String method,
    Map<String, Object?> arguments, {
    required String task,
  }) async {
    final Object? result = await _invoke(method, arguments, task: task);
    if (result is num) return result.toInt();
    throw MpException(MpStatus.internal, '$task creation returned an invalid handle.', task: task);
  }

  Future<int> invokeInt(
    String method,
    Map<String, Object?> arguments, {
    required String task,
  }) async {
    final Object? result = await _invoke(method, arguments, task: task);
    if (result is num) return result.toInt();
    throw MpException(MpStatus.internal, '$task returned a non-integer result.', task: task);
  }

  Future<bool> invokeBool(
    String method,
    Map<String, Object?> arguments, {
    required String task,
  }) async {
    final Object? result = await _invoke(method, arguments, task: task);
    if (result is bool) return result;
    throw MpException(MpStatus.internal, '$task returned a non-boolean result.', task: task);
  }

  Future<String> invokeString(
    String method,
    Map<String, Object?> arguments, {
    required String task,
  }) async {
    final Object? result = await _invoke(method, arguments, task: task);
    if (result is String) return result;
    throw MpException(MpStatus.internal, '$task returned a non-string result.', task: task);
  }

  Future<List<Object?>> invokeList(
    String method,
    Map<String, Object?> arguments, {
    required String task,
  }) async {
    final Object? result = await _invoke(method, arguments, task: task);
    if (result is List<Object?>) return result;
    throw MpException(MpStatus.internal, '$task returned an invalid list.', task: task);
  }

  Future<Map<Object?, Object?>> invokeMap(
    String method,
    Map<String, Object?> arguments, {
    required String task,
  }) async {
    final Object? result = await _invoke(method, arguments, task: task);
    if (result case final Map<Object?, Object?> map) return map;
    throw MpException(MpStatus.internal, '$task returned an invalid result.', task: task);
  }

  Future<Map<Object?, Object?>?> invokeOptionalMap(
    String method,
    Map<String, Object?> arguments, {
    required String task,
  }) async {
    final Object? result = await _invoke(method, arguments, task: task);
    if (result == null) return null;
    if (result case final Map<Object?, Object?> map) return map;
    throw MpException(MpStatus.internal, '$task returned an invalid result.', task: task);
  }

  Future<void> invokeVoid(
    String method,
    Map<String, Object?> arguments, {
    required String task,
  }) async {
    await _invoke(method, arguments, task: task);
  }

  _GenerationOperation startGeneration(int handle) {
    final String requestId = '${DateTime.now().microsecondsSinceEpoch}-${_nextRequest++}';
    final _PendingGeneration pending = _PendingGeneration();
    _pending[requestId] = pending;
    unawaited(
      _invoke('llm.generate', <String, Object?>{
        'handle': handle,
        'requestId': requestId,
      }, task: 'LlmSession').catchError((Object error, StackTrace stackTrace) {
        _pending.remove(requestId)?.fail(error, stackTrace);
        return null;
      }),
    );
    return _GenerationOperation(
      stream: pending.controller.stream,
      response: pending.response.future,
      done: pending.response.future.then<void>((_) {}, onError: (Object _, StackTrace _) {}),
    );
  }

  _RagStreamOperation startRagGeneration(int handle, String query, RagRetrievalOptions options) {
    final String requestId = '${DateTime.now().microsecondsSinceEpoch}-${_nextRequest++}';
    final _PendingRagGeneration pending = _PendingRagGeneration();
    _pending[requestId] = pending;
    unawaited(
      _invoke('rag.generateStreaming', <String, Object?>{
        'handle': handle,
        'requestId': requestId,
        'query': query,
        ..._ragRetrievalMap(options),
      }, task: 'RagPipeline').catchError((Object error, StackTrace stackTrace) {
        _pending.remove(requestId)?.fail(error, stackTrace);
        return null;
      }),
    );
    return _RagStreamOperation(pending.controller.stream, pending.completion.future);
  }

  Future<Object?> _invoke(
    String method,
    Map<String, Object?> arguments, {
    required String task,
  }) async {
    try {
      return await _methods.invokeMethod<Object?>(method, arguments);
    } on MissingPluginException catch (error) {
      throw MpException(
        MpStatus.unimplemented,
        'The $task Android plugin is not registered.',
        task: task,
        cause: error,
      );
    } on PlatformException catch (error) {
      throw MpException(
        _statusFromPlatformCode(error.code),
        error.message ?? '$task failed in the Android runtime.',
        task: task,
        cause: error,
      );
    }
  }

  void _onEvent(Object? rawEvent) {
    if (rawEvent is! Map<Object?, Object?>) return;
    final String? requestId = rawEvent['requestId'] as String?;
    if (requestId == null) return;
    final _PendingPlatformStream? pending = _pending[requestId];
    if (pending == null) return;
    switch (rawEvent['kind']) {
      case 'data':
        pending.add(rawEvent);
      case 'done':
        _pending.remove(requestId)?.complete();
      case 'error':
        final String message = rawEvent['message'] as String? ?? 'Generation failed.';
        final String code = rawEvent['code'] as String? ?? 'internal';
        _pending.remove(requestId)?.fail(MpException(_statusFromPlatformCode(code), message));
    }
  }

  void _onEventChannelError(Object error, StackTrace stackTrace) {
    final List<_PendingPlatformStream> pending = _pending.values.toList(growable: false);
    _pending.clear();
    for (final _PendingPlatformStream generation in pending) {
      generation.fail(error, stackTrace);
    }
  }
}

MpStatus _statusFromPlatformCode(String code) => switch (code) {
  'cancelled' => MpStatus.cancelled,
  'invalid_argument' => MpStatus.invalidArgument,
  'not_found' => MpStatus.notFound,
  'resource_exhausted' => MpStatus.resourceExhausted,
  'failed_precondition' => MpStatus.failedPrecondition,
  'unimplemented' => MpStatus.unimplemented,
  'unavailable' => MpStatus.unavailable,
  _ => MpStatus.internal,
};
