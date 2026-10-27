@TestOn('vm')
library;

import 'dart:typed_data';

import 'package:mp_core/mp_core.dart';
import 'package:mp_core/native.dart' show nativePixelConversionSupported;
import 'package:test/test.dart';

// libyuv converts with fixed-point BT.601 constants whose rounding differs
// from the Dart kernels by at most a couple of levels per channel. Inference
// is insensitive to that, but the two paths must agree within this bound.
const int _maximumChannelDelta = 2;

void main() {
  setUp(() => PixelConverter.forceDartKernels = false);
  tearDown(() => PixelConverter.forceDartKernels = false);

  test('the built runtime exports the pixel conversion symbols', () {
    expect(nativePixelConversionSupported, isTrue);
  });

  test('BGRA swizzle matches the Dart kernel exactly', () {
    final PixelPlane plane = _plane(_pattern(2 * 12, seed: 3), rowStride: 12, pixelStride: 4);

    final MpImageUint8 native = PixelConverter.bgra8888ToSrgba(width: 2, height: 2, plane: plane);
    PixelConverter.forceDartKernels = true;
    final MpImageUint8 dart = PixelConverter.bgra8888ToSrgba(width: 2, height: 2, plane: plane);

    expect(native.data, dart.data);
  });

  test('NV21 and YUV420 conversions agree with the Dart kernels within rounding', () {
    const int width = 64;
    const int height = 32;
    final PixelPlane nv21 = _plane(
      _pattern((width + 16) * height * 3 ~/ 2, seed: 5),
      rowStride: width + 16,
    );
    final PixelPlane y = _plane(_pattern((width + 8) * height, seed: 7), rowStride: width + 8);
    final PixelPlane u = _plane(
      _pattern((width ~/ 2 + 4) * (height ~/ 2), seed: 11),
      rowStride: width ~/ 2 + 4,
    );
    final PixelPlane v = _plane(
      _pattern((width ~/ 2 + 4) * (height ~/ 2), seed: 13),
      rowStride: width ~/ 2 + 4,
    );
    final Uint8List chroma = _pattern(width * (height ~/ 2), seed: 17);
    final PixelPlane semiU = PixelPlane(bytes: chroma, rowStride: width, pixelStride: 2);
    final PixelPlane semiV = PixelPlane(
      bytes: Uint8List.sublistView(chroma, 1),
      rowStride: width,
      pixelStride: 2,
    );
    final PixelPlane semiY = _plane(_pattern(width * height, seed: 19), rowStride: width);

    final MpImageUint8 nativeNv21 = PixelConverter.nv21ToSrgb(
      width: width,
      height: height,
      plane: nv21,
    );
    final MpImageUint8 nativePlanar = PixelConverter.yuv420ToSrgb(
      width: width,
      height: height,
      y: y,
      u: u,
      v: v,
    );
    final MpImageUint8 nativeSemi = PixelConverter.yuv420ToSrgb(
      width: width,
      height: height,
      y: semiY,
      u: semiU,
      v: semiV,
    );

    PixelConverter.forceDartKernels = true;

    final MpImageUint8 dartNv21 = PixelConverter.nv21ToSrgb(
      width: width,
      height: height,
      plane: nv21,
    );
    final MpImageUint8 dartPlanar = PixelConverter.yuv420ToSrgb(
      width: width,
      height: height,
      y: y,
      u: u,
      v: v,
    );
    final MpImageUint8 dartSemi = PixelConverter.yuv420ToSrgb(
      width: width,
      height: height,
      y: semiY,
      u: semiU,
      v: semiV,
    );

    expect(_maximumDelta(nativeNv21.data, dartNv21.data), lessThanOrEqualTo(_maximumChannelDelta));
    expect(
      _maximumDelta(nativePlanar.data, dartPlanar.data),
      lessThanOrEqualTo(_maximumChannelDelta),
    );
    expect(_maximumDelta(nativeSemi.data, dartSemi.data), lessThanOrEqualTo(_maximumChannelDelta));
  });

  test('neutral chroma converts to exact gray through the native path', () {
    final MpImageUint8 image = PixelConverter.nv21ToSrgb(
      width: 2,
      height: 2,
      plane: _plane(<int>[16, 235, 99, 99, 81, 145, 99, 99, 128, 128, 99, 99], rowStride: 4),
    );
    final List<int> pixels = image.data;

    expect(pixels.sublist(0, 3), <int>[0, 0, 0]);
    expect(pixels.sublist(3, 6), <int>[255, 255, 255]);
    expect((pixels[6] - 76).abs(), lessThanOrEqualTo(_maximumChannelDelta));
    expect((pixels[9] - 150).abs(), lessThanOrEqualTo(_maximumChannelDelta));
  });
}

PixelPlane _plane(List<int> bytes, {required int rowStride, int pixelStride = 1}) =>
    PixelPlane(bytes: Uint8List.fromList(bytes), rowStride: rowStride, pixelStride: pixelStride);

Uint8List _pattern(int length, {required int seed}) {
  final Uint8List bytes = Uint8List(length);
  int state = seed & 0xFFFFFFFF;

  for (int index = 0; index < length; index += 1) {
    state = (state * 1664525 + 1013904223) & 0xFFFFFFFF;
    bytes[index] = state >> 24;
  }

  return bytes;
}

int _maximumDelta(Uint8List first, Uint8List second) {
  expect(first.length, second.length);

  int maximum = 0;

  for (int index = 0; index < first.length; index += 1) {
    final int delta = (first[index] - second[index]).abs();

    if (delta > maximum) maximum = delta;
  }

  return maximum;
}
