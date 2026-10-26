import 'dart:async';
import 'dart:developer' show TimelineTask;

import 'package:meta/meta.dart';

import 'errors.dart';
import 'latency_window.dart';

/// One failed frame-processing attempt.
final class LatestFrameFailure<T extends Object> {
  /// Creates a failure for [item].
  const LatestFrameFailure({required this.item, required this.error, required this.stackTrace});

  /// Item whose processing callback failed.
  final T item;

  /// Error thrown by the processing callback.
  final Object error;

  /// Stack trace captured with [error].
  final StackTrace stackTrace;
}

/// A point-in-time view of a [LatestFrameScheduler]'s counters and timings.
///
/// Percentiles come from the scheduler's rolling window and are `null` until a
/// frame has completed. Applications show these to explain *why* results feel
/// stale: a rising queue wait means frames arrive faster than inference runs,
/// while a rising processing time points at the model or the delegate.
@immutable
final class LatestFrameStats {
  /// Creates a snapshot; see [LatestFrameScheduler.stats].
  const LatestFrameStats({
    required this.submittedCount,
    required this.processedCount,
    required this.droppedCount,
    required this.staleCount,
    required this.failedCount,
    required this.processedPerSecond,
    this.lastQueueWait,
    this.lastProcessing,
    this.queueWaitP50,
    this.queueWaitP95,
    this.processingP50,
    this.processingP95,
  });

  /// Items passed to `submit`.
  final int submittedCount;

  /// Items whose processing callback completed successfully.
  final int processedCount;

  /// Waiting items replaced by a newer submission before they could run.
  final int droppedCount;

  /// Items discarded because they waited longer than the configured maximum.
  final int staleCount;

  /// Items whose processing callback threw.
  final int failedCount;

  /// Successful completions during the most recent second.
  final double processedPerSecond;

  /// Time the most recently processed item spent waiting to start.
  final Duration? lastQueueWait;

  /// Duration of the most recent processing callback.
  final Duration? lastProcessing;

  /// Median queue wait over the rolling window.
  final Duration? queueWaitP50;

  /// Slow-tail queue wait over the rolling window.
  final Duration? queueWaitP95;

  /// Median processing time over the rolling window.
  final Duration? processingP50;

  /// Slow-tail processing time over the rolling window.
  final Duration? processingP95;
}

/// Serializes camera inference while retaining at most the newest queued frame.
///
/// Camera callbacks commonly outpace model inference. An unbounded queue makes
/// results increasingly stale and retains large image buffers. This scheduler
/// processes one item at a time, drops superseded waiting items, optionally
/// discards items that waited longer than [maxQueueAge], and records queue
/// wait and processing time so applications can observe pressure through
/// [stats]. Every processed item is wrapped in a `dart:developer` timeline
/// task named `LatestFrameScheduler.process`, visible in DevTools.
final class LatestFrameScheduler<T extends Object> {
  /// Creates a scheduler that invokes [process] for retained items.
  ///
  /// [maxQueueAge] drops a waiting item that is older than the given duration
  /// when its turn comes, which keeps live results current after a long
  /// inference stall; leave it `null` for offline video where every frame
  /// matters. [statsWindow] bounds the rolling latency statistics. [clock]
  /// exists for deterministic tests and defaults to a monotonic stopwatch.
  LatestFrameScheduler(
    this._process, {
    this.maxQueueAge,
    int statsWindow = 120,
    Duration Function()? clock,
  }) : _clock = clock ?? _stopwatchClock(),
       _queueWaits = LatencyWindow(capacity: statsWindow),
       _processingTimes = LatencyWindow(capacity: statsWindow),
       _completionsMicros = List<int>.filled(statsWindow, 0) {
    if (maxQueueAge case final Duration age when age <= Duration.zero) {
      throw ArgumentError.value(age, 'maxQueueAge', 'must be greater than zero');
    }
  }

  /// Waiting items older than this are discarded instead of processed.
  final Duration? maxQueueAge;

  final Future<void> Function(T item) _process;
  final Duration Function() _clock;
  final LatencyWindow _queueWaits;
  final LatencyWindow _processingTimes;
  final List<int> _completionsMicros;
  final StreamController<LatestFrameFailure<T>> _failures =
      StreamController<LatestFrameFailure<T>>.broadcast(sync: true);
  T? _pending;
  Duration _pendingSubmittedAt = Duration.zero;
  int _completionCount = 0;
  int _nextCompletion = 0;
  bool _processing = false;
  bool _closed = false;
  int _submittedCount = 0;
  int _processedCount = 0;
  int _droppedCount = 0;
  int _staleCount = 0;
  int _failedCount = 0;
  Completer<void>? _idleCompleter;

