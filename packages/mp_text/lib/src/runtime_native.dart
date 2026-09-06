import 'dart:async';
import 'dart:ffi' as ffi;

import 'package:mp_core/mp_core.dart';
import 'package:mp_core/native.dart' as native;

import 'language_detector.dart';
import 'platform_channel_stub.dart'
    if (dart.library.ui) 'platform_channel_flutter.dart'
    as platform_channel;
import 'runtime.dart';
import 'text_classifier.dart';
import 'text_embedder.dart';
import 'text_proofreader.dart';
import 'text_summarizer.dart';

/// Creates the MediaPipe C runtime used on native Dart and Flutter platforms.
TextRuntime createTextRuntime() => const _NativeTextRuntime();

final class _NativeTextRuntime implements TextRuntime {
  const _NativeTextRuntime();

  @override
  Future<LanguageDetectorBackend> createLanguageDetector(LanguageDetectorOptions options) async {
    final LanguageDetectorOptions resolved = LanguageDetectorOptions(
      baseOptions: await _resolveBaseOptions(options.baseOptions),
      classifierOptions: options.classifierOptions,
    );
    return _NativeLanguageDetector(
      await _spawnTextWorker(_TextTaskKind.languageDetector, resolved),
    );
  }

  @override
  Future<TextClassifierBackend> createTextClassifier(TextClassifierOptions options) async {
    final TextClassifierOptions resolved = TextClassifierOptions(
      baseOptions: await _resolveBaseOptions(options.baseOptions),
      classifierOptions: options.classifierOptions,
    );
    return _NativeTextClassifier(await _spawnTextWorker(_TextTaskKind.textClassifier, resolved));
  }

  @override
  Future<TextEmbedderBackend> createTextEmbedder(TextEmbedderOptions options) async {
    final TextEmbedderOptions resolved = TextEmbedderOptions(
      baseOptions: await _resolveBaseOptions(options.baseOptions),
      embedderOptions: options.embedderOptions,
    );
    return _NativeTextEmbedder(await _spawnTextWorker(_TextTaskKind.textEmbedder, resolved));
  }

  @override
  Future<TextProofreaderBackend> createTextProofreader(TextProofreaderOptions options) =>
      platform_channel.createPlatformTextProofreader(options);

  @override
  Future<TextSummarizerBackend> createTextSummarizer(TextSummarizerOptions options) =>
      platform_channel.createPlatformTextSummarizer(options);
}

final class _NativeLanguageDetector implements LanguageDetectorBackend {
  _NativeLanguageDetector(this._worker);

  final native.NativeTaskIsolate _worker;
  final _SerialQueue _queue = _SerialQueue();
  var _closed = false;

  @override
  bool get isClosed => _closed;

  @override
  Future<LanguageDetectorResult> detect(String text) =>
      _queue.run(() => _worker.request<LanguageDetectorResult>(_TextRequest(text)));

  @override
  Future<void> close() => _queue.run(() async {
    if (_closed) return;
    _closed = true;
    await _worker.request<void>(_TextClose.instance);
    await _worker.dispose();
  });
}

final class _NativeTextClassifier implements TextClassifierBackend {
  _NativeTextClassifier(this._worker);

  final native.NativeTaskIsolate _worker;
  final _SerialQueue _queue = _SerialQueue();
  var _closed = false;

  @override
  bool get isClosed => _closed;

  @override
  Future<ClassificationResult> classify(String text) =>
      _queue.run(() => _worker.request<ClassificationResult>(_TextRequest(text)));

  @override
  Future<void> close() => _queue.run(() async {
    if (_closed) return;
    _closed = true;
    await _worker.request<void>(_TextClose.instance);
    await _worker.dispose();
  });
}

final class _NativeTextEmbedder implements TextEmbedderBackend {
  _NativeTextEmbedder(this._worker);

  final native.NativeTaskIsolate _worker;
  final _SerialQueue _queue = _SerialQueue();
  var _closed = false;

  @override
  bool get isClosed => _closed;

  @override
  Future<EmbeddingResult> embed(String text, {TextEmbedderFormatContext? formatContext}) =>
      _queue.run(
        () => _worker.request<EmbeddingResult>(_TextRequest(text, formatContext: formatContext)),
      );

