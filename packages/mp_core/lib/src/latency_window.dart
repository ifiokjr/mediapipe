/// A fixed-capacity rolling window of durations with percentile queries.
///
/// The window keeps the most recent [capacity] samples and answers
/// nearest-rank percentiles over them, which is enough to show a live p50/p95
/// inference latency without unbounded memory. All queries copy and sort the
/// window, so call them per frame rather than per sample.
final class LatencyWindow {
  /// Creates an empty window holding at most [capacity] samples.
  LatencyWindow({this.capacity = 120}) : _samplesMicros = List<int>.filled(capacity, 0) {
    if (capacity <= 0) {
      throw ArgumentError.value(capacity, 'capacity', 'must be greater than zero');
    }
  }

  /// Maximum number of samples retained.
  final int capacity;

  final List<int> _samplesMicros;
  int _next = 0;
  int _count = 0;
  Duration? _last;

  /// Number of retained samples, at most [capacity].
  int get count => _count;

  /// Whether no sample has been recorded yet.
  bool get isEmpty => _count == 0;

  /// The most recently recorded sample.
  Duration? get last => _last;

  /// Records [value], evicting the oldest sample once the window is full.
  void add(Duration value) {
    _samplesMicros[_next] = value.inMicroseconds;
    _next = (_next + 1) % capacity;

    if (_count < capacity) _count += 1;

    _last = value;
  }

  /// Discards every sample.
  void clear() {
    _next = 0;
    _count = 0;
    _last = null;
  }

  /// Nearest-rank percentile of the retained samples, or `null` when empty.
  Duration? percentile(num percent) {
    if (percent < 0 || percent > 100) {
      throw RangeError.range(percent, 0, 100, 'percent');
    }

    if (_count == 0) return null;

    final List<int> sorted = _samplesMicros.sublist(0, _count)..sort();
    final int rank = (percent / 100 * _count).ceil().clamp(1, _count);

    return Duration(microseconds: sorted[rank - 1]);
  }

  /// Median of the retained samples.
  Duration? get p50 => percentile(50);

  /// Slow-tail sample.
  Duration? get p95 => percentile(95);

  /// Largest retained sample.
  Duration? get max => percentile(100);

  /// Arithmetic mean of the retained samples, or `null` when empty.
  Duration? get mean {
    if (_count == 0) return null;

    int total = 0;

    for (int index = 0; index < _count; index += 1) {
      total += _samplesMicros[index];
    }

    return Duration(microseconds: total ~/ _count);
  }
}
