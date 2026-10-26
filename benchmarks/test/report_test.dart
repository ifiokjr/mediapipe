import 'dart:convert';

import 'package:mp_benchmarks/mp_benchmarks.dart';
import 'package:test/test.dart';

void main() {
  final List<BenchmarkResult> results = <BenchmarkResult>[
    BenchmarkResult(name: 'suite/fast', samplesMicros: <int>[1, 2, 3]),
    BenchmarkResult(name: 'suite/slow_variant', samplesMicros: <int>[1000, 1500]),
  ];

  test('encodeResults writes a versioned document with provenance', () {
    final String document = encodeResults(
      results,
      createdAt: DateTime.utc(2026, 10, 26, 9, 30),
      dartVersion: '3.12.0',
      platform: 'linux',
    );
    final Map<String, Object?> decoded = jsonDecode(document) as Map<String, Object?>;

    expect(decoded['schemaVersion'], benchmarkSchemaVersion);
    expect(decoded['createdAt'], '2026-10-26T09:30:00.000Z');
    expect(decoded['dartVersion'], '3.12.0');
    expect(decoded['platform'], 'linux');
    expect(decoded['benchmarks'], <Object?>[
      <String, Object?>{
        'name': 'suite/fast',
        'iterations': 3,
        'minUs': 1,
        'p50Us': 2,
        'p95Us': 3,
        'meanUs': 2.0,
      },
      <String, Object?>{
        'name': 'suite/slow_variant',
        'iterations': 2,
        'minUs': 1000,
        'p50Us': 1000,
        'p95Us': 1500,
        'meanUs': 1250.0,
      },
    ]);
  });

  test('encodeResults normalizes local timestamps to UTC', () {
    final String document = encodeResults(
      results,
      createdAt: DateTime(2026, 1, 1, 12),
      dartVersion: 'x',
      platform: 'y',
    );
    final Map<String, Object?> decoded = jsonDecode(document) as Map<String, Object?>;

    expect(decoded['createdAt'], endsWith('Z'));
  });

  test('renderTable aligns every column', () {
    final List<String> lines = renderTable(results).trimRight().split('\n');

    expect(lines, hasLength(4));
    expect(lines[0], startsWith('benchmark         '));
    expect(lines[0], contains('p50 µs'));
    expect(lines[1], matches(RegExp(r'^-+(  -+)+$')));
    expect(lines[2], startsWith('suite/fast        '));
    expect(lines[2], endsWith('  3'));
    expect(lines[3], startsWith('suite/slow_variant'));
    expect(lines[3], contains('1250.0'));

    final Set<int> lengths = lines.map((String line) => line.length).toSet();

    expect(lengths, hasLength(1));
  });
}
