import 'dart:convert';

import 'harness.dart';

/// Version of the JSON document written by [encodeResults].
///
/// `tool/compare_benchmarks.dart` refuses documents with another version, so
/// bump it together with any change to the per-benchmark fields.
const int benchmarkSchemaVersion = 1;

/// Serializes [results] with the run's provenance for cross-commit comparison.
String encodeResults(
  List<BenchmarkResult> results, {
  required DateTime createdAt,
  required String dartVersion,
  required String platform,
}) => const JsonEncoder.withIndent('  ').convert(<String, Object?>{
  'schemaVersion': benchmarkSchemaVersion,
  'createdAt': createdAt.toUtc().toIso8601String(),
  'dartVersion': dartVersion,
  'platform': platform,
  'benchmarks': <Map<String, Object?>>[
    for (final BenchmarkResult result in results) result.toJson(),
  ],
});

/// Renders [results] as a fixed-width text table.
String renderTable(List<BenchmarkResult> results) {
  const List<String> headers = <String>['benchmark', 'p50 µs', 'p95 µs', 'min µs', 'mean µs', 'n'];
  final List<List<String>> rows = <List<String>>[
    for (final BenchmarkResult result in results)
      <String>[
        result.name,
        '${result.p50Micros}',
        '${result.p95Micros}',
        '${result.minMicros}',
        result.meanMicros.toStringAsFixed(1),
        '${result.iterations}',
      ],
  ];
  final List<int> widths = List<int>.generate(
    headers.length,
    (int column) => <int>[
      headers[column].length,
      for (final List<String> row in rows) row[column].length,
    ].reduce((int a, int b) => a > b ? a : b),
  );

  String line(List<String> cells) {
    final StringBuffer buffer = StringBuffer();

    for (int column = 0; column < cells.length; column += 1) {
      final String cell = cells[column];
      buffer.write(column == 0 ? cell.padRight(widths[column]) : cell.padLeft(widths[column]));

      if (column < cells.length - 1) buffer.write('  ');
    }

    return buffer.toString();
  }

  final StringBuffer output = StringBuffer()
    ..writeln(line(headers))
    ..writeln(line(<String>[for (final int width in widths) '-' * width]));

  for (final List<String> row in rows) {
    output.writeln(line(row));
  }

  return output.toString();
}
