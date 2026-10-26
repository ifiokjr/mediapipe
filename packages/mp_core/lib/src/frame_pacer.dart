/// Admits at most one frame per interval, judged by camera timestamp.
///
/// Cameras commonly deliver 30 or 60 frames per second while a landmarker
/// sustains far fewer. Converting every frame and letting the scheduler drop
/// the surplus still pays the conversion for frames that never run; a pacer
/// decides *before* conversion, so a skipped frame costs nothing.
///
/// ```dart
/// final pacer = FramePacer.targetFps(15);
///
/// void onCameraImage(CameraImage image) {
///   final timestampMs = clock.nextTimestampMs();
///   if (!pacer.admit(timestampMs)) return;
///   scheduler.submit(MpCameraFrameConverter.convert(image, timestampMs: timestampMs, ...));
/// }
/// ```
final class FramePacer {
  /// Creates a pacer that admits one frame per [minInterval].
  FramePacer({required this.minInterval}) {
    if (minInterval <= Duration.zero) {
      throw ArgumentError.value(minInterval, 'minInterval', 'must be greater than zero');
    }
  }

  /// Creates a pacer that admits roughly [framesPerSecond] frames per second.
  factory FramePacer.targetFps(double framesPerSecond) {
    if (!framesPerSecond.isFinite || framesPerSecond <= 0) {
      throw ArgumentError.value(framesPerSecond, 'framesPerSecond', 'must be greater than zero');
    }

    return FramePacer(
      minInterval: Duration(
        microseconds: (Duration.microsecondsPerSecond / framesPerSecond).round(),
      ),
    );
  }

  /// Minimum spacing between two admitted frames.
  final Duration minInterval;

  int? _lastAdmittedTimestampMs;
  int _admittedCount = 0;
  int _skippedCount = 0;

  /// Timestamp of the most recently admitted frame, or `null` before the first.
  int? get lastAdmittedTimestampMs => _lastAdmittedTimestampMs;

  /// Number of frames [admit] accepted.
  int get admittedCount => _admittedCount;

  /// Number of frames [admit] rejected.
  int get skippedCount => _skippedCount;

  /// Whether a frame stamped [timestampMs] should be converted and processed.
  ///
  /// The first frame is always admitted, as is any frame whose timestamp runs
  /// backwards, so a camera restart never stalls the pipeline.
  bool admit(int timestampMs) {
    final int? last = _lastAdmittedTimestampMs;

    if (last != null && timestampMs >= last && timestampMs - last < minInterval.inMilliseconds) {
      _skippedCount += 1;

      return false;
    }

    _lastAdmittedTimestampMs = timestampMs;
    _admittedCount += 1;

    return true;
  }

  /// Forgets the last admitted timestamp and zeroes the counters.
  void reset() {
    _lastAdmittedTimestampMs = null;
    _admittedCount = 0;
    _skippedCount = 0;
  }
}