  /// Number of submitted items.
  int get submittedCount => _submittedCount;

  /// Number of items whose processing callback completed successfully.
  int get processedCount => _processedCount;

  /// Number of waiting items replaced by a newer item.
  int get droppedCount => _droppedCount;

  /// Number of waiting items discarded for exceeding [maxQueueAge].
  int get staleCount => _staleCount;

  /// Number of items whose processing callback failed.
  int get failedCount => _failedCount;

  /// Processing failures, without terminating future frame processing.
  Stream<LatestFrameFailure<T>> get failures => _failures.stream;

  /// Whether [close] has been called.
  bool get isClosed => _closed;

  /// Current counters and rolling timings.
  LatestFrameStats get stats {
    final Duration now = _clock();
    final int oneSecondAgo = now.inMicroseconds - Duration.microsecondsPerSecond;
    int recent = 0;

    for (int index = 0; index < _completionCount; index += 1) {
      if (_completionsMicros[index] > oneSecondAgo) recent += 1;
    }

    return LatestFrameStats(
      submittedCount: _submittedCount,
      processedCount: _processedCount,
      droppedCount: _droppedCount,
      staleCount: _staleCount,
      failedCount: _failedCount,
      processedPerSecond: recent.toDouble(),
      lastQueueWait: _queueWaits.last,
      lastProcessing: _processingTimes.last,
      queueWaitP50: _queueWaits.p50,
      queueWaitP95: _queueWaits.p95,
      processingP50: _processingTimes.p50,
      processingP95: _processingTimes.p95,
    );
  }

  /// Submits [item] and schedules it for processing.
  ///
  /// When another item is already waiting, that older waiting item is dropped.
  void submit(T item) {
    if (_closed) throw MpTaskClosedError('LatestFrameScheduler');
    _submittedCount += 1;

    if (_pending != null) _droppedCount += 1;
    _pending = item;
    _pendingSubmittedAt = _clock();
    _idleCompleter ??= Completer<void>();

    if (!_processing) unawaited(_drain());
  }

  /// Waits until the active callback and the latest queued item complete.
  Future<void> get idle => _idleCompleter?.future ?? Future<void>.value();

  /// Rejects future submissions and drains retained work.
  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    await idle;
    await _failures.close();
  }

  Future<void> _drain() async {
    _processing = true;
    try {
      while (_pending != null) {
        final T item = _pending!;
        final Duration submittedAt = _pendingSubmittedAt;
        _pending = null;

        final Duration started = _clock();
        final Duration queueWait = started - submittedAt;

        if (maxQueueAge case final Duration age when queueWait > age) {
          _staleCount += 1;
          continue;
        }

        final TimelineTask task = TimelineTask()
          ..start(
            'LatestFrameScheduler.process',
            arguments: <String, Object?>{'queueWaitUs': queueWait.inMicroseconds},
          );

        try {
          await _process(item);
          _processedCount += 1;
          _recordCompletion(started, queueWait);
        } on Object catch (error, stackTrace) {
          _failedCount += 1;
          _reportFailure(LatestFrameFailure<T>(item: item, error: error, stackTrace: stackTrace));
        } finally {
          task.finish();
        }
      }
    } finally {
      _processing = false;
      _idleCompleter?.complete();
      _idleCompleter = null;
    }
  }

  void _recordCompletion(Duration started, Duration queueWait) {
    final Duration finished = _clock();

    _queueWaits.add(queueWait);
    _processingTimes.add(finished - started);
    _completionsMicros[_nextCompletion] = finished.inMicroseconds;
    _nextCompletion = (_nextCompletion + 1) % _completionsMicros.length;

    if (_completionCount < _completionsMicros.length) _completionCount += 1;
  }

  void _reportFailure(LatestFrameFailure<T> failure) {
    try {
      _failures.add(failure);
    } on Object {
      // The synchronous controller runs failure listeners inline; a listener
      // that throws must not terminate frame processing.
    }
  }

  static Duration Function() _stopwatchClock() {
    final Stopwatch stopwatch = Stopwatch()..start();

    return () => stopwatch.elapsed;
  }
}
