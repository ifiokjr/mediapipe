/// Microbenchmarks for the MP SDK's per-frame hot paths.
///
/// Run `dart run benchmarks/bin/run.dart` from the repository root. Each
/// benchmark is identified by a stable `suite/case/variant` name so that
/// `tool/compare_benchmarks.dart` can match results across commits.
library;

export 'src/cli.dart';
export 'src/harness.dart';
export 'src/report.dart';
export 'src/suites/image_construction.dart';
export 'src/suites/isolate_transfer.dart';
export 'src/suites/pixel_conversion.dart';
export 'src/suites/result_containers.dart';
export 'src/suites/suites.dart';
export 'src/synthetic.dart';
