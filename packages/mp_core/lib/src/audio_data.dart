import 'dart:typed_data';

import 'package:collection/collection.dart';
import 'package:meta/meta.dart';

/// Interleaved, floating-point PCM audio consumed by MediaPipe audio tasks.
@immutable
final class AudioData {
  /// Creates audio data and copies [samples].
  AudioData({required this.channelCount, required this.sampleRateHz, required Float32List samples})
    : samples = Float32List.fromList(samples) {
    if (channelCount <= 0) {
      throw ArgumentError.value(channelCount, 'channelCount', 'must be greater than zero');
    }
    if (!sampleRateHz.isFinite || sampleRateHz <= 0) {
      throw ArgumentError.value(sampleRateHz, 'sampleRateHz', 'must be finite and positive');
    }
    if (samples.isEmpty || samples.length % channelCount != 0) {
      throw ArgumentError.value(
        samples.length,
        'samples.length',
        'must be a non-empty multiple of channelCount',
      );
    }
  }

  /// Number of interleaved channels.
  final int channelCount;

  /// Number of frames per second.
  final double sampleRateHz;

  /// Interleaved PCM samples, normally in the range −1–1.
  final Float32List samples;

  /// Number of frames per channel.
  int get frameCount => samples.length ~/ channelCount;

  /// Audio duration.
  Duration get duration =>
      Duration(microseconds: (frameCount * Duration.microsecondsPerSecond / sampleRateHz).round());

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is AudioData &&
          channelCount == other.channelCount &&
          sampleRateHz == other.sampleRateHz &&
          const ListEquality<double>().equals(samples, other.samples);

  @override
  int get hashCode =>
      Object.hash(channelCount, sampleRateHz, const ListEquality<double>().hash(samples));
}

/// MediaPipe audio task execution modes.
enum AudioRunningMode {
  /// Process complete, independent audio clips.
  audioClips,

  /// Process timestamped chunks from an ongoing audio stream.
  audioStream,
}
