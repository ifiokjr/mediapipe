import 'dart:typed_data';

import 'package:meta/meta.dart';

import 'image.dart';

// The default (browser) pixel-conversion accelerator: there is none, so every
// kernel runs the pure Dart implementation. Native builds override this file
// through the conditional import in `pixel_conversion.dart`.

/// Accelerated BGRA8888 → sRGBA conversion, or `null` when unavailable.
@internal
MpImageUint8? acceleratedBgraToSrgba(int width, int height, Uint8List bytes, int rowStride) => null;

/// Accelerated NV21 → sRGB conversion, or `null` when unavailable.
@internal
MpImageUint8? acceleratedNv21ToSrgb(int width, int height, Uint8List bytes, int rowStride) => null;

/// Accelerated YUV420 → sRGB conversion, or `null` when unavailable.
@internal
MpImageUint8? acceleratedYuv420ToSrgb({
  required int width,
  required int height,
  required Uint8List y,
  required int yRowStride,
  required int yPixelStride,
  required Uint8List u,
  required int uRowStride,
  required int uPixelStride,
  required Uint8List v,
  required int vRowStride,
  required int vPixelStride,
}) => null;
