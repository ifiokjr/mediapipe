import 'package:collection/collection.dart';
import 'package:meta/meta.dart';
import 'package:mp_core/mp_core.dart';

import 'runtime.dart';

/// Configuration for an [AudioClassifier].
@immutable
final class AudioClassifierOptions {
  /// Creates audio classifier options.
  const AudioClassifierOptions({
    required this.baseOptions,
    this.classifierOptions,
    this.runningMode = AudioRunningMode.audioClips,
  });

  /// Model and hardware configuration.
  final BaseOptions baseOptions;

  /// Optional result filtering configuration.
  final ClassifierOptions? classifierOptions;

  /// Whether inputs are independent clips or an ordered stream.
  final AudioRunningMode runningMode;
}

/// Classification results for the windows generated from one audio input.
@immutable
final class AudioClassifierResult {
  /// Creates an immutable audio classifier result.
  AudioClassifierResult(Iterable<ClassificationResult> classifications)
    : classifications = List<ClassificationResult>.unmodifiable(classifications);

  /// Classification results for each window in chronological order.
  final List<ClassificationResult> classifications;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is AudioClassifierResult &&
          const ListEquality<ClassificationResult>().equals(classifications, other.classifications);

  @override
  int get hashCode => const ListEquality<ClassificationResult>().hash(classifications);
}

/// Platform implementation used by [AudioClassifier].
abstract interface class AudioClassifierBackend implements MpTask {
  /// Results emitted for inputs submitted with [classifyAsync].
  Stream<AudioClassifierResult> get results;

  /// Classifies an independent audio clip.
  Future<AudioClassifierResult> classify(AudioData audio);

  /// Submits a chunk from an ordered audio stream.
  Future<void> classifyAsync(AudioData audio, int timestampMs);
}

/// Classifies complete audio clips or an ongoing audio stream.
final class AudioClassifier implements MpTask {
  AudioClassifier._(this.options, this._backend);

  /// Options used to create this classifier.
  final AudioClassifierOptions options;

  final AudioClassifierBackend _backend;
  final TaskLifecycle _lifecycle = TaskLifecycle('AudioClassifier');
  final TimestampTracker _timestamps = TimestampTracker();

  /// Creates a classifier using [runtime], or the active platform adapter.
  static Future<AudioClassifier> create(
    AudioClassifierOptions options, {
    AudioRuntime? runtime,
  }) async => AudioClassifier._(
    options,
    await (runtime ?? defaultAudioRuntime).createAudioClassifier(options),
  );

  @override
  bool get isClosed => _lifecycle.isClosed;

  /// Asynchronous results for [AudioRunningMode.audioStream].
  Stream<AudioClassifierResult> get results {
    _lifecycle.ensureOpen();
    return _backend.results;
  }

  /// Classifies one independent [audio] clip.
  Future<AudioClassifierResult> classify(AudioData audio) {
    _lifecycle.ensureOpen();
    _requireMode(AudioRunningMode.audioClips, 'classify');
    return _backend.classify(audio);
  }

  /// Submits timestamped [audio] to a streaming classifier.
  Future<void> classifyAsync(AudioData audio, int timestampMs) {
    _lifecycle.ensureOpen();
    _requireMode(AudioRunningMode.audioStream, 'classifyAsync');
    _timestamps.add(timestampMs);
    return _backend.classifyAsync(audio, timestampMs);
  }

  void _requireMode(AudioRunningMode expected, String operation) {
    if (options.runningMode != expected) {
      throw StateError(
        '$operation requires ${expected.name} mode; this classifier uses '
        '${options.runningMode.name}.',
      );
    }
  }

  @override
  Future<void> close() async {
    if (!_lifecycle.markClosed()) return;
    await _backend.close();
  }
}
