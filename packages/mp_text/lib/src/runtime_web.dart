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

  Future<({JSObject fileset, JSObject module})> _load() async {
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
  bool _isClosed = false;

  @override
  bool get isClosed => _isClosed;

  void ensureOpen() {
    if (_isClosed) {
      throw const MpException(MpStatus.failedPrecondition, 'The web task is closed.');
    }
  }

  @override
  Future<void> close() async {
    if (_isClosed) return;
    _isClosed = true;
    callWebMethod<JSAny?>(task, 'close');
  }
}

final class _WebLanguageDetector extends _WebTextTask implements LanguageDetectorBackend {
  _WebLanguageDetector(super.task);

  @override
  Future<LanguageDetectorResult> detect(String text) async {
    ensureOpen();
    final JSAny? raw = callWebMethod<JSAny?>(task, 'detect', <JSAny?>[text.toJS]);
    final Map<Object?, Object?> result = webDartify(raw)! as Map<Object?, Object?>;
    final List<Object?> languages = result['languages']! as List<Object?>;
    return LanguageDetectorResult(
      languages.map((Object? value) {
        final Map<Object?, Object?> prediction = value! as Map<Object?, Object?>;
        return LanguagePrediction(
          languageCode: prediction['languageCode']! as String,
          probability: (prediction['probability']! as num).toDouble(),
        );
      }),
    );
  }
}

final class _WebTextClassifier extends _WebTextTask implements TextClassifierBackend {
  _WebTextClassifier(super.task);

  @override
  Future<ClassificationResult> classify(String text) async {
    ensureOpen();
    final JSAny? raw = callWebMethod<JSAny?>(task, 'classify', <JSAny?>[text.toJS]);
    return webClassificationResult(webDartify(raw)! as Map<Object?, Object?>);
  }
}

final class _WebTextEmbedder extends _WebTextTask implements TextEmbedderBackend {
  _WebTextEmbedder(super.task);

  @override
  Future<EmbeddingResult> embed(String text, {TextEmbedderFormatContext? formatContext}) async {
    ensureOpen();
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
    final Map<Object?, Object?> result = webDartify(raw)! as Map<Object?, Object?>;
    final List<Object?> embeddings = result['embeddings']! as List<Object?>;
    return EmbeddingResult(
      timestampMs: webOptionalInt(result['timestampMs']),
      embeddings: embeddings.map((Object? value) {
        final Map<Object?, Object?> embedding = value! as Map<Object?, Object?>;
        final int headIndex = (embedding['headIndex']! as num).toInt();
        final String? headName = webEmptyToNull(embedding['headName'] as String?);
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