  @override
  Future<void> close() => _queue.run(() async {
    if (_closed) return;
    _closed = true;
    await _worker.request<void>(_TextClose.instance);
    await _worker.dispose();
  });
}

enum _TextTaskKind { languageDetector, textClassifier, textEmbedder }

final class _TextWorkerInit {
  const _TextWorkerInit(this.kind, this.options);

  final _TextTaskKind kind;
  final Object options;
}

final class _TextRequest {
  const _TextRequest(this.text, {this.formatContext});

  final String text;
  final TextEmbedderFormatContext? formatContext;
}

final class _TextClose {
  const _TextClose._();

  static const _TextClose instance = _TextClose._();
}

Future<native.NativeTaskIsolate> _spawnTextWorker(_TextTaskKind kind, Object options) =>
    native.NativeTaskIsolate.spawn(
      factory: _createTextWorker,
      initialMessage: _TextWorkerInit(kind, options),
      debugName: 'mp_text.${kind.name}',
    );

native.NativeTaskWorkerHandler _createTextWorker(Object? initialMessage) {
  final _TextWorkerInit initialization = initialMessage! as _TextWorkerInit;
  final int address = switch (initialization.kind) {
    _TextTaskKind.languageDetector => _createLanguageDetector(
      initialization.options as LanguageDetectorOptions,
    ),
    _TextTaskKind.textClassifier => _createTextClassifier(
      initialization.options as TextClassifierOptions,
    ),
    _TextTaskKind.textEmbedder => _createTextEmbedder(
      initialization.options as TextEmbedderOptions,
    ),
  };
  return (Object? command) {
    if (command is _TextClose) {
      switch (initialization.kind) {
        case _TextTaskKind.languageDetector:
          _closeLanguageDetector(address);
          return null;
        case _TextTaskKind.textClassifier:
          _closeTextClassifier(address);
          return null;
        case _TextTaskKind.textEmbedder:
          _closeTextEmbedder(address);
          return null;
      }
    }
    final _TextRequest request = command! as _TextRequest;
    return switch (initialization.kind) {
      _TextTaskKind.languageDetector => _detectLanguage(address, request.text),
      _TextTaskKind.textClassifier => _classifyText(address, request.text),
      _TextTaskKind.textEmbedder => _embedText(address, request.text, request.formatContext),
    };
  };
}

final class _SerialQueue {
  Future<void> _tail = Future<void>.value();

  Future<T> run<T>(Future<T> Function() action) {
    final Future<T> operation = _tail.then((_) => action());
    _tail = operation.then<void>((_) {}, onError: (Object _, StackTrace _) {});
    return operation;
  }
}

Future<BaseOptions> _resolveBaseOptions(BaseOptions options) async => BaseOptions(
  modelAsset: await native.resolveNativeModelAsset(options.modelAsset),
  delegate: options.delegate,
  liteRtOptions: options.liteRtOptions,
);

int _createLanguageDetector(LanguageDetectorOptions options) {
  final native.NativeScope scope = native.NativeScope(task: 'LanguageDetector');
  try {
    final ffi.Pointer<native.MpLanguageDetectorOptions> nativeOptions = scope
        .allocator<native.MpLanguageDetectorOptions>();
    nativeOptions.ref
      ..base_options = scope.baseOptions(options.baseOptions).ref
      ..classifier_options = scope.classifierOptions(options.classifierOptions).ref;
    final ffi.Pointer<native.MpLanguageDetectorPtr> output = scope
        .allocator<native.MpLanguageDetectorPtr>();
    final ffi.Pointer<ffi.Pointer<ffi.Char>> error = scope.errorOutput();
    scope.check(native.MpLanguageDetectorCreate(nativeOptions, output, error), error);
    return output.value.address;
  } finally {
    scope.release();
  }
}

