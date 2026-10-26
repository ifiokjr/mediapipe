import 'dart:async';

import 'package:mp_benchmarks/mp_benchmarks.dart';
import 'package:test/test.dart';

void main() {
  group('BenchmarkResult', () {
    test('sorts samples and reports nearest-rank percentiles', () {
      final BenchmarkResult result = BenchmarkResult(name: 'a', samplesMicros: <int>[5, 1, 3]);

      expect(result.samplesMicros, <int>[1, 3, 5]);
      expect(result.iterations, 3);
      expect(result.minMicros, 1);
      expect(result.p50Micros, 3);
      expect(result.p95Micros, 5);
      expect(result.meanMicros, 3);
      expect(result.percentile(0), 1);
      expect(result.percentile(100), 5);
    });

    test('does not expose a mutable sample list', () {
      final BenchmarkResult result = BenchmarkResult(name: 'a', samplesMicros: <int>[2, 1]);

      expect(() => result.samplesMicros.add(3), throwsUnsupportedError);
    });

    test('rejects empty samples and out-of-range percentiles', () {
      expect(() => BenchmarkResult(name: 'a', samplesMicros: <int>[]), throwsArgumentError);

      final BenchmarkResult result = BenchmarkResult(name: 'a', samplesMicros: <int>[1]);

      expect(() => result.percentile(101), throwsRangeError);
      expect(() => result.percentile(-1), throwsRangeError);
    });

    test('serializes summary statistics', () {
      final BenchmarkResult result = BenchmarkResult(
        name: 'suite/case',
        samplesMicros: <int>[4, 2],
      );

      expect(result.toJson(), <String, Object?>{
        'name': 'suite/case',
        'iterations': 2,
        'minUs': 2,
        'p50Us': 2,
        'p95Us': 4,
        'meanUs': 3.0,
      });
    });
  });

  group('BenchmarkRunner', () {
    test('runs warm-up and measured iterations for every round', () async {
      int setUps = 0;
      int runs = 0;
      int tearDowns = 0;
      final Benchmark benchmark = Benchmark(
        name: 'count',
        setUp: () => setUps += 1,
        run: () => runs += 1,
        tearDown: () => tearDowns += 1,
      );

      final BenchmarkResult result = await const BenchmarkRunner(
        warmupIterations: 2,
        measuredIterations: 3,
        rounds: 2,
      ).run(benchmark);

      expect(setUps, 1);
      expect(runs, 10);
      expect(tearDowns, 1);
      expect(result.iterations, 6);
      expect(result.name, 'count');
    });

    test('interleaves benchmarks across rounds', () async {
      final List<String> order = <String>[];
      final List<Benchmark> benchmarks = <Benchmark>[
        Benchmark(name: 'a', run: () => order.add('a')),
        Benchmark(name: 'b', run: () => order.add('b')),
      ];

      final List<BenchmarkResult> results = await const BenchmarkRunner(
        warmupIterations: 1,
        measuredIterations: 1,
        rounds: 2,
      ).runAll(benchmarks);

      expect(results.map((BenchmarkResult result) => result.name), <String>['a', 'b']);
      expect(order, <String>['a', 'a', 'b', 'b', 'a', 'a', 'b', 'b']);
    });

    test('awaits asynchronous bodies before stopping the clock', () async {
      final Benchmark benchmark = Benchmark(
        name: 'async',
        run: () => Future<void>.delayed(const Duration(milliseconds: 5)),
      );

      final BenchmarkResult result = await const BenchmarkRunner(
        warmupIterations: 1,
        measuredIterations: 2,
      ).run(benchmark);

      expect(result.minMicros, greaterThanOrEqualTo(4000));
    });

    test('tears down even when a body throws, then rethrows', () async {
      int tearDowns = 0;
      final Benchmark benchmark = Benchmark(
        name: 'failing',
        run: () => throw StateError('boom'),
        tearDown: () => tearDowns += 1,
      );

      await expectLater(
        const BenchmarkRunner(warmupIterations: 1, measuredIterations: 1).run(benchmark),
        throwsStateError,
      );
      expect(tearDowns, 1);
    });

    test('supports asynchronous set-up and tear-down', () async {
      final List<String> events = <String>[];
      final Benchmark benchmark = Benchmark(
        name: 'lifecycle',
        setUp: () async {
          await Future<void>.delayed(Duration.zero);
          events.add('setUp');
        },
        run: () => events.add('run'),
        tearDown: () async {
          await Future<void>.delayed(Duration.zero);
          events.add('tearDown');
        },
      );

      await const BenchmarkRunner(warmupIterations: 1, measuredIterations: 1).run(benchmark);

      expect(events, <String>['setUp', 'run', 'run', 'tearDown']);
    });
  });
}
