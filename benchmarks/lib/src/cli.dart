import 'dart:io';

import 'harness.dart';
import 'report.dart';
import 'suites/suites.dart';

/// Exit code for invalid command-line usage, matching `EX_USAGE`.
const int usageExitCode = 64;

/// Help text for `dart run benchmarks/bin/run.dart`.
const String benchmarkUsage = '''
Usage: dart run benchmarks/bin/run.dart [options]

Runs the MP SDK hot-path benchmarks and prints a table of timings.

Options:
  --json <path>         Also write results as JSON for tool/compare_benchmarks.dart.
  --filter <substring>  Only run benchmarks whose name contains the substring.
  --rounds <n>          Repeat the whole benchmark list n times (default 1).
  --iterations <n>      Timed iterations per round (default 20, or 3 with --quick).
  --warmup <n>          Untimed iterations per round (default 3, or 1 with --quick).
  --quick               Smoke-test settings: 1 round, 3 iterations, 1 warm-up.
  --list                Print the selected benchmark names without running them.
  --help, -h            Show this message.
''';

/// Options parsed from the benchmark command line.
final class BenchmarkCliOptions {
  /// Creates resolved options; see [parseBenchmarkArguments] for defaults.
  const BenchmarkCliOptions({
    required this.rounds,
    required this.iterations,
    required this.warmup,
    this.jsonPath,
    this.filter,
    this.list = false,
    this.help = false,
  });

  /// Rounds through the full benchmark list.
  final int rounds;

  /// Timed iterations per round.
  final int iterations;

  /// Untimed iterations per round.
  final int warmup;

  /// Destination for the JSON results document, when requested.
  final String? jsonPath;

  /// Substring every selected benchmark name must contain.
  final String? filter;

  /// Whether to print benchmark names instead of running them.
  final bool list;

  /// Whether to print usage and exit.
  final bool help;
}

/// Parses [arguments], throwing a [FormatException] for invalid input.
///
/// `--quick` lowers the iteration defaults; explicit counts always win.
BenchmarkCliOptions parseBenchmarkArguments(List<String> arguments) {
  String? jsonPath;
  String? filter;
  int? rounds;
  int? iterations;
  int? warmup;
  bool quick = false;
  bool list = false;
  bool help = false;

  for (int index = 0; index < arguments.length; index += 1) {
    final String argument = arguments[index];
    final int separator = argument.indexOf('=');
    final String name = separator == -1 ? argument : argument.substring(0, separator);
    String? inlineValue = separator == -1 ? null : argument.substring(separator + 1);

    String value() {
      if (inlineValue case final String provided) {
        inlineValue = null;

        return provided;
      }

      index += 1;

      if (index >= arguments.length) {
        throw FormatException('Option "$name" requires a value.');
      }

      return arguments[index];
    }

    int positive() {
      final String raw = value();
      final int? parsed = int.tryParse(raw);

      if (parsed == null || parsed <= 0) {
        throw FormatException('Option "$name" requires a positive integer, got "$raw".');
      }

      return parsed;
    }

    switch (name) {
      case '--help' || '-h':
        help = true;
      case '--list':
        list = true;
      case '--quick':
        quick = true;
      case '--json':
        jsonPath = value();
      case '--filter':
        filter = value();
      case '--rounds':
        rounds = positive();
      case '--iterations':
        iterations = positive();
      case '--warmup':
        warmup = positive();
      default:
        throw FormatException('Unknown option "$argument".');
    }

    if (inlineValue != null) {
      throw FormatException('Option "$name" does not take a value.');
    }
  }

  return BenchmarkCliOptions(
    rounds: rounds ?? 1,
    iterations: iterations ?? (quick ? 3 : 20),
    warmup: warmup ?? (quick ? 1 : 3),
    jsonPath: jsonPath,
    filter: filter,
    list: list,
    help: help,
  );
}

/// Runs the benchmark command line and returns the process exit code.
///
/// [suites], [writeFile], and [now] exist so tests can substitute small
/// inputs, capture output, and pin timestamps.
Future<int> runBenchmarkCli(
  List<String> arguments, {
  required StringSink out,
  required StringSink err,
  List<BenchmarkSuite>? suites,
  void Function(String path, String contents)? writeFile,
  DateTime Function()? now,
}) async {
  final BenchmarkCliOptions options;

  try {
    options = parseBenchmarkArguments(arguments);
  } on FormatException catch (error) {
    err
      ..writeln(error.message)
      ..writeln()
      ..write(benchmarkUsage);

    return usageExitCode;
  }

  if (options.help) {
    out.write(benchmarkUsage);

    return 0;
  }

  final List<Benchmark> selected = <Benchmark>[
    for (final BenchmarkSuite suite in suites ?? defaultSuites())
      for (final Benchmark benchmark in suite.benchmarks)
        if (options.filter == null || benchmark.name.contains(options.filter!)) benchmark,
  ];

  if (selected.isEmpty) {
    err.writeln('No benchmarks match "${options.filter}".');

    return usageExitCode;
  }

  if (options.list) {
    for (final Benchmark benchmark in selected) {
      out.writeln(benchmark.name);
    }

    return 0;
  }

  final BenchmarkRunner runner = BenchmarkRunner(
    warmupIterations: options.warmup,
    measuredIterations: options.iterations,
    rounds: options.rounds,
  );
  out.writeln(
    'Running ${selected.length} benchmarks: ${options.rounds} round(s) of '
    '${options.iterations} timed and ${options.warmup} warm-up iterations.',
  );
  final List<BenchmarkResult> results = await runner.runAll(selected);
  out
    ..writeln()
    ..write(renderTable(results));

  if (options.jsonPath case final String jsonPath) {
    final String document = encodeResults(
      results,
      createdAt: (now ?? DateTime.now)(),
      dartVersion: Platform.version,
      platform: Platform.operatingSystem,
    );
    (writeFile ?? _writeFile)(jsonPath, document);
    out.writeln('Wrote ${results.length} results to $jsonPath.');
  }

  return 0;
}

void _writeFile(String path, String contents) {
  final File file = File(path);
  file.parent.createSync(recursive: true);
  file.writeAsStringSync(contents);
}
