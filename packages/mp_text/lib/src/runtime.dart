import 'package:mp_core/mp_core.dart';

import 'language_detector.dart';
import 'runtime_stub.dart'
    if (dart.library.io) 'runtime_native.dart'
    if (dart.library.js_interop) 'runtime_web.dart'
    as platform;
import 'text_classifier.dart';
import 'text_embedder.dart';
import 'text_proofreader.dart';
import 'text_summarizer.dart';

/// A platform adapter capable of creating MediaPipe text task backends.
abstract interface class TextRuntime {
  /// Creates a language detector backend.
  Future<LanguageDetectorBackend> createLanguageDetector(LanguageDetectorOptions options);

  /// Creates a text classifier backend.
  Future<TextClassifierBackend> createTextClassifier(TextClassifierOptions options);

  /// Creates a text embedder backend.
  Future<TextEmbedderBackend> createTextEmbedder(TextEmbedderOptions options);

  /// Creates a text proofreader backend.
  Future<TextProofreaderBackend> createTextProofreader(TextProofreaderOptions options);

  /// Creates a text summarizer backend.
  Future<TextSummarizerBackend> createTextSummarizer(TextSummarizerOptions options);
}

/// The adapter selected for the active platform.
TextRuntime get defaultTextRuntime => platform.createTextRuntime();

/// An adapter used when the current build has no linked MediaPipe runtime.
final class UnsupportedTextRuntime implements TextRuntime {
  /// Creates an unsupported adapter for [platform].
  const UnsupportedTextRuntime(this.platform);

  /// The platform for which no implementation was linked.
  final MpPlatform platform;

  Never _unsupported(String task) => throw MpException(
    MpStatus.unimplemented,
    'No $task backend is linked for ${platform.name}.',
    task: task,
  );

  @override
  Future<LanguageDetectorBackend> createLanguageDetector(LanguageDetectorOptions options) async =>
      _unsupported('LanguageDetector');

  @override
  Future<TextClassifierBackend> createTextClassifier(TextClassifierOptions options) async =>
      _unsupported('TextClassifier');

  @override
  Future<TextEmbedderBackend> createTextEmbedder(TextEmbedderOptions options) async =>
      _unsupported('TextEmbedder');

  @override
  Future<TextProofreaderBackend> createTextProofreader(TextProofreaderOptions options) async =>
      _unsupported('TextProofreader');

  @override
  Future<TextSummarizerBackend> createTextSummarizer(TextSummarizerOptions options) async =>
      _unsupported('TextSummarizer');
}
