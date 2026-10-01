import 'package:meta/meta.dart';
import 'package:mp_core/mp_core.dart';

import 'runtime.dart';

/// Output format used by [TextSummarizer].
enum TextSummarizerMode {
  /// A short summary paragraph.
  tldr,

  /// A short list of key points.
  keyPoints,
}

/// Configuration for a [TextSummarizer].
@immutable
final class TextSummarizerOptions {
  /// Creates text summarizer options.
  TextSummarizerOptions({
    required this.baseOptions,
    this.mode = TextSummarizerMode.keyPoints,
    this.maxTokens,
  }) {
    if (baseOptions.delegate != MpDelegate.cpu) {
      throw ArgumentError.value(
        baseOptions.delegate,
        'baseOptions.delegate',
        'TextSummarizer supports only the CPU delegate',
      );
    }
    if (maxTokens case final int value when value <= 0) {
      throw ArgumentError.value(value, 'maxTokens', 'must be greater than zero');
    }
  }

  /// Model and hardware configuration.
  final BaseOptions baseOptions;

  /// Shape of the requested summary.
  final TextSummarizerMode mode;

  /// Maximum combined input and output token count.
  ///
  /// A `null` value lets the model choose its supported capacity.
  final int? maxTokens;
}

/// Complete output from a text summarization call.
@immutable
final class TextSummarizerResult {
  /// Creates a summarization result.
  const TextSummarizerResult(this.summary);

  /// Generated summary.
  final String summary;

  @override
  bool operator ==(Object other) =>
      identical(this, other) || other is TextSummarizerResult && summary == other.summary;

  @override
  int get hashCode => summary.hashCode;
}

/// One incremental update from [TextSummarizer.summarizeStreaming].
@immutable
final class TextSummarizerChunk {
  /// Creates a summarization update.
  const TextSummarizerChunk({required this.text, required this.isDone});

  /// Newly generated text since the preceding update.
  final String text;

  /// Whether this is the final update.
  final bool isDone;
}

/// Platform implementation used by [TextSummarizer].
abstract interface class TextSummarizerBackend implements MpTask {
  /// Summarizes [text] and waits for the complete result.
  Future<TextSummarizerResult> summarize(String text);

  /// Summarizes [text] and emits incremental output.
  Stream<TextSummarizerChunk> summarizeStreaming(String text);
}

/// Generates either a short paragraph or key points from input text.
final class TextSummarizer implements MpTask {
  TextSummarizer._(this._backend);

  final TextSummarizerBackend _backend;
  final TaskLifecycle _lifecycle = TaskLifecycle('TextSummarizer');

  /// Creates a summarizer using [runtime], or the active platform adapter.
  static Future<TextSummarizer> create(
    TextSummarizerOptions options, {
    TextRuntime? runtime,
  }) async => TextSummarizer._(await (runtime ?? defaultTextRuntime).createTextSummarizer(options));

  @override
  bool get isClosed => _lifecycle.isClosed;

  /// Summarizes [text] and waits for the complete result.
  Future<TextSummarizerResult> summarize(String text) {
    _lifecycle.ensureOpen();
    return _backend.summarize(text);
  }

  /// Summarizes [text] and emits incremental output.
  Stream<TextSummarizerChunk> summarizeStreaming(String text) {
    _lifecycle.ensureOpen();
    return _backend.summarizeStreaming(text);
  }

  @override
  Future<void> close() async {
    if (!_lifecycle.markClosed()) return;
    await _backend.close();
  }
}
