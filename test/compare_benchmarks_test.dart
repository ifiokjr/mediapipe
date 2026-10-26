import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';

import '../tool/compare_benchmarks.dart' as compare;

void main() {
  group('compareBenchmarks', () {
    test('flags regressions only beyond both the ratio and the floor', () {
      final compare.ComparisonReport report = compare.compareBenchmarks(
        base: <String, num>{'a/base': 100, 'a/small': 10},
        head: <String, num>{'a/base': 130, 'a/small': 30},
        threshold: 0.25,
        noiseFloorUs: 25,
      );

      // a/base: +30% and +30us -> regression. a/small: +200% but only +20us
      // -> below the noise floor, reported ok.
      expect(
        report.rows.singleWhere((compare.ComparisonRow row) => row.name == 'a/base').status,
        compare.ComparisonStatus.regression,
      );
      expect(
        report.rows.singleWhere((compare.ComparisonRow row) => row.name == 'a/small').status,
        compare.ComparisonStatus.ok,
      );
      expect(report.hasRegressions, isTrue);
    });

    test('marks improvements and unchanged benchmarks', () {
      final compare.ComparisonReport report = compare.compareBenchmarks(
        base: <String, num>{'a/faster': 100, 'a/same': 100},
        head: <String, num>{'a/faster': 50, 'a/same': 110},
        threshold: 0.25,
        noiseFloorUs: 25,
      );

      expect(
        report.rows.singleWhere((compare.ComparisonRow row) => row.name == 'a/faster').status,
        compare.ComparisonStatus.improved,
      );
      expect(
        report.rows.singleWhere((compare.ComparisonRow row) => row.name == 'a/same').status,
        compare.ComparisonStatus.ok,
      );
      expect(report.hasRegressions, isFalse);
    });

    test('reports new and removed benchmarks and sorts rows', () {
      final compare.ComparisonReport report = compare.compareBenchmarks(
        base: <String, num>{'a/gone': 10},
        head: <String, num>{'a/fresh': 10},
        threshold: 0.25,
        noiseFloorUs: 0,
      );

      expect(report.rows.map((compare.ComparisonRow row) => row.name), <String>[
        'a/fresh',
        'a/gone',
      ]);
      expect(report.rows.first.status, compare.ComparisonStatus.newBenchmark);
      expect(report.rows.last.status, compare.ComparisonStatus.removed);
      expect(report.hasRemoved, isTrue);
      expect(report.hasRegressions, isFalse);
    });

    test('renders a Markdown table with percentages', () {
      final compare.ComparisonReport report = compare.compareBenchmarks(
        base: <String, num>{'a/base': 100},
        head: <String, num>{'a/base': 150, 'a/fresh': 1},
        threshold: 0.25,
        noiseFloorUs: 0,
      );

      final String markdown = report.renderMarkdown(compare.ComparisonMetric.p50);

      expect(markdown, contains('| benchmark | p50 base | p50 head | change | status |'));
      expect(markdown, contains('| a/base | 100 | 150 | +50.0% | **regression** |'));
      expect(markdown, contains('| a/fresh | — | 1 | — | new |'));
    });
  });

  group('readMetricValues', () {
    late Directory temporary;

    setUp(() {
      temporary = Directory.systemTemp.createTempSync('compare_benchmarks_');
    });

    tearDown(() {
      temporary.deleteSync(recursive: true);
    });

    String writeDocument(Map<String, Object?> document, String name) {
      final File file = File('${temporary.path}/$name');

      file.writeAsStringSync(jsonEncode(document));

      return file.path;
    }

    test('reads the requested metric by name', () {
      final String path = writeDocument(<String, Object?>{
        'schemaVersion': 1,
        'benchmarks': <Object?>[
          <String, Object?>{
            'name': 'suite/case',
            'p50Us': 11,
            'p95Us': 20,
            'minUs': 9,
            'meanUs': 12.5,
          },
        ],
      }, 'ok.json');

      expect(compare.readMetricValues(path, compare.ComparisonMetric.min), <String, num>{
        'suite/case': 9,
      });
      expect(compare.readMetricValues(path, compare.ComparisonMetric.mean), <String, num>{
        'suite/case': 12.5,
      });
    });

    test('rejects unreadable, malformed, and unexpected-schema documents', () {
      expect(
        () => compare.readMetricValues(
          '${temporary.path}/missing.json',
          compare.ComparisonMetric.p50,
        ),
        throwsFormatException,
      );

      expect(
        () => compare.readMetricValues(
          writeDocument(<String, Object?>{
            'schemaVersion': 1,
            'benchmarks': <Object?>[],
          }, 'empty.json'),
          compare.ComparisonMetric.p50,
        ),
        returnsNormally,
      );

      expect(
        () => compare.readMetricValues(
          writeDocument(<String, Object?>{
            'schemaVersion': 99,
            'benchmarks': <Object?>[],
          }, 'schema.json'),
          compare.ComparisonMetric.p50,
        ),
        throwsFormatException,
      );

      expect(
        () => compare.readMetricValues(
          writeDocument(<String, Object?>{
            'schemaVersion': 1,
            'benchmarks': <Object?>[
              <String, Object?>{'name': '', 'p50Us': 1, 'p95Us': 1, 'minUs': 1, 'meanUs': 1.0},
            ],
          }, 'badname.json'),
          compare.ComparisonMetric.p50,
        ),
        throwsFormatException,
      );

      expect(
        () => compare.readMetricValues(
          writeDocument(<String, Object?>{
            'schemaVersion': 1,
            'benchmarks': <Object?>[
              <String, Object?>{'name': 'a', 'p50Us': 1, 'p95Us': 1, 'minUs': 1, 'meanUs': 1.0},
              <String, Object?>{'name': 'a', 'p50Us': 2, 'p95Us': 2, 'minUs': 2, 'meanUs': 2.0},
            ],
          }, 'dupes.json'),
          compare.ComparisonMetric.p50,
        ),
        throwsFormatException,
      );
    });
  });

  test('ComparisonMetric parses names and rejects unknown metrics', () {
    expect(compare.ComparisonMetric.fromName('p95'), compare.ComparisonMetric.p95);
    expect(compare.ComparisonMetric.p50.jsonKey, 'p50Us');
    expect(() => compare.ComparisonMetric.fromName('median'), throwsFormatException);
  });

  group('readMetricValues validation', () {
    late Directory temporary;

    setUp(() {
      temporary = Directory.systemTemp.createTempSync('compare_benchmarks_validation_');
    });

    tearDown(() {
      temporary.deleteSync(recursive: true);
    });

    String write(String name, Object? document) {
      final File file = File('${temporary.path}/$name');

      file.writeAsStringSync(jsonEncode(document));

      return file.path;
    }

    test('rejects documents whose shape is wrong', () {
      expect(
        () =>
            compare.readMetricValues(write('list.json', <Object?>[]), compare.ComparisonMetric.min),
        throwsFormatException,
      );
      expect(
        () => compare.readMetricValues(
          write('nolist.json', <String, Object?>{'schemaVersion': 1, 'benchmarks': 'nope'}),
          compare.ComparisonMetric.min,
        ),
        throwsFormatException,
      );
      expect(
        () => compare.readMetricValues(
          write('entry.json', <String, Object?>{
            'schemaVersion': 1,
            'benchmarks': <Object?>[1],
          }),
          compare.ComparisonMetric.min,
        ),
        throwsFormatException,
      );
      expect(
        () => compare.readMetricValues(
          write('negative.json', <String, Object?>{
            'schemaVersion': 1,
            'benchmarks': <Object?>[
              <String, Object?>{'name': 'a', 'p50Us': 1, 'p95Us': 1, 'minUs': 1, 'meanUs': -1.0},
            ],
          }),
          compare.ComparisonMetric.min,
        ),
        throwsFormatException,
      );
      expect(
        () => compare.readMetricValues(
          write('name.json', <String, Object?>{
            'schemaVersion': 1,
            'benchmarks': <Object?>[
              <String, Object?>{'name': 5, 'p50Us': 1, 'p95Us': 1, 'minUs': 1, 'meanUs': 1.0},
            ],
          }),
          compare.ComparisonMetric.min,
        ),
        throwsFormatException,
      );
    });
  });

  group('runCompareBenchmarks', () {
    late Directory temporary;
    late StringBuffer out;
    late StringBuffer err;

    setUp(() {
      temporary = Directory.systemTemp.createTempSync('compare_benchmarks_cli_');
      out = StringBuffer();
      err = StringBuffer();
    });

    tearDown(() {
      temporary.deleteSync(recursive: true);
    });

    String results(String name, Map<String, int> minUs) {
      final File file = File('${temporary.path}/$name');

      file.writeAsStringSync(
        jsonEncode(<String, Object?>{
          'schemaVersion': 1,
          'benchmarks': <Object?>[
            for (final MapEntry<String, int> entry in minUs.entries)
              <String, Object?>{
                'name': entry.key,
                'iterations': 1,
                'minUs': entry.value,
                'p50Us': entry.value,
                'p95Us': entry.value,
                'meanUs': entry.value.toDouble(),
              },
          ],
        }),
      );

      return file.path;
    }

    Future<int> run(List<String> arguments) =>
        compare.runCompareBenchmarks(arguments, out: out, err: err);

    test('passes, renders Markdown, and appends a summary when nothing regressed', () async {
      final String base = results('base.json', <String, int>{'s/a': 100, 's/b': 10});
      final String head = results('head.json', <String, int>{'s/a': 105, 's/b': 10, 's/c': 1});
      final String summary = '${temporary.path}/summary.md';

      expect(await run(<String>['--base', base, '--head', head, '--summary', summary]), 0);
      expect(out.toString(), contains('| s/a | 100 | 105 | +5.0% | ok |'));
      expect(out.toString(), contains('| s/c | — | 1 | — | new |'));
      expect(err.toString(), isEmpty);
      expect(
        File(summary).readAsStringSync(),
        contains('### Benchmark comparison (min, threshold 25%)'),
      );
    });

    test('fails on regressions and on removed benchmarks unless allowed', () async {
      final String base = results('base.json', <String, int>{'s/a': 100, 's/gone': 50});
      final String head = results('head.json', <String, int>{'s/a': 200});

      expect(
        await run(<String>['--base', base, '--head', head]),
        compare.comparisonFailureExitCode,
      );
      expect(err.toString(), contains('Performance regression: min exceeded the threshold for 1'));
      expect(err.toString(), contains('Benchmarks disappeared from the head run'));
      expect(out.toString(), contains('| s/gone | 50 | — | — | **removed** |'));

      err.clear();
      out.clear();

      final String tolerant = results('tolerant.json', <String, int>{'s/a': 110});

      expect(await run(<String>['--base', base, '--head', tolerant, '--allow-removed']), 0);
      expect(err.toString(), isEmpty);
    });

    test('honours metric, threshold, and noise-floor options', () async {
      final String base = results('base.json', <String, int>{'s/a': 100});
      final String head = results('head.json', <String, int>{'s/a': 140});

      expect(
        await run(<String>[
          '--base',
          base,
          '--head',
          head,
          '--metric',
          'p95',
          '--threshold',
          '0.5',
          '--noise-floor-us',
          '0',
        ]),
        0,
      );
      expect(out.toString(), contains('| benchmark | p95 base | p95 head | change | status |'));
    });

    test('treats an empty base run as having no baseline', () async {
      final String base = results('base.json', <String, int>{});
      final String head = results('head.json', <String, int>{'s/a': 1});

      expect(await run(<String>['--base', base, '--head', head]), 0);
      expect(out.toString(), contains('| s/a | — | 1 | — | new |'));

      out.clear();
      expect(await run(<String>['--base', base, '--head', base]), 0);
      expect(out.toString(), contains('No benchmarks to compare; neither run produced results.'));
    });

    test('rejects invalid usage and unreadable documents', () async {
      expect(await run(<String>[]), compare.usageExitCode);
      expect(err.toString(), contains('Both --base and --head are required.'));

      err.clear();
      expect(await run(<String>['--base']), compare.usageExitCode);
      expect(err.toString(), contains('requires a value'));

      err.clear();
      expect(await run(<String>['--threshold', 'lots']), compare.usageExitCode);
      expect(err.toString(), contains('requires a fraction such as 0.25'));

      err.clear();
      expect(await run(<String>['--noise-floor-us', '-1']), compare.usageExitCode);
      expect(err.toString(), contains('non-negative number'));

      err.clear();
      expect(await run(<String>['--metric', 'median']), compare.usageExitCode);
      expect(err.toString(), contains('Unknown metric "median"'));

      err.clear();
      expect(await run(<String>['--wat']), compare.usageExitCode);
      expect(err.toString(), contains('Unknown option "--wat"'));

      err.clear();
      expect(
        await run(<String>[
          '--base',
          '${temporary.path}/missing.json',
          '--head',
          '${temporary.path}/missing.json',
        ]),
        compare.usageExitCode,
      );
      expect(err.toString(), contains('Cannot read'));
    });

    test('main forwards the exit code', () async {
      final String base = results('base.json', <String, int>{'s/a': 100});
      final int previousExitCode = exitCode;

      try {
        await compare.main(<String>['--base', base, '--head', base]);

        expect(exitCode, 0);
      } finally {
        exitCode = previousExitCode;
      }
    });
  });
}
