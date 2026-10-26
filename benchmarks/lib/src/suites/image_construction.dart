import 'dart:typed_data';

import 'package:mp_core/mp_core.dart';

import '../harness.dart';
import '../synthetic.dart';

/// The cost of wrapping a pixel buffer as an [MpImage].
///
/// The copying factory and the adopting constructor sit side by side so the
/// gate catches a copy sneaking back into the adopt path.
BenchmarkSuite imageConstructionSuite({FrameSize size = hd720}) {
  final String label = sizeLabel(size);
  late Uint8List rgba;

  return BenchmarkSuite(
    name: 'image_construction',
    benchmarks: <Benchmark>[
      Benchmark(
        name: 'image_construction/uint8_copy/${label}_srgba',
        setUp: () => rgba = syntheticSrgbaBytes(size),
        run: () => MpImage.uint8(
          width: size.width,
          height: size.height,
          format: MpImageFormat.srgba,
          data: rgba,
        ),
      ),
      Benchmark(
        name: 'image_construction/uint8_adopt/${label}_srgba',
        setUp: () => rgba = syntheticSrgbaBytes(size),
        run: () => MpImageUint8.adopt(
          width: size.width,
          height: size.height,
          format: MpImageFormat.srgba,
          data: rgba,
        ),
      ),
    ],
  );
}
