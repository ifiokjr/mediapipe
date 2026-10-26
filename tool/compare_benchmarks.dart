import 'dart:convert';
import 'dart:io';

/// Compares two benchmark result documents and fails on hot-path regressions.
///
/// Usage:
/// ```sh
/// dart run tool/compare_benchmarks.dart \
///   --base /tmp/base.json --head /tmp/head.json \
///   --threshold 0.25 --noise-floor-us 25 --summary "$GITHUB_STEP_SUMMARY"
/// ```
///
/// Both documents are produced by `benchmarks/bin/run.dart --json` on the same
/// machine, so the comparison is relative and immune to runner speed. A head
/// median regresses when it exceeds the base median by more than `--threshold`
/// (a fraction) and more than `--noise-floor-us` microseconds; the floor keeps
/// microsecond-scale benchmarks from flapping. A benchmark that vanished from
/// the head run fails the comparison unless `--allow-removed` is set, so a
/// regression cannot hide behind a rename.

/// Exit code when the comparison fails.
const int comparisonFailureExitCode = 1;

/// Must stay in sync with `benchmarkSchemaVersion` in
/// `benchmarks/lib/src/report.dart`.
const int _expectedSchemaVersion = 1;

/// The statistic compared between runs.
enum ComparisonMetric {
  /// Median.
  p50('p50Us'),

  /// Slow-tail behaviour.
  p95('p95Us'),

  /// Fastest iteration; the default because it is robust against transient
  /// contention while still rising when every iteration slows down.
  min('minUs'),

  /// Arithmetic mean.
  mean('meanUs');

  const ComparisonMetric(this.jsonKey);

  /// Key of the metric inside a benchmark's JSON object.
  final String jsonKey;

  /// Parses a metric name from the command line.
  static ComparisonMetric fromName(String name) => switch (name) {
    'p50' => ComparisonMetric.p50,
    'p95' => ComparisonMetric.p95,
    'min' => ComparisonMetric.min,
    'mean' => ComparisonMetric.mean,
    _ => throw FormatException('Unknown metric "$name"; expected p50, p95, min, or mean.'),
  };
}

/// One benchmark's summary statistics from a results document.
final class BenchmarkReading {
  /// Parses a benchmark object from a results document.
  BenchmarkReading.fromJson(String context, Map<String, Object?> json)
    : name = _string(context, json, 'name'),
      values = <ComparisonMetric, num>{
        for (final ComparisonMetric metric in ComparisonMetric.values)
          metric: _number(context, json, metric.jsonKey),
      };

  /// The benchmark's stable `suite/case/variant` name.
  final String name;

  /// Available statistics keyed by metric.
  final Map<ComparisonMetric, num> values;

  static String _string(String context, Map<String, Object?> json, String key) {
    final Object? value = json[key];

    if (value is! String || value.isEmpty) {
      throw FormatException('$context: benchmark "$key" must be a non-empty string.');
    }

    return value;
  }

  static num _number(String context, Map<String, Object?> json, String key) {
    final Object? value = json[key];

    if (value is! num || value < 0) {
      throw FormatException('$context: benchmark "$key" must be a non-negative number.');
    }

    return value;
  }
}

/// Outcome of comparing one benchmark between the base and head runs.
enum ComparisonStatus { ok, improved, regression, newBenchmark, removed }

/// The comparison of a single benchmark.
final class ComparisonRow {
  /// Creates a row; exactly one of [baseValue] and [headValue] is null only for
  /// [ComparisonStatus.newBenchmark] and [ComparisonStatus.removed].
  const ComparisonRow({required this.name, required this.status, this.baseValue, this.headValue});

  /// The benchmark name.
  final String name;

  /// Outcome of the comparison.
  final ComparisonStatus status;

  /// Metric value in the base run, when present.
  final num? baseValue;

  /// Metric value in the head run, when present.
  final num? headValue;
}

/// The full base-versus-head comparison.
final class ComparisonReport {
  /// Creates a report from already-computed rows.
  const ComparisonReport({required this.rows});

  /// One row per benchmark present in either run, sorted by name.
  final List<ComparisonRow> rows;

  /// Whether any head benchmark regressed beyond the threshold.
  bool get hasRegressions =>
      rows.any((ComparisonRow row) => row.status == ComparisonStatus.regression);

