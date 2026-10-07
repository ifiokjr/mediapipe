import 'dart:async';
import 'dart:js_interop';
import 'dart:typed_data';

import 'package:mp_core/mp_core.dart';
import 'package:mp_core/web.dart';

import 'language_detector.dart';
import 'runtime.dart';
import 'text_classifier.dart';
import 'text_embedder.dart';
import 'text_proofreader.dart';
import 'text_summarizer.dart';

final WebTaskAssets _defaultAssets = WebTaskAssets(
  moduleUri: Uri.parse('https://cdn.jsdelivr.net/npm/@mediapipe/tasks-text@1.0.1/text_bundle.mjs'),
  wasmRoot: Uri.parse('https://cdn.jsdelivr.net/npm/@mediapipe/tasks-text@1.0.1/wasm'),
);

/// Creates the default web text runtime.
TextRuntime createTextRuntime() => WebTextRuntime();

/// Browser runtime backed by the official `@mediapipe/tasks-text` package.
final class WebTextRuntime implements TextRuntime {
  /// Creates a runtime using [assets].
  WebTextRuntime({WebTaskAssets? assets}) : assets = assets ?? _defaultAssets;

  /// Locations of the JavaScript module and Wasm files.
  final WebTaskAssets assets;

  Future<({JSObject fileset, JSObject module})>? _loaded;

  Future<({JSObject fileset, JSObject module})> _load() =>
      _loaded ??= _loadOnce().catchError((Object error, StackTrace stackTrace) {
        // A failed load stays failed for the app's lifetime if it is cached,
        // so clear it and let the next task creation retry.
        _loaded = null;
        Error.throwWithStackTrace(error, stackTrace);
      });

  Future<({JSObject fileset, JSObject module})> _loadOnce() async {
    final JSObject module = await importWebTaskModule(assets.moduleUri);
    final JSObject resolver = requireWebObject(module, 'FilesetResolver');
    final JSPromise<JSObject> promise = callWebMethod<JSPromise<JSObject>>(
      resolver,
      'forTextTasks',
      <JSAny?>[assets.wasmRoot.toString().toJS],
    );

    return (fileset: await promise.toDart, module: module);
  }

  Future<JSObject> _create(String task, Map<String, Object?> options) async {
    final ({JSObject fileset, JSObject module}) loaded = await _load();
    final JSObject taskClass = requireWebObject(loaded.module, task);
    final JSPromise<JSObject> promise = callWebMethod<JSPromise<JSObject>>(
      taskClass,
      'createFromOptions',
      <JSAny?>[loaded.fileset, webJsify(options)],
    );
    try {
      return await promise.toDart;
    } on Object catch (error) {
      throw MpException(
        MpStatus.internal,
        'MediaPipe could not create $task.',
        task: task,
        cause: error,
      );
    }
  }

  @override
  Future<LanguageDetectorBackend> createLanguageDetector(LanguageDetectorOptions options) async =>
      _WebLanguageDetector(
        await _create('LanguageDetector', <String, Object?>{
          'baseOptions': await resolveWebBaseOptions(options.baseOptions),
          ...webClassifierOptions(options.classifierOptions),
        }),
      );

  @override
  Future<TextClassifierBackend> createTextClassifier(TextClassifierOptions options) async =>
      _WebTextClassifier(
        await _create('TextClassifier', <String, Object?>{
          'baseOptions': await resolveWebBaseOptions(options.baseOptions),
          ...webClassifierOptions(options.classifierOptions),
        }),
      );

  @override
  Future<TextEmbedderBackend> createTextEmbedder(TextEmbedderOptions options) async =>
      _WebTextEmbedder(
        await _create('TextEmbedder', <String, Object?>{
          'baseOptions': await resolveWebBaseOptions(options.baseOptions),
          ...webEmbedderOptions(options.embedderOptions),
        }),
      );

  @override
  Future<TextProofreaderBackend> createTextProofreader(TextProofreaderOptions options) async =>
      throw const MpException(
        MpStatus.unimplemented,
        'TextProofreader is not exported by @mediapipe/tasks-text.',
        task: 'TextProofreader',
      );

  @override
  Future<TextSummarizerBackend> createTextSummarizer(TextSummarizerOptions options) async =>
      throw const MpException(
        MpStatus.unimplemented,
        'TextSummarizer is not exported by @mediapipe/tasks-text.',
        task: 'TextSummarizer',
      );
}

abstract base class _WebTextTask implements MpTask {
  _WebTextTask(this.task);

  final JSObject task;
  Future<void> _pending = Future<void>.value();
  Future<void>? _closing;
  bool _isClosed = false;

  @override
  bool get isClosed => _isClosed;

  void ensureOpen() {
    if (_isClosed) {
      throw const MpException(MpStatus.failedPrecondition, 'The web task is closed.');
    }
  }

  /// Runs [action] serialized against other calls and a pending [close].
  Future<R> runSerialized<R>(FutureOr<R> Function() action) {
    ensureOpen();
    final Future<R> operation = _pending.then((_) => action());
    _pending = operation.then<void>((_) {}, onError: (Object _, StackTrace _) {});

    return operation;
  }

  @override
  Future<void> close() {
    _isClosed = true;

    return _closing ??= _pending
        .then((_) {
          callWebMethod<JSAny?>(task, 'close');
        })
        .catchError((Object error, StackTrace stackTrace) {
          // Let a failed close be retried instead of caching the rejection.
          _closing = null;
          Error.throwWithStackTrace(error, stackTrace);
        });
  }
}

