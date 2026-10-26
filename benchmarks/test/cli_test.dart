import 'dart:convert';
import 'dart:io';

import 'package:mp_benchmarks/mp_benchmarks.dart';
import 'package:test/test.dart';

void main() {
  group('parseBenchmarkArguments', () {
    test('uses full defaults without flags', () {
      final BenchmarkCliOptions options = parseBenchmarkArguments(<String>[]);

      expect(options.rounds, 1);
      expect(options.iterations, 20);
      expect(options.warmup, 3);
      expect(options.jsonPath, isNull);
      expect(options.filter, isNull);
      expect(options.list, isFalse);
      expect(options.help, isFalse);
    });

    test('--quick lowers iteration defaults but explicit counts win', () {
      final BenchmarkCliOptions quick = parseBenchmarkArguments(<String>['--quick']);

      expect(quick.iterations, 3);
      expect(quick.warmup, 1);
      expect(quick.rounds, 1);

      final BenchmarkCliOptions explicit = parseBenchmarkArguments(<String>[
        '--quick',
        '--iterations',
        '7',
        '--warmup=2',
        '--rounds',
        '4',
      ]);

      expect(explicit.iterations, 7);
      expect(explicit.warmup, 2);
      expect(explicit.rounds, 4);
    });

    test('accepts values separated by a space or an equals sign', () {
      final BenchmarkCliOptions options = parseBenchmarkArguments(<String>[
        '--json',
        'out.json',
        '--filter=pixel',
        '--list',
        '-h',
      ]);

      expect(options.jsonPath, 'out.json');
      expect(options.filter, 'pixel');
      expect(options.list, isTrue);
      expect(options.help, isTrue);
    });

    test('rejects malformed input', () {
      expect(() => parseBenchmarkArguments(<String>['--bogus']), throwsFormatException);
      expect(() => parseBenchmarkArguments(<String>['--json']), throwsFormatException);
      expect(() => parseBenchmarkArguments(<String>['--rounds', '0']), throwsFormatException);
      expect(() => parseBenchmarkArguments(<String>['--iterations', 'two']), throwsFormatException);
      expect(() => parseBenchmarkArguments(<String>['--list=yes']), throwsFormatException);
    });
  });

  group('runBenchmarkCli', () {
    final List<BenchmarkSuite> suites = <BenchmarkSuite>[
      BenchmarkSuite(
        name: 'alpha',
        benchmarks: <Benchmark>[
          Benchmark(name: 'alpha/one', run: () => 1),
          Benchmark(name: 'alpha/two', run: () => 2),
        ],
      ),
      BenchmarkSuite(
        name: 'beta',
        benchmarks: <Benchmark>[Benchmark(name: 'beta/three', run: () => 3)],
      ),
    ];

    test('prints usage for --help', () async {
      final StringBuffer out = StringBuffer();
      final StringBuffer err = StringBuffer();

      final int code = await runBenchmarkCli(
        <String>['--help'],
        out: out,
        err: err,
        suites: suites,
      );

      expect(code, 0);
      expect(out.toString(), benchmarkUsage);
      expect(err.toString(), isEmpty);
    });

    test('reports invalid options with the usage exit code', () async {
      final StringBuffer out = StringBuffer();
      final StringBuffer err = StringBuffer();

      final int code = await runBenchmarkCli(
        <String>['--nope'],
        out: out,
        err: err,
        suites: suites,
      );

      expect(code, usageExitCode);
      expect(err.toString(), contains('Unknown option "--nope".'));
      expect(err.toString(), contains('Usage:'));
      expect(out.toString(), isEmpty);
    });

    test('lists filtered benchmark names without running them', () async {
      final StringBuffer out = StringBuffer();
      final StringBuffer err = StringBuffer();

      final int code = await runBenchmarkCli(
        <String>['--list', '--filter', 'alpha'],
        out: out,
        err: err,
        suites: suites,
      );

      expect(code, 0);
      expect(out.toString(), 'alpha/one\nalpha/two\n');
    });

    test('fails when the filter matches nothing', () async {
      final StringBuffer out = StringBuffer();
      final StringBuffer err = StringBuffer();

      final int code = await runBenchmarkCli(
        <String>['--filter', 'gamma'],
        out: out,
        err: err,
        suites: suites,
      );

      expect(code, usageExitCode);
      expect(err.toString(), 'No benchmarks match "gamma".\n');
    });

    test('runs the selection, prints a table, and writes JSON on request', () async {
      final StringBuffer out = StringBuffer();
      final StringBuffer err = StringBuffer();
      final Map<String, String> written = <String, String>{};

      final int code = await runBenchmarkCli(
        <String>['--quick', '--json', 'nested/dir/results.json', '--filter', 'beta'],
        out: out,
        err: err,
        suites: suites,
        writeFile: (String path, String contents) => written[path] = contents,
        now: () => DateTime.utc(2026),
      );

      expect(code, 0);
      expect(err.toString(), isEmpty);

      final String output = out.toString();

      expect(
        output,
        contains('Running 1 benchmarks: 1 round(s) of 3 timed and 1 warm-up iterations.'),
      );
      expect(output, contains('beta/three'));
      expect(output, contains('Wrote 1 results to nested/dir/results.json.'));
      expect(written.keys, <String>['nested/dir/results.json']);

      final Map<String, Object?> document =
          jsonDecode(written.values.single) as Map<String, Object?>;
      final List<Object?> benchmarks = document['benchmarks'] as List<Object?>;

      expect(document['createdAt'], '2026-01-01T00:00:00.000Z');
      expect(benchmarks, hasLength(1));
      expect((benchmarks.single as Map<String, Object?>)['name'], 'beta/three');
      expect((benchmarks.single as Map<String, Object?>)['iterations'], 3);
    });

    test('writes JSON to disk with the default writer, creating parents', () async {
      final Directory temporary = Directory.systemTemp.createTempSync('mp_benchmarks_cli_');
      final String path = '${temporary.path}/nested/results.json';

      try {
        final int code = await runBenchmarkCli(
          <String>['--quick', '--filter', 'beta', '--json', path],
          out: StringBuffer(),
          err: StringBuffer(),
          suites: suites,
        );

        expect(code, 0);

        final Map<String, Object?> document =
            jsonDecode(File(path).readAsStringSync()) as Map<String, Object?>;

        expect(document['schemaVersion'], benchmarkSchemaVersion);
      } finally {
        temporary.deleteSync(recursive: true);
      }
    });

    test('runs without writing when no JSON path is given', () async {
      final StringBuffer out = StringBuffer();
      final StringBuffer err = StringBuffer();
      bool wrote = false;

      final int code = await runBenchmarkCli(
        <String>['--quick'],
        out: out,
        err: err,
        suites: suites,
        writeFile: (String path, String contents) => wrote = true,
      );

      expect(code, 0);
      expect(wrote, isFalse);
      expect(out.toString(), isNot(contains('Wrote')));
      expect(out.toString(), contains('alpha/one'));
      expect(out.toString(), contains('beta/three'));
    });
  });
}