LanguageDetectorResult _detectLanguage(int address, String text) {
  final native.NativeScope scope = native.NativeScope(task: 'LanguageDetector');
  final ffi.Pointer<native.MpLanguageDetectorResult> result = scope
      .allocator<native.MpLanguageDetectorResult>();
  var ownsResult = false;
  try {
    final ffi.Pointer<ffi.Pointer<ffi.Char>> error = scope.errorOutput();
    scope.check(
      native.MpLanguageDetectorDetect(
        ffi.Pointer<native.MpLanguageDetectorInternal>.fromAddress(address),
        scope.string(text),
        result,
        error,
      ),
      error,
    );
    ownsResult = true;
    return LanguageDetectorResult(
      List<LanguagePrediction>.generate(result.ref.predictions_count, (int index) {
        final native.MpLanguageDetectorPrediction prediction = result.ref.predictions[index];
        return LanguagePrediction(
          languageCode: native.nativeString(prediction.language_code) ?? '',
          probability: prediction.probability,
        );
      }, growable: false),
    );
  } finally {
    if (ownsResult) native.MpLanguageDetectorCloseResult(result);
    scope.release();
  }
}

void _closeLanguageDetector(int address) {
  final native.NativeScope scope = native.NativeScope(task: 'LanguageDetector');
  try {
    final ffi.Pointer<ffi.Pointer<ffi.Char>> error = scope.errorOutput();
    scope.check(
      native.MpLanguageDetectorClose(
        ffi.Pointer<native.MpLanguageDetectorInternal>.fromAddress(address),
        error,
      ),
      error,
    );
  } finally {
    scope.release();
  }
}

int _createTextClassifier(TextClassifierOptions options) {
  final native.NativeScope scope = native.NativeScope(task: 'TextClassifier');
  try {
    final ffi.Pointer<native.MpTextClassifierOptions> nativeOptions = scope
        .allocator<native.MpTextClassifierOptions>();
    nativeOptions.ref
      ..base_options = scope.baseOptions(options.baseOptions).ref
      ..classifier_options = scope.classifierOptions(options.classifierOptions).ref;
    final ffi.Pointer<native.MpTextClassifierPtr> output = scope
        .allocator<native.MpTextClassifierPtr>();
    final ffi.Pointer<ffi.Pointer<ffi.Char>> error = scope.errorOutput();
    scope.check(native.MpTextClassifierCreate(nativeOptions, output, error), error);
    return output.value.address;
  } finally {
    scope.release();
  }
}

ClassificationResult _classifyText(int address, String text) {
  final native.NativeScope scope = native.NativeScope(task: 'TextClassifier');
  final ffi.Pointer<native.MpTextClassifierResult> result = scope
      .allocator<native.MpTextClassifierResult>();
  var ownsResult = false;
  try {
    final ffi.Pointer<ffi.Pointer<ffi.Char>> error = scope.errorOutput();
    scope.check(
      native.MpTextClassifierClassify(
        ffi.Pointer<native.MpTextClassifierInternal>.fromAddress(address),
        scope.string(text),
        result,
        error,
      ),
      error,
    );
    ownsResult = true;
    return native.classificationResultFromNative(result.ref);
  } finally {
    if (ownsResult) native.MpTextClassifierCloseResult(result);
    scope.release();
  }
}

void _closeTextClassifier(int address) {
  final native.NativeScope scope = native.NativeScope(task: 'TextClassifier');
  try {
    final ffi.Pointer<ffi.Pointer<ffi.Char>> error = scope.errorOutput();
    scope.check(
      native.MpTextClassifierClose(
        ffi.Pointer<native.MpTextClassifierInternal>.fromAddress(address),
        error,
      ),
      error,
    );
  } finally {
    scope.release();
  }
}

int _createTextEmbedder(TextEmbedderOptions options) {
  final native.NativeScope scope = native.NativeScope(task: 'TextEmbedder');
  try {
    final ffi.Pointer<native.MpTextEmbedderOptions> nativeOptions = scope
        .allocator<native.MpTextEmbedderOptions>();
    nativeOptions.ref
      ..base_options = scope.baseOptions(options.baseOptions).ref
      ..embedder_options = scope.embedderOptions(options.embedderOptions).ref;
    final ffi.Pointer<native.MpTextEmbedderPtr> output = scope
        .allocator<native.MpTextEmbedderPtr>();
    final ffi.Pointer<ffi.Pointer<ffi.Char>> error = scope.errorOutput();
    scope.check(native.MpTextEmbedderCreate(nativeOptions, output, error), error);
    return output.value.address;
  } finally {
    scope.release();
  }
}