final class _WebLanguageDetector extends _WebTextTask implements LanguageDetectorBackend {
  _WebLanguageDetector(super.task);

  @override
  Future<LanguageDetectorResult> detect(String text) => runSerialized(() {
    final JSAny? raw = callWebMethod<JSAny?>(task, 'detect', <JSAny?>[text.toJS]);
    final Map<Object?, Object?> result = _requireMap(webDartify(raw), 'languages result');
    final List<Object?> languages = _requireList(result['languages'], 'languages');
    return LanguageDetectorResult(
      languages.map((Object? value) {
        final Map<Object?, Object?> prediction = _requireMap(value, 'language prediction');
        return LanguagePrediction(
          languageCode: _requireString(prediction['languageCode'], 'languageCode'),
          probability: _requireDouble(prediction['probability'], 'probability'),
        );
      }),
    );
  });
}

final class _WebTextClassifier extends _WebTextTask implements TextClassifierBackend {
  _WebTextClassifier(super.task);

  @override
  Future<ClassificationResult> classify(String text) => runSerialized(() {
    final JSAny? raw = callWebMethod<JSAny?>(task, 'classify', <JSAny?>[text.toJS]);

    return webClassificationResult(_requireMap(webDartify(raw), 'classification result'));
  });
}

final class _WebTextEmbedder extends _WebTextTask implements TextEmbedderBackend {
  _WebTextEmbedder(super.task);

  @override
  Future<EmbeddingResult> embed(String text, {TextEmbedderFormatContext? formatContext}) =>
      runSerialized(() => _embed(text, formatContext));

  Future<EmbeddingResult> _embed(String text, TextEmbedderFormatContext? formatContext) async {
    final List<JSAny?> arguments = <JSAny?>[text.toJS];

    if (formatContext != null) {
      arguments.add(
        webJsify(<String, Object?>{
          'type': switch (formatContext.taskType) {
            TextEmbeddingType.retrievalQuery => 'RETRIEVAL_QUERY',
            TextEmbeddingType.retrievalDocument => 'RETRIEVAL_DOCUMENT',
            TextEmbeddingType.semanticSimilarity => 'SEMANTIC_SIMILARITY',
            TextEmbeddingType.classification => 'CLASSIFICATION',
            TextEmbeddingType.clustering => 'CLUSTERING',
            TextEmbeddingType.questionAnswering => 'QUESTION_ANSWERING',
            TextEmbeddingType.factChecking => 'FACT_CHECKING',
            TextEmbeddingType.codeRetrieval => 'CODE_RETRIEVAL',
          },
          'textRole': switch (formatContext.role) {
            TextEmbeddingRole.query => 'QUERY',
            TextEmbeddingRole.document => 'DOCUMENT',
          },
          if (formatContext.title case final String title) 'title': title,
        }),
      );
    }

    final JSAny? raw = callWebMethod<JSAny?>(task, 'embed', arguments);
    final Map<Object?, Object?> result = _requireMap(webDartify(raw), 'embedding result');
    final List<Object?> embeddings = _requireList(result['embeddings'], 'embeddings');
    return EmbeddingResult(
      timestampMs: webOptionalInt(result['timestampMs']),
      embeddings: embeddings.map((Object? value) {
        final Map<Object?, Object?> embedding = _requireMap(value, 'embedding');
        final int headIndex = _requireInt(embedding['headIndex'], 'headIndex');
        final String? headName = webEmptyToNull(
          embedding['headName'] == null ? null : _requireString(embedding['headName'], 'headName'),
        );
        if (embedding['floatEmbedding'] case final List<Object?> values when values.isNotEmpty) {
          return Embedding.float(
            Float32List.fromList(values.cast<num>().map((num value) => value.toDouble()).toList()),
            headIndex: headIndex,
            headName: headName,
          );
        }

        final Object? quantized = embedding['quantizedEmbedding'];
        final Uint8List values = switch (quantized) {
          final Uint8List bytes => bytes,
          final List<Object?> bytes => Uint8List.fromList(
            bytes.cast<num>().map((e) => e.toInt()).toList(),
          ),
          _ => throw const MpException(MpStatus.internal, 'MediaPipe returned an empty embedding.'),
        };
        return Embedding.quantized(values, headIndex: headIndex, headName: headName);
      }),
    );
  }
}

Map<Object?, Object?> _requireMap(Object? value, String field) {
  if (value is! Map<Object?, Object?>) {
    throw _malformedTextResult(field);
  }

  return value;
}

List<Object?> _requireList(Object? value, String field) {
  if (value is! List<Object?>) {
    throw _malformedTextResult(field);
  }

  return value;
}

int _requireInt(Object? value, String field) {
  if (value is num) return value.toInt();

  throw _malformedTextResult(field);
}

double _requireDouble(Object? value, String field) {
  if (value is num) return value.toDouble();

  throw _malformedTextResult(field);
}

String _requireString(Object? value, String field) {
  if (value is String) return value;

  throw _malformedTextResult(field);
}

MpException _malformedTextResult(String field) => MpException(
  MpStatus.internal,
  'The MediaPipe web runtime returned a malformed result: expected $field.',
);
