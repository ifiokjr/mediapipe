import 'package:collection/collection.dart';
import 'package:meta/meta.dart';
import 'package:mp_core/mp_core.dart';

import 'runtime.dart';

/// Configuration for a [TextProofreader].
@immutable
final class TextProofreaderOptions {
  /// Creates text proofreader options.
  TextProofreaderOptions({required this.baseOptions, this.maxTokens}) {
    if (baseOptions.delegate != MpDelegate.cpu) {
      throw ArgumentError.value(
        baseOptions.delegate,
        'baseOptions.delegate',
        'TextProofreader supports only the CPU delegate',
      );
    }
    if (maxTokens case final int value when value <= 0) {
      throw ArgumentError.value(value, 'maxTokens', 'must be greater than zero');
    }
  }

  /// Model and hardware configuration.
  final BaseOptions baseOptions;

  /// Maximum combined input and output token count.
  ///
  /// A `null` value lets the model choose its supported capacity.
  final int? maxTokens;
}

/// How one segment relates the original text to the corrected text.
enum TextCorrectionType {
  /// Text retained without a change.
  same,

  /// Text inserted into the corrected output.
  insertion,

  /// Text removed from the original input.
  deletion,
}

/// One segment in the diff between the original and corrected text.
@immutable
final class TextCorrection {
  /// Creates a correction segment.
  const TextCorrection({required this.type, required this.text});

  /// The segment operation.
  final TextCorrectionType type;

  /// Text associated with the operation.
  final String text;

  @override
  bool operator ==(Object other) =>
      identical(this, other) || other is TextCorrection && type == other.type && text == other.text;

  @override
  int get hashCode => Object.hash(type, text);
}

/// Complete corrected text and its ordered diff segments.
@immutable
final class TextProofreaderResult {
  /// Creates an immutable proofreading result.
  TextProofreaderResult({required this.text, Iterable<TextCorrection> corrections = const []})
    : corrections = List<TextCorrection>.unmodifiable(corrections);

  /// Corrected text with all insertions and deletions applied.
  final String text;

  /// Ordered unchanged, inserted, and deleted segments.
  final List<TextCorrection> corrections;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is TextProofreaderResult &&
          text == other.text &&
          const ListEquality<TextCorrection>().equals(corrections, other.corrections);

  @override
  int get hashCode => Object.hash(text, const ListEquality<TextCorrection>().hash(corrections));
}

/// One incremental update from [TextProofreader.proofreadStreaming].
@immutable
final class TextProofreaderChunk {
  /// Creates an immutable proofreading update.
  TextProofreaderChunk({
    required this.text,
    required this.isDone,
    Iterable<TextCorrection> corrections = const [],
  }) : corrections = List<TextCorrection>.unmodifiable(corrections);

  /// Newly generated text since the preceding update.
  final String text;

  /// Whether this is the final update.
  final bool isDone;

  /// Final ordered diff segments, populated by the upstream task when done.
  final List<TextCorrection> corrections;
}

/// Platform implementation used by [TextProofreader].
abstract interface class TextProofreaderBackend implements MpTask {
  /// Corrects [text] and waits for the complete result.
  Future<TextProofreaderResult> proofread(String text);

  /// Corrects [text] and emits incremental output.
  Stream<TextProofreaderChunk> proofreadStreaming(String text);
}

/// Corrects spelling, grammar, and punctuation in text.
final class TextProofreader implements MpTask {
  TextProofreader._(this._backend);

  final TextProofreaderBackend _backend;
  final TaskLifecycle _lifecycle = TaskLifecycle('TextProofreader');

  /// Creates a proofreader using [runtime], or the active platform adapter.
  static Future<TextProofreader> create(
    TextProofreaderOptions options, {
    TextRuntime? runtime,
  }) async =>
      TextProofreader._(await (runtime ?? defaultTextRuntime).createTextProofreader(options));

  @override
  bool get isClosed => _lifecycle.isClosed;

  /// Corrects [text] and waits for the complete result.
  Future<TextProofreaderResult> proofread(String text) {
    _lifecycle.ensureOpen();
    return _backend.proofread(text);
  }

  /// Corrects [text] and emits incremental output.
  Stream<TextProofreaderChunk> proofreadStreaming(String text) {
    _lifecycle.ensureOpen();
    return _backend.proofreadStreaming(text);
  }

  @override
  Future<void> close() async {
    if (!_lifecycle.markClosed()) return;
    await _backend.close();
  }
}