EmbeddingResult _embedText(int address, String text, TextEmbedderFormatContext? formatContext) {
  final native.NativeScope scope = native.NativeScope(task: 'TextEmbedder');
  final ffi.Pointer<native.MpTextEmbedderResult> result = scope
      .allocator<native.MpTextEmbedderResult>();
  var ownsResult = false;
  try {
    final ffi.Pointer<native.MpTextEmbedderFormatContext> nativeContext = switch (formatContext) {
      null => ffi.nullptr,
      final TextEmbedderFormatContext value => native.MpTextEmbedderFormatContext.$allocate(
        scope.allocator,
        task_type: _embeddingType(value.taskType),
        title: scope.string(value.title),
        role: _embeddingRole(value.role),
      ),
    };
    final ffi.Pointer<ffi.Pointer<ffi.Char>> error = scope.errorOutput();
    scope.check(
      native.MpTextEmbedderEmbed(
        ffi.Pointer<native.MpTextEmbedderInternal>.fromAddress(address),
        scope.string(text),
        nativeContext,
        result,
        error,
      ),
      error,
    );
    ownsResult = true;
    return native.embeddingResultFromNative(result.ref);
  } finally {
    if (ownsResult) native.MpTextEmbedderCloseResult(result);
    scope.release();
  }
}

void _closeTextEmbedder(int address) {
  final native.NativeScope scope = native.NativeScope(task: 'TextEmbedder');
  try {
    final ffi.Pointer<ffi.Pointer<ffi.Char>> error = scope.errorOutput();
    scope.check(
      native.MpTextEmbedderClose(
        ffi.Pointer<native.MpTextEmbedderInternal>.fromAddress(address),
        error,
      ),
      error,
    );
  } finally {
    scope.release();
  }
}

native.MpTextEmbedderEmbeddingType _embeddingType(TextEmbeddingType value) => switch (value) {
  TextEmbeddingType.retrievalQuery =>
    native.MpTextEmbedderEmbeddingType.MP_TEXT_EMBEDDER_EMBEDDING_TYPE_RETRIEVAL_QUERY,
  TextEmbeddingType.retrievalDocument =>
    native.MpTextEmbedderEmbeddingType.MP_TEXT_EMBEDDER_EMBEDDING_TYPE_RETRIEVAL_DOCUMENT,
  TextEmbeddingType.semanticSimilarity =>
    native.MpTextEmbedderEmbeddingType.MP_TEXT_EMBEDDER_EMBEDDING_TYPE_SEMANTIC_SIMILARITY,
  TextEmbeddingType.classification =>
    native.MpTextEmbedderEmbeddingType.MP_TEXT_EMBEDDER_EMBEDDING_TYPE_CLASSIFICATION,
  TextEmbeddingType.clustering =>
    native.MpTextEmbedderEmbeddingType.MP_TEXT_EMBEDDER_EMBEDDING_TYPE_CLUSTERING,
  TextEmbeddingType.questionAnswering =>
    native.MpTextEmbedderEmbeddingType.MP_TEXT_EMBEDDER_EMBEDDING_TYPE_QUESTION_ANSWERING,
  TextEmbeddingType.factChecking =>
    native.MpTextEmbedderEmbeddingType.MP_TEXT_EMBEDDER_EMBEDDING_TYPE_FACT_CHECKING,
  TextEmbeddingType.codeRetrieval =>
    native.MpTextEmbedderEmbeddingType.MP_TEXT_EMBEDDER_EMBEDDING_TYPE_CODE_RETRIEVAL,
};

native.MpTextEmbedderRole _embeddingRole(TextEmbeddingRole value) => switch (value) {
  TextEmbeddingRole.query => native.MpTextEmbedderRole.MP_TEXT_EMBEDDER_ROLE_QUERY,
  TextEmbeddingRole.document => native.MpTextEmbedderRole.MP_TEXT_EMBEDDER_ROLE_DOCUMENT,
};
