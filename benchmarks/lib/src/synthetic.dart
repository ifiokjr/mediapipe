import 'dart:typed_data';

import 'package:mp_core/mp_core.dart';

/// Frame dimensions shared by the suites.
typedef FrameSize = ({int width, int height});

/// The 720p landscape frame most camera pipelines feed to a landmarker.
const FrameSize hd720 = (width: 1280, height: 720);

/// A tiny frame for tests and smoke runs; even dimensions keep NV21 and
/// YUV420 valid.
const FrameSize tiny = (width: 32, height: 16);

/// Formats [size] the way benchmark variants are named.
String sizeLabel(FrameSize size) => '${size.width}x${size.height}';

/// Fills [bytes] with a deterministic pseudo-random pattern.
///
/// Real frames exercise every clamp branch of the YUV kernels; zeroed buffers
/// would let the branch predictor flatter the conversion loops.
void fillPattern(Uint8List bytes, {int seed = 0x9E3779B9}) {
  int state = seed & 0xFFFFFFFF;

  for (int index = 0; index < bytes.length; index += 1) {
    state = (state * 1664525 + 1013904223) & 0xFFFFFFFF;
    bytes[index] = state >> 24;
  }
}

/// A padded BGRA8888 plane such as iOS delivers.
PixelPlane syntheticBgra8888(FrameSize size, {int rowPadding = 64}) {
  final int rowStride = size.width * 4 + rowPadding;
  final Uint8List bytes = Uint8List(rowStride * size.height);
  fillPattern(bytes, seed: 1);

  return PixelPlane(bytes: bytes, rowStride: rowStride, pixelStride: 4);
}

/// A padded NV21 buffer such as Android's legacy camera delivers.
PixelPlane syntheticNv21(FrameSize size, {int rowPadding = 32}) {
  final int rowStride = size.width + rowPadding;
  final Uint8List bytes = Uint8List(rowStride * size.height + rowStride * (size.height ~/ 2));
  fillPattern(bytes, seed: 2);

  return PixelPlane(bytes: bytes, rowStride: rowStride);
}

/// Three fully planar YUV420 planes (I420) with padded rows.
({PixelPlane y, PixelPlane u, PixelPlane v}) syntheticYuv420Planar(
  FrameSize size, {
  int rowPadding = 32,
}) {
  final int lumaStride = size.width + rowPadding;
  final int chromaStride = size.width ~/ 2 + rowPadding;
  final Uint8List y = Uint8List(lumaStride * size.height);
  final Uint8List u = Uint8List(chromaStride * (size.height ~/ 2));
  final Uint8List v = Uint8List(chromaStride * (size.height ~/ 2));
  fillPattern(y, seed: 3);
  fillPattern(u, seed: 4);
  fillPattern(v, seed: 5);

  return (
    y: PixelPlane(bytes: y, rowStride: lumaStride),
    u: PixelPlane(bytes: u, rowStride: chromaStride),
    v: PixelPlane(bytes: v, rowStride: chromaStride),
  );
}

/// YUV420 as Android's CameraX reports it: a luma plane plus one interleaved
/// chroma buffer exposed as two planes with a pixel stride of two.
({PixelPlane y, PixelPlane u, PixelPlane v}) syntheticYuv420SemiPlanar(FrameSize size) {
  final Uint8List y = Uint8List(size.width * size.height);
  final Uint8List chroma = Uint8List(size.width * (size.height ~/ 2));
  fillPattern(y, seed: 6);
  fillPattern(chroma, seed: 7);

  return (
    y: PixelPlane(bytes: y, rowStride: size.width),
    u: PixelPlane(bytes: chroma, rowStride: size.width, pixelStride: 2),
    v: PixelPlane(bytes: Uint8List.sublistView(chroma, 1), rowStride: size.width, pixelStride: 2),
  );
}

/// A packed RGB buffer with the length [MpImageFormat.srgb] requires.
Uint8List syntheticSrgbBytes(FrameSize size) {
  final Uint8List bytes = Uint8List(size.width * size.height * 3);
  fillPattern(bytes, seed: 8);

  return bytes;
}

/// A packed RGBA buffer with the length [MpImageFormat.srgba] requires.
Uint8List syntheticSrgbaBytes(FrameSize size) {
  final Uint8List bytes = Uint8List(size.width * size.height * 4);
  fillPattern(bytes, seed: 9);

  return bytes;
}