  /// Whether any base benchmark disappeared from the head run.
  bool get hasRemoved => rows.any((ComparisonRow row) => row.status == ComparisonStatus.removed);

  /// Renders the comparison as a Markdown table.
  String renderMarkdown(ComparisonMetric metric) {
    final StringBuffer buffer = StringBuffer()
      ..writeln('| benchmark | ${metric.name} base | ${metric.name} head | change | status |')
      ..writeln('| --- | ---: | ---: | ---: | --- |');

    for (final ComparisonRow row in rows) {
      final String change = switch ((
        row.baseValue,
        row.headValue,
        row.baseValue != null && row.baseValue! != 0,
      )) {
        (final num base, final num head, true) =>
          head > base ? '+${_percent(head, base)}%' : '${_percent(head, base)}%',
        (_, _, _) => '—',
      };
      final String status = switch (row.status) {
        ComparisonStatus.ok => 'ok',
        ComparisonStatus.improved => 'improved',
        ComparisonStatus.regression => '**regression**',
        ComparisonStatus.newBenchmark => 'new',
        ComparisonStatus.removed => '**removed**',
      };

      buffer.writeln(
        '| ${row.name} | ${row.baseValue ?? '—'} | ${row.headValue ?? '—'} | $change | $status |',
      );
    }

    return buffer.toString();
  }

  static String _percent(num head, num base) => ((head / base - 1) * 100).toStringAsFixed(1);
}

/// Compares metric values per benchmark name.
///
/// [threshold] is the allowed relative regression as a fraction (0.25 allows
/// the head to be 25% slower); [noiseFloorUs] suppresses regressions whose
/// absolute growth is below it, measured in microseconds.
ComparisonReport compareBenchmarks({
  required Map<String, num> base,
  required Map<String, num> head,
  required double threshold,
  required num noiseFloorUs,
}) {
  final List<ComparisonRow> rows = <ComparisonRow>[];

  for (final MapEntry<String, num> entry in head.entries) {
    final num? baseValue = base[entry.key];

    if (baseValue == null) {
      rows.add(
        ComparisonRow(
          name: entry.key,
          status: ComparisonStatus.newBenchmark,
          headValue: entry.value,
        ),
      );
      continue;
    }

    final num headValue = entry.value;
    final num growth = headValue - baseValue;

    if (headValue > baseValue * (1 + threshold) && growth > noiseFloorUs) {
      rows.add(
        ComparisonRow(
          name: entry.key,
          status: ComparisonStatus.regression,
          baseValue: baseValue,
          headValue: headValue,
        ),
      );
    } else if (headValue < baseValue * (1 - threshold) && -growth > noiseFloorUs) {
      rows.add(
        ComparisonRow(
          name: entry.key,
          status: ComparisonStatus.improved,
          baseValue: baseValue,
          headValue: headValue,
        ),
      );
    } else {
      rows.add(
        ComparisonRow(
          name: entry.key,
          status: ComparisonStatus.ok,
          baseValue: baseValue,
          headValue: headValue,
        ),
      );
    }
  }

  for (final String name in base.keys) {
    if (!head.containsKey(name)) {
      rows.add(ComparisonRow(name: name, status: ComparisonStatus.removed, baseValue: base[name]));
    }
  }

  rows.sort((ComparisonRow a, ComparisonRow b) => a.name.compareTo(b.name));

  return ComparisonReport(rows: rows);
}

/// Reads a results document and maps every benchmark to one metric value.
Map<String, num> readMetricValues(String path, ComparisonMetric metric) {
  final Object? decoded;

  try {
    decoded = jsonDecode(File(path).readAsStringSync());
  } on FileSystemException catch (error) {
    throw FormatException('Cannot read "$path": ${error.message}');
  }

  if (decoded is! Map<String, Object?>) {
    throw FormatException('$path: expected a JSON object at the top level.');
  }

  final Object? schemaVersion = decoded['schemaVersion'];

  if (schemaVersion != _expectedSchemaVersion) {
    throw FormatException(
      '$path: schema version $schemaVersion is not supported; expected '
      '$_expectedSchemaVersion. Regenerate both documents with the same '
      'benchmark runner.',
    );
  }

  final Object? benchmarks = decoded['benchmarks'];

  if (benchmarks is! List<Object?>) {
    throw FormatException('$path: "benchmarks" must be a list.');
  }

  final Map<String, num> values = <String, num>{};

  for (final Object? entry in benchmarks) {
    if (entry is! Map<String, Object?>) {
      throw FormatException('$path: each benchmark must be a JSON object.');
    }

    final BenchmarkReading reading = BenchmarkReading.fromJson(path, entry);

    if (values.containsKey(reading.name)) {
      throw FormatException('$path: benchmark "${reading.name}" appears more than once.');
    }

    values[reading.name] = reading.values[metric]!;
  }

  return values;
}

