import 'package:meta/meta.dart';
import 'package:mp_core/mp_core.dart';

/// An immutable camera frame ready for an MP vision task.
@immutable
final class MpCameraFrame {
  /// Creates a converted camera frame.
  const MpCameraFrame({
    required this.image,
    required this.timestampMs,
    required this.processingOptions,
    required this.mirroredPreview,
  });

  /// Tightly packed RGB or RGBA pixels.
  final MpImage image;

  /// Monotonic timestamp for video and live-stream task modes.
  final int timestampMs;

  /// Rotation that MediaPipe applies before inference.
  final ImageProcessingOptions processingOptions;

  /// Whether the camera preview mirrors this frame horizontally.
  ///
  /// MediaPipe receives the unmirrored pixels. Use this flag only when
  /// transforming result coordinates onto a front-camera preview.
  final bool mirroredPreview;
}

/// Produces monotonic millisecond timestamps for camera frames.
final class MpCameraClock {
  /// Starts a new camera clock at zero.
  MpCameraClock() : _stopwatch = Stopwatch()..start();

  final Stopwatch _stopwatch;
  int _lastTimestampMs = -1;

  /// Returns a timestamp greater than the preceding value.
  ///
  /// Camera callbacks can arrive more than once in the same millisecond. MP
  /// video and live-stream tasks require strict monotonicity, so equal clock
  /// readings advance by one millisecond.
  int nextTimestampMs() {
    final int elapsed = _stopwatch.elapsedMilliseconds;
    final int next = elapsed > _lastTimestampMs ? elapsed : _lastTimestampMs + 1;
    _lastTimestampMs = next;
    return next;
  }
}
