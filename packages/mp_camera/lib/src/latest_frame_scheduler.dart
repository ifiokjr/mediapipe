import 'dart:async';

import 'package:mp_core/mp_core.dart';

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

/// Serializes camera inference while retaining at most the newest queued frame.
///
/// Camera callbacks commonly outpace model inference. An unbounded queue makes
/// results increasingly stale and retains large image buffers. This scheduler
/// processes one item at a time, drops superseded waiting items, and exposes
/// counters so applications can observe pressure.
final class LatestFrameScheduler<T extends Object> {
  /// Creates a scheduler that invokes [process] for retained items.
  LatestFrameScheduler(this._process);

  final Future<void> Function(T item) _process;
  final StreamController<LatestFrameFailure<T>> _failures =
      StreamController<LatestFrameFailure<T>>.broadcast(sync: true);
  T? _pending;
  bool _processing = false;
  bool _closed = false;
  int _submittedCount = 0;
  int _processedCount = 0;
  int _droppedCount = 0;
  int _failedCount = 0;
  Completer<void>? _idleCompleter;

  /// Number of submitted items.
  int get submittedCount => _submittedCount;

  /// Number of items whose processing callback completed successfully.
  int get processedCount => _processedCount;

  /// Number of waiting items replaced by a newer item.
  int get droppedCount => _droppedCount;

  /// Number of items whose processing callback failed.
  int get failedCount => _failedCount;

  /// Processing failures, without terminating future frame processing.
  Stream<LatestFrameFailure<T>> get failures => _failures.stream;

  /// Whether [close] has been called.
  bool get isClosed => _closed;

  /// Submits [item] and schedules it for processing.
  ///
  /// When another item is already waiting, that older waiting item is dropped.
  void submit(T item) {
    if (_closed) throw MpTaskClosedError('LatestFrameScheduler');
    _submittedCount += 1;

    if (_pending != null) _droppedCount += 1;
    _pending = item;
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
        _pending = null;
        try {
          await _process(item);
          _processedCount += 1;
        } on Object catch (error, stackTrace) {
          _failedCount += 1;

          _reportFailure(LatestFrameFailure<T>(item: item, error: error, stackTrace: stackTrace));
        }
      }
    } finally {
      _processing = false;
      _idleCompleter?.complete();
      _idleCompleter = null;
    }
  }

  void _reportFailure(LatestFrameFailure<T> failure) {
    try {
      _failures.add(failure);
    } on Object {
      // The synchronous controller runs failure listeners inline; a listener
      // that throws must not terminate frame processing.
    }
  }
}
