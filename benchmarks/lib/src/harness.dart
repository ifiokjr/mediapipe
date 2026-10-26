import 'dart:async';

/// One timed operation in a benchmark suite.
///
/// [run] is invoked once per iteration. When it returns a [Future] the runner
/// awaits it before stopping the clock, so asynchronous hot paths such as
/// isolate round trips are timed end to end; synchronous bodies are timed
/// without an event-loop hop.
final class Benchmark {
  /// Creates a benchmark identified by [name].
  const Benchmark({required this.name, required this.run, this.setUp, this.tearDown});

  /// Stable `suite/case/variant` identifier used to match runs across commits.
  final String name;

  /// The operation under measurement.
  final FutureOr<Object?> Function() run;

  /// Prepares inputs once, before the first warm-up iteration.
  final FutureOr<void> Function()? setUp;

  /// Releases resources once, after the last measured iteration.
  final FutureOr<void> Function()? tearDown;
}

/// A group of benchmarks that cover one hot path.
final class BenchmarkSuite {
  /// Creates a suite named [name].
  const BenchmarkSuite({required this.name, required this.benchmarks});

  /// Suite identifier; every member's [Benchmark.name] starts with it.
  final String name;

  /// Benchmarks in execution order.
  final List<Benchmark> benchmarks;
}

/// Wall-clock samples collected for one benchmark.
final class BenchmarkResult {
  /// Creates a result from unsorted per-iteration durations in microseconds.
  BenchmarkResult({required this.name, required List<int> samplesMicros})
    : samplesMicros = List<int>.unmodifiable(samplesMicros.toList()..sort()) {
    if (samplesMicros.isEmpty) {
      throw ArgumentError.value(samplesMicros, 'samplesMicros', 'must not be empty');
    }
  }

  /// The benchmark that produced these samples.
  final String name;

  /// Per-iteration durations in microseconds, ascending.
  final List<int> samplesMicros;

  /// Number of measured iterations.
  int get iterations => samplesMicros.length;

  /// Fastest iteration.
  int get minMicros => samplesMicros.first;

  /// Median iteration; the metric the regression gate compares.
  int get p50Micros => percentile(50);

  /// Slow-tail iteration.
  int get p95Micros => percentile(95);

  /// Arithmetic mean of all iterations.
  double get meanMicros =>
      samplesMicros.fold<int>(0, (int sum, int sample) => sum + sample) / samplesMicros.length;

  /// Nearest-rank percentile of the sorted samples.
  int percentile(num percent) {
    if (percent < 0 || percent > 100) {
      throw RangeError.range(percent, 0, 100, 'percent');
    }

    final int rank = (percent / 100 * samplesMicros.length).ceil();

    return samplesMicros[rank.clamp(1, samplesMicros.length) - 1];
  }

  /// The summary statistics serialized for cross-commit comparison.
  Map<String, Object?> toJson() => <String, Object?>{
    'name': name,
    'iterations': iterations,
    'minUs': minMicros,
    'p50Us': p50Micros,
    'p95Us': p95Micros,
    'meanUs': meanMicros,
  };
}

/// Executes benchmarks with warm-up, repeated rounds, and sample collection.
///
/// Rounds interleave the whole benchmark list so that slow drift on a shared
/// machine (thermal throttling, a noisy neighbour) spreads across every
/// benchmark rather than penalizing whichever one ran last.
final class BenchmarkRunner {
  /// Creates a runner; every count must be positive.
  const BenchmarkRunner({this.warmupIterations = 3, this.measuredIterations = 20, this.rounds = 1})
    : assert(warmupIterations > 0, 'warmupIterations must be positive'),
      assert(measuredIterations > 0, 'measuredIterations must be positive'),
      assert(rounds > 0, 'rounds must be positive');

  /// Untimed iterations before each round's measurements.
  final int warmupIterations;

  /// Timed iterations per round.
  final int measuredIterations;

  /// How many times the full benchmark list is repeated.
  final int rounds;

  /// Runs every benchmark in [benchmarks] and returns results in the same order.
  Future<List<BenchmarkResult>> runAll(Iterable<Benchmark> benchmarks) async {
    final List<Benchmark> ordered = benchmarks.toList(growable: false);
    final Map<String, List<int>> samples = <String, List<int>>{
      for (final Benchmark benchmark in ordered) benchmark.name: <int>[],
    };

    for (final Benchmark benchmark in ordered) {
      await benchmark.setUp?.call();
    }

    try {
      for (int round = 0; round < rounds; round += 1) {
        for (final Benchmark benchmark in ordered) {
          await _measure(benchmark, samples[benchmark.name]!);
        }
      }
    } finally {
      for (final Benchmark benchmark in ordered.reversed) {
        await benchmark.tearDown?.call();
      }
    }

    return <BenchmarkResult>[
      for (final Benchmark benchmark in ordered)
        BenchmarkResult(name: benchmark.name, samplesMicros: samples[benchmark.name]!),
    ];
  }

  /// Runs a single [benchmark] through every round.
  Future<BenchmarkResult> run(Benchmark benchmark) async =>
      (await runAll(<Benchmark>[benchmark])).single;

  Future<void> _measure(Benchmark benchmark, List<int> samples) async {
    for (int iteration = 0; iteration < warmupIterations; iteration += 1) {
      await _invoke(benchmark);
    }

    for (int iteration = 0; iteration < measuredIterations; iteration += 1) {
      final Stopwatch stopwatch = Stopwatch()..start();
      await _invoke(benchmark);
      stopwatch.stop();
      samples.add(stopwatch.elapsedMicroseconds);
    }
  }

  static Future<void> _invoke(Benchmark benchmark) async {
    // Only hop through the event loop when the body is actually asynchronous,
    // so synchronous kernels are not charged a microtask per iteration.
    final Object? pending = benchmark.run();

    if (pending is Future<Object?>) await pending;
  }
}
