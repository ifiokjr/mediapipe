@ffi.DefaultAsset('package:mp_core/native.dart')
// Underscore-prefixed externals mirror the generated bindings' convention for
// raw C symbols.
// ignore_for_file: non_constant_identifier_names
library;

import 'dart:ffi' as ffi;
import 'dart:typed_data';

import 'package:ffi/ffi.dart';
import 'package:meta/meta.dart';

import '../image.dart';
import '../pixel_conversion.dart' show PixelConverter;

// libyuv-backed pixel conversion. The functions only exist in native runtimes
// built from this repository after the pixel shim; when an older or unbundled
// runtime is linked, symbol resolution fails and every kernel falls back to
// the pure Dart implementation in `pixel_conversion.dart`.

bool? _supported;

/// Whether the linked native runtime accelerates [PixelConverter] with libyuv.
///
/// False when no runtime is bundled or an older runtime without the pixel
/// shim is linked; conversions then run the pure Dart kernels with identical
/// semantics.
bool get nativePixelConversionSupported => _supported ??= _probe();

bool _probe() {
  try {
    // A probe call with no buffers returns the invalid-argument status
    // without touching memory, proving the symbol resolves.
    _MpPixelBgraToSrgba(ffi.nullptr, 0, 0, 0, ffi.nullptr);

    return true;
  } on ArgumentError {
    return false;
  }
}

/// Accelerated BGRA8888 → sRGBA conversion, or `null` when unavailable.
@internal
MpImageUint8? acceleratedBgraToSrgba(int width, int height, Uint8List bytes, int rowStride) {
  if (!nativePixelConversionSupported) return null;

  final ffi.Pointer<ffi.Uint8> src = malloc<ffi.Uint8>(bytes.length);
  final ffi.Pointer<ffi.Uint8> dst = malloc<ffi.Uint8>(width * height * 4);

  try {
    src.asTypedList(bytes.length).setAll(0, bytes);

    if (_MpPixelBgraToSrgba(src, rowStride, width, height, dst) != 0) return null;

    return MpImageUint8.adopt(
      width: width,
      height: height,
      format: MpImageFormat.srgba,
      data: Uint8List.fromList(dst.asTypedList(width * height * 4)),
    );
  } finally {
    malloc
      ..free(src)
      ..free(dst);
  }
}

/// Accelerated NV21 → sRGB conversion, or `null` when unavailable.
@internal
MpImageUint8? acceleratedNv21ToSrgb(int width, int height, Uint8List bytes, int rowStride) {
  if (!nativePixelConversionSupported) return null;

  final ffi.Pointer<ffi.Uint8> src = malloc<ffi.Uint8>(bytes.length);
  final ffi.Pointer<ffi.Uint8> dst = malloc<ffi.Uint8>(width * height * 3);

  try {
    src.asTypedList(bytes.length).setAll(0, bytes);

    if (_MpPixelNv21ToSrgb(src, rowStride, width, height, dst) != 0) return null;

    return MpImageUint8.adopt(
      width: width,
      height: height,
      format: MpImageFormat.srgb,
      data: Uint8List.fromList(dst.asTypedList(width * height * 3)),
    );
  } finally {
    malloc
      ..free(src)
      ..free(dst);
  }
}

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
}) {
  if (!nativePixelConversionSupported) return null;

  final ffi.Pointer<ffi.Uint8> yPlane = malloc<ffi.Uint8>(y.length);
  final ffi.Pointer<ffi.Uint8> uPlane = malloc<ffi.Uint8>(u.length);
  final ffi.Pointer<ffi.Uint8> vPlane = malloc<ffi.Uint8>(v.length);
  final ffi.Pointer<ffi.Uint8> dst = malloc<ffi.Uint8>(width * height * 3);

  try {
    yPlane.asTypedList(y.length).setAll(0, y);
    uPlane.asTypedList(u.length).setAll(0, u);
    vPlane.asTypedList(v.length).setAll(0, v);

    final int status = _MpPixelYuv420ToSrgb(
      yPlane,
      yRowStride,
      yPixelStride,
      uPlane,
      uRowStride,
      uPixelStride,
      vPlane,
      vRowStride,
      vPixelStride,
      width,
      height,
      dst,
    );

    if (status != 0) return null;

    return MpImageUint8.adopt(
      width: width,
      height: height,
      format: MpImageFormat.srgb,
      data: Uint8List.fromList(dst.asTypedList(width * height * 3)),
    );
  } finally {
    malloc
      ..free(yPlane)
      ..free(uPlane)
      ..free(vPlane)
      ..free(dst);
  }
}

@ffi.Native<
  ffi.Int Function(ffi.Pointer<ffi.Uint8>, ffi.Int, ffi.Int, ffi.Int, ffi.Pointer<ffi.Uint8>)
>(symbol: 'MpPixelBgraToSrgba')
external int _MpPixelBgraToSrgba(
  ffi.Pointer<ffi.Uint8> src,
  int srcStride,
  int width,
  int height,
  ffi.Pointer<ffi.Uint8> dst,
);

@ffi.Native<
  ffi.Int Function(ffi.Pointer<ffi.Uint8>, ffi.Int, ffi.Int, ffi.Int, ffi.Pointer<ffi.Uint8>)
>(symbol: 'MpPixelNv21ToSrgb')
external int _MpPixelNv21ToSrgb(
  ffi.Pointer<ffi.Uint8> src,
  int srcStride,
  int width,
  int height,
  ffi.Pointer<ffi.Uint8> dst,
);

@ffi.Native<
  ffi.Int Function(
    ffi.Pointer<ffi.Uint8>,
    ffi.Int,
    ffi.Int,
    ffi.Pointer<ffi.Uint8>,
    ffi.Int,
    ffi.Int,
    ffi.Pointer<ffi.Uint8>,
    ffi.Int,
    ffi.Int,
    ffi.Int,
    ffi.Int,
    ffi.Pointer<ffi.Uint8>,
  )
>(symbol: 'MpPixelYuv420ToSrgb')
external int _MpPixelYuv420ToSrgb(
  ffi.Pointer<ffi.Uint8> y,
  int yStride,
  int yPixelStride,
  ffi.Pointer<ffi.Uint8> u,
  int uStride,
  int uPixelStride,
  ffi.Pointer<ffi.Uint8> v,
  int vStride,
  int vPixelStride,
  int width,
  int height,
  ffi.Pointer<ffi.Uint8> dst,
);