/// Exit code for invalid command-line usage, matching `EX_USAGE`.
const int usageExitCode = 64;

/// Runs the comparison for [arguments].
///
/// Returns the process exit code instead of exiting so tests can drive it in
/// process; [main] forwards the code to [exitCode].
Future<int> runCompareBenchmarks(
  List<String> arguments, {
  required StringSink out,
  required StringSink err,
}) async {
  String? basePath;
  String? headPath;
  String? summaryPath;
  double threshold = 0.25;
  num noiseFloorUs = 25;
  ComparisonMetric metric = ComparisonMetric.min;
  bool allowRemoved = false;

  try {
    for (int index = 0; index < arguments.length; index += 1) {
      final String argument = arguments[index];

      String value() {
        index += 1;

        if (index >= arguments.length) {
          throw FormatException('Option "$argument" requires a value.');
        }

        return arguments[index];
      }

      double fraction() => switch (double.tryParse(value())) {
        final double parsed when parsed > 0 && parsed < 10 => parsed,
        _ => throw FormatException('Option "$argument" requires a fraction such as 0.25.'),
      };

      switch (argument) {
        case '--base':
          basePath = value();
        case '--head':
          headPath = value();
        case '--summary':
          summaryPath = value();
        case '--threshold':
          threshold = fraction();
        case '--noise-floor-us':
          noiseFloorUs = switch (num.tryParse(value())) {
            final num parsed when parsed >= 0 => parsed,
            _ => throw FormatException('Option "$argument" requires a non-negative number.'),
          };
        case '--metric':
          metric = ComparisonMetric.fromName(value());
        case '--allow-removed':
          allowRemoved = true;
        default:
          throw FormatException('Unknown option "$argument".');
      }
    }

    if (basePath == null || headPath == null) {
      throw const FormatException('Both --base and --head are required.');
    }
  } on FormatException catch (error) {
    err
      ..writeln(error.message)
      ..writeln();

    return usageExitCode;
  }

  final Map<String, num> base;
  final Map<String, num> head;

  try {
    base = readMetricValues(basePath, metric);
    head = readMetricValues(headPath, metric);
  } on FormatException catch (error) {
    err.writeln(error.message);

    return usageExitCode;
  }

  final ComparisonReport report = compareBenchmarks(
    base: base,
    head: head,
    threshold: threshold,
    noiseFloorUs: noiseFloorUs,
  );
  final String markdown = report.renderMarkdown(metric);

  out.writeln(markdown);

  if (summaryPath case final String summary) {
    final IOSink sink = File(summary).openWrite(mode: FileMode.append);

    sink
      ..writeln(
        '### Benchmark comparison (${metric.name}, threshold ${(threshold * 100).toStringAsFixed(0)}%)',
      )
      ..writeln()
      ..writeln(markdown);
    await sink.flush();
    await sink.close();
  }

  if (report.rows.isEmpty) {
    out.writeln('No benchmarks to compare; neither run produced results.');
  }

  if (report.hasRegressions) {
    err.writeln(
      'Performance regression: ${metric.name} exceeded the threshold for '
      '${report.rows.where((ComparisonRow row) => row.status == ComparisonStatus.regression).length} '
      'benchmark(s).',
    );
  }

  if (report.hasRemoved && !allowRemoved) {
    err.writeln(
      'Benchmarks disappeared from the head run; a regression cannot hide behind '
      'a rename. Restore the names or pass --allow-removed deliberately.',
    );
  }

  final bool failed = report.hasRegressions || (report.hasRemoved && !allowRemoved);

  return failed ? comparisonFailureExitCode : 0;
}

/// Command-line entry point; see the doc comment at the top of this file.
Future<void> main(List<String> arguments) async {
  exitCode = await runCompareBenchmarks(arguments, out: stdout, err: stderr);
}
