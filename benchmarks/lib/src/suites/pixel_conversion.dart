import 'package:mp_core/mp_core.dart';

import '../harness.dart';
import '../synthetic.dart';

/// Camera pixel-layout conversions, the first per-frame cost of live inference.
BenchmarkSuite pixelConversionSuite({FrameSize size = hd720}) {
  final String label = sizeLabel(size);
  late PixelPlane bgra;
  late PixelPlane nv21;
  late ({PixelPlane y, PixelPlane u, PixelPlane v}) planar;
  late ({PixelPlane y, PixelPlane u, PixelPlane v}) semiPlanar;

  return BenchmarkSuite(
    name: 'pixel_conversion',
    benchmarks: <Benchmark>[
      Benchmark(
        name: 'pixel_conversion/bgra8888_to_srgba/$label',
        setUp: () => bgra = syntheticBgra8888(size),
        run: () =>
            PixelConverter.bgra8888ToSrgba(width: size.width, height: size.height, plane: bgra),
      ),
      Benchmark(
        name: 'pixel_conversion/nv21_to_srgb/$label',
        setUp: () => nv21 = syntheticNv21(size),
        run: () => PixelConverter.nv21ToSrgb(width: size.width, height: size.height, plane: nv21),
      ),
      Benchmark(
        name: 'pixel_conversion/yuv420_planar_to_srgb/$label',
        setUp: () => planar = syntheticYuv420Planar(size),
        run: () => PixelConverter.yuv420ToSrgb(
          width: size.width,
          height: size.height,
          y: planar.y,
          u: planar.u,
          v: planar.v,
        ),
      ),
      Benchmark(
        name: 'pixel_conversion/yuv420_semiplanar_to_srgb/$label',
        setUp: () => semiPlanar = syntheticYuv420SemiPlanar(size),
        run: () => PixelConverter.yuv420ToSrgb(
          width: size.width,
          height: size.height,
          y: semiPlanar.y,
          u: semiPlanar.u,
          v: semiPlanar.v,
        ),
      ),
    ],
  );
}
