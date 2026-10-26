import 'dart:io';
import 'dart:typed_data';

import 'package:mp_benchmarks/mp_benchmarks.dart';
import 'package:mp_core/mp_core.dart';
import 'package:test/test.dart';

void main() {
  group('defaultSuites', () {
    test('names are unique and prefixed by their suite', () {
      final List<BenchmarkSuite> suites = defaultSuites();
      final List<String> names = <String>[
        for (final BenchmarkSuite suite in suites)
          for (final Benchmark benchmark in suite.benchmarks) benchmark.name,
      ];

      expect(names.toSet(), hasLength(names.length));

      for (final BenchmarkSuite suite in suites) {
        for (final Benchmark benchmark in suite.benchmarks) {
          expect(benchmark.name, startsWith('${suite.name}/'));
          expect(benchmark.name, matches(RegExp(r'^[a-z0-9_]+(/[a-z0-9_]+)+$')));
        }
      }
    });

    test('default to the 720p frame size', () {
      final List<String> names = <String>[
        for (final BenchmarkSuite suite in defaultSuites())
          for (final Benchmark benchmark in suite.benchmarks) benchmark.name,
      ];

      expect(names.where((String name) => name.contains('1280x720')), hasLength(8));
    });

    test('every benchmark runs end to end at the tiny size', () async {
      final List<Benchmark> benchmarks = <Benchmark>[
        for (final BenchmarkSuite suite in defaultSuites(size: tiny)) ...suite.benchmarks,
      ];

      final List<BenchmarkResult> results = await const BenchmarkRunner(
        warmupIterations: 1,
        measuredIterations: 2,
      ).runAll(benchmarks);

      expect(results, hasLength(benchmarks.length));

      for (final BenchmarkResult result in results) {
        expect(result.iterations, 2);
        expect(result.minMicros, greaterThanOrEqualTo(0));
      }
    });
  });

  group('synthetic inputs', () {
    test('fillPattern is deterministic and varied', () {
      final Uint8List first = Uint8List(64);
      final Uint8List second = Uint8List(64);
      fillPattern(first);
      fillPattern(second);

      expect(first, second);
      expect(first.toSet().length, greaterThan(16));

      final Uint8List reseeded = Uint8List(64);
      fillPattern(reseeded, seed: 42);

      expect(reseeded, isNot(first));
    });

    test('planes convert through the kernels they target', () {
      final PixelPlane bgra = syntheticBgra8888(tiny);
      final PixelPlane nv21 = syntheticNv21(tiny);
      final ({PixelPlane y, PixelPlane u, PixelPlane v}) planar = syntheticYuv420Planar(tiny);
      final ({PixelPlane y, PixelPlane u, PixelPlane v}) semi = syntheticYuv420SemiPlanar(tiny);

      expect(bgra.rowStride, tiny.width * 4 + 64);
      expect(nv21.rowStride, tiny.width + 32);
      expect(semi.u.pixelStride, 2);
      expect(semi.v.bytes.length, semi.u.bytes.length - 1);

      expect(
        PixelConverter.bgra8888ToSrgba(width: tiny.width, height: tiny.height, plane: bgra).format,
        MpImageFormat.srgba,
      );
      expect(
        PixelConverter.nv21ToSrgb(width: tiny.width, height: tiny.height, plane: nv21).format,
        MpImageFormat.srgb,
      );
      expect(
        PixelConverter.yuv420ToSrgb(
          width: tiny.width,
          height: tiny.height,
          y: planar.y,
          u: planar.u,
          v: planar.v,
        ).byteLength,
        tiny.width * tiny.height * 3,
      );
      expect(
        PixelConverter.yuv420ToSrgb(
          width: tiny.width,
          height: tiny.height,
          y: semi.y,
          u: semi.u,
          v: semi.v,
        ).byteLength,
        tiny.width * tiny.height * 3,
      );
    });

    test('packed buffers match the image formats they feed', () {
      expect(syntheticSrgbBytes(tiny), hasLength(tiny.width * tiny.height * 3));
      expect(syntheticSrgbaBytes(tiny), hasLength(tiny.width * tiny.height * 4));
      expect(sizeLabel(tiny), '32x16');
      expect(sizeLabel(hd720), '1280x720');
    });
  });

  group('isolate workers', () {
    test('answer with byte length and echo', () {
      final MpImage image = MpImageUint8.adopt(
        width: 2,
        height: 1,
        format: MpImageFormat.gray8,
        data: Uint8List.fromList(<int>[1, 2]),
      );

      expect(byteLengthWorkerFactory(null)(image), 2);
      expect(identical(echoWorkerFactory(null)(image), image), isTrue);
    });
  });

  test('the executable entry point runs the quick suite', () async {
    final ProcessResult result = await Process.run(_dartExecutable(), <String>[
      'run',
      'benchmarks/bin/run.dart',
      '--quick',
      '--list',
      '--filter',
      'result_containers',
    ], workingDirectory: _repositoryRoot());

    expect(result.exitCode, 0, reason: '${result.stderr}');
    expect(result.stdout, contains('result_containers/normalized_landmarks/face_478'));
  }, timeout: const Timeout(Duration(minutes: 3)));

  test('locates a dart executable', () {
    final String dart = _dartExecutable();

    expect(dart, isNotEmpty);
    expect(_fileName(dart), anyOf('dart', 'dart.exe'));
  });
}

/// The `dart` command-line tool to spawn.
///
/// Under `dart test` the running executable is `dart` itself. Under
/// `flutter test` it is the `flutter_tester` engine binary, which has no `run`
/// command, so the Dart SDK bundled with that Flutter checkout is located by
/// walking up to the SDK root; `dart` on the search path is the last resort.
String _dartExecutable() {
  final String resolved = Platform.resolvedExecutable;

  if (_fileName(resolved) == 'dart' || _fileName(resolved) == 'dart.exe') return resolved;

  final String suffix = Platform.isWindows ? '.exe' : '';
  Directory directory = File(resolved).parent;

  while (directory.path != directory.parent.path) {
    final File bundled = File('${directory.path}/bin/cache/dart-sdk/bin/dart$suffix');

    if (bundled.existsSync()) return bundled.path;

    directory = directory.parent;
  }

  return 'dart';
}

String _fileName(String path) => path.split(RegExp(r'[\\/]')).last;

String _repositoryRoot() {
  Directory directory = Directory.current;

  while (!File('${directory.path}/benchmarks/pubspec.yaml').existsSync()) {
    final Directory parent = directory.parent;

    if (parent.path == directory.path) {
      throw StateError('Could not locate the repository root from ${Directory.current.path}.');
    }

    directory = parent;
  }

  return directory.path;
}
