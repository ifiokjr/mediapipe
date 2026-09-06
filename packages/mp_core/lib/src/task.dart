import 'errors.dart';

/// Lifecycle contract shared by all task objects.
abstract interface class MpTask {
  /// Whether [close] has completed.
  bool get isClosed;

  /// Releases native, web, and isolate resources owned by this task.
  ///
  /// Implementations must be idempotent.
  Future<void> close();
}

/// Reusable lifecycle guard for task implementations.
final class TaskLifecycle {
  /// Creates an open lifecycle for [taskName].
  TaskLifecycle(this.taskName);

  /// Name included in lifecycle errors.
  final String taskName;

  bool _isClosed = false;

  /// Whether the associated task is closed.
  bool get isClosed => _isClosed;

  /// Throws when the associated task has already been closed.
  void ensureOpen() {
    if (_isClosed) throw MpTaskClosedError(taskName);
  }

  /// Marks the associated task closed.
  ///
  /// Returns `true` only for the first call, allowing implementations to make
  /// resource cleanup idempotent.
  bool markClosed() {
    if (_isClosed) return false;
    _isClosed = true;
    return true;
  }
}

/// Validates timestamps for ordered video and live-stream inputs.
final class TimestampTracker {
  int? _lastTimestampMs;

  /// The most recently accepted timestamp, or `null` before the first input.
  int? get lastTimestampMs => _lastTimestampMs;

  /// Accepts [timestampMs] when it is non-negative and strictly increasing.
  void add(int timestampMs) {
    if (timestampMs < 0) {
      throw ArgumentError.value(timestampMs, 'timestampMs', 'must not be negative');
    }
    final int? previous = _lastTimestampMs;
    if (previous != null && timestampMs <= previous) {
      throw ArgumentError.value(
        timestampMs,
        'timestampMs',
        'must be greater than the previous timestamp ($previous)',
      );
    }
    _lastTimestampMs = timestampMs;
  }
}
