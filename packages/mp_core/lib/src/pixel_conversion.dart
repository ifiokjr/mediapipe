import 'dart:typed_data';

import 'package:meta/meta.dart';

import 'image.dart';

/// One plane of a camera or decoder frame.
///
/// Producers routinely pad their buffers, so [rowStride] may exceed the packed
/// row width and [pixelStride] may exceed the sample size. Conversions read
/// through both strides and never assume a packed layout.
@immutable
final class PixelPlane {
  /// Describes [bytes] laid out with the given strides.
  const PixelPlane({required this.bytes, required this.rowStride, this.pixelStride = 1});

  /// Raw plane samples.
  final Uint8List bytes;

  /// Bytes between the first sample of adjacent rows.
  final int rowStride;

  /// Bytes between adjacent samples within one row.
  final int pixelStride;
}

/// CPU conversions from common camera pixel layouts into packed [MpImage]s.
///
/// Every conversion validates plane strides and buffer lengths against the
/// requested dimensions, writes one freshly allocated buffer, and returns an
/// image that adopts that buffer rather than copying it again. These kernels
/// are the per-frame hot path for live camera inference; the `benchmarks/`
/// package measures them and CI fails on regressions.
abstract final class PixelConverter {
  /// Converts a single BGRA8888 [plane] into an [MpImageFormat.srgba] image.
  ///
  /// MediaPipe has no BGRA input format, so the channels are swizzled while
  /// the padded rows are packed.
  static MpImageUint8 bgra8888ToSrgba({
    required int width,
    required int height,
    required PixelPlane plane,
  }) {
    _requireDimensions(width, height);
    const int bytesPerPixel = 4;
    final int rowStride = plane.rowStride;
    final int minimumRowStride = width * bytesPerPixel;

    if (plane.pixelStride != bytesPerPixel) {
      throw StateError('BGRA8888 pixel stride must be $bytesPerPixel, got ${plane.pixelStride}.');
    }

    if (rowStride < minimumRowStride) {
      throw StateError('BGRA8888 row stride $rowStride is smaller than $minimumRowStride.');
    }

    _requireBufferLength(plane, minimumLength: rowStride * height, format: 'BGRA8888');

    final Uint8List rgba = Uint8List(width * height * bytesPerPixel);
    final Uint8List bytes = plane.bytes;
    int destination = 0;

    for (int y = 0; y < height; y += 1) {
      int source = y * rowStride;

      for (int x = 0; x < width; x += 1) {
        final int blue = bytes[source];
        final int green = bytes[source + 1];
        final int red = bytes[source + 2];
        final int alpha = bytes[source + 3];
        rgba[destination] = red;
        rgba[destination + 1] = green;
        rgba[destination + 2] = blue;
        rgba[destination + 3] = alpha;
        source += bytesPerPixel;
        destination += bytesPerPixel;
      }
    }

    return MpImageUint8.adopt(
      width: width,
      height: height,
      format: MpImageFormat.srgba,
      data: rgba,
    );
  }

  /// Converts an NV21 [plane] into an [MpImageFormat.srgb] image.
  ///
  /// NV21 stores the full-resolution Y rows first, followed by half-height rows
  /// of interleaved V and U samples that share [PixelPlane.rowStride].
  static MpImageUint8 nv21ToSrgb({
    required int width,
    required int height,
    required PixelPlane plane,
  }) {
    _requireDimensions(width, height);
    _requireEvenDimensions(width, height, format: 'NV21');

    if (plane.pixelStride != 1) {
      throw StateError('NV21 pixel stride must be 1, got ${plane.pixelStride}.');
    }

    final int rowStride = plane.rowStride;

    if (rowStride < width) {
      throw StateError('NV21 row stride $rowStride is smaller than $width.');
    }

    final int yPlaneLength = rowStride * height;
    final int chromaRows = height ~/ 2;
    _requireBufferLength(
      plane,
      minimumLength: yPlaneLength + rowStride * chromaRows,
      format: 'NV21',
    );

    final Uint8List rgb = Uint8List(width * height * 3);
    final Uint8List bytes = plane.bytes;
    int destination = 0;

    for (int y = 0; y < height; y += 1) {
      final int yRow = y * rowStride;
      final int uvRow = yPlaneLength + (y ~/ 2) * rowStride;

      // NV21 interleaves chroma per pixel pair; sample it once per pair.
      for (int x = 0; x < width; x += 2) {
        final int uv = uvRow + x;
        final int u = bytes[uv + 1];
        final int v = bytes[uv];
        _writeYuvPixel(rgb, destination, y: bytes[yRow + x], u: u, v: v);
        _writeYuvPixel(rgb, destination + 3, y: bytes[yRow + x + 1], u: u, v: v);
        destination += 6;
      }
    }

    return MpImageUint8.adopt(width: width, height: height, format: MpImageFormat.srgb, data: rgb);
  }

  /// Converts three-plane YUV420 into an [MpImageFormat.srgb] image.
  ///
  /// Each chroma plane is half the luma resolution in both directions and may
  /// carry its own row and pixel strides, which covers both planar I420 and the
  /// semi-planar layouts Android reports as three interleaved planes.
  static MpImageUint8 yuv420ToSrgb({
    required int width,
    required int height,
    required PixelPlane y,
    required PixelPlane u,
    required PixelPlane v,
  }) {
    _requireDimensions(width, height);
    _requireEvenDimensions(width, height, format: 'YUV420');
    _validatePlane(y, width: width, height: height, name: 'Y');
    _validatePlane(u, width: width ~/ 2, height: height ~/ 2, name: 'U');
    _validatePlane(v, width: width ~/ 2, height: height ~/ 2, name: 'V');

    final Uint8List rgb = Uint8List(width * height * 3);
    final int rowSamples = width * 3;
    final Uint8List yBytes = y.bytes;
    final Uint8List uBytes = u.bytes;
    final Uint8List vBytes = v.bytes;
    final int yRowStride = y.rowStride;
    final int uRowStride = u.rowStride;
    final int vRowStride = v.rowStride;
    final int yPixelStride = y.pixelStride;
    final int uPixelStride = u.pixelStride;
    final int vPixelStride = v.pixelStride;

    for (int row = 0; row < height; row += 1) {
      final int yRow = row * yRowStride;
      final int uRow = (row ~/ 2) * uRowStride;
      final int vRow = (row ~/ 2) * vRowStride;
      int destination = row * rowSamples;

      // Dimensions are validated even, so every row is a whole number of
      // chroma pairs; sample each chroma value once for two luma samples.
      for (int x = 0; x < width; x += 2) {
        final int chroma = x ~/ 2;
        final int uValue = uBytes[uRow + chroma * uPixelStride];
        final int vValue = vBytes[vRow + chroma * vPixelStride];
        _writeYuvPixel(rgb, destination, y: yBytes[yRow + x * yPixelStride], u: uValue, v: vValue);
        _writeYuvPixel(
          rgb,
          destination + 3,
          y: yBytes[yRow + (x + 1) * yPixelStride],
          u: uValue,
          v: vValue,
        );
        destination += 6;
      }
    }

    return MpImageUint8.adopt(width: width, height: height, format: MpImageFormat.srgb, data: rgb);
  }

  static void _writeYuvPixel(
    Uint8List destination,
    int offset, {
    required int y,
    required int u,
    required int v,
  }) {
    final int luminance = y - 16;
    final int blueDifference = u - 128;
    final int redDifference = v - 128;
    destination[offset] = _clampByte((298 * luminance + 409 * redDifference + 128) >> 8);
    destination[offset + 1] = _clampByte(
      (298 * luminance - 100 * blueDifference - 208 * redDifference + 128) >> 8,
    );
    destination[offset + 2] = _clampByte((298 * luminance + 516 * blueDifference + 128) >> 8);
  }

  static int _clampByte(int value) {
    // Branches avoid the dynamic dispatch of `num.clamp` in this per-pixel path.
    if (value < 0) return 0;
    if (value > 255) return 255;

    return value;
  }

  static void _requireDimensions(int width, int height) {
    if (width <= 0) throw ArgumentError.value(width, 'width', 'must be greater than zero');
    if (height <= 0) throw ArgumentError.value(height, 'height', 'must be greater than zero');
  }

  static void _requireEvenDimensions(int width, int height, {required String format}) {
    if (width.isOdd || height.isOdd) {
      throw StateError('$format dimensions must be even, got ${width}x$height.');
    }
  }

  static void _requireBufferLength(
    PixelPlane plane, {
    required int minimumLength,
    required String format,
  }) {
    if (plane.bytes.length < minimumLength) {
      throw StateError(
        '$format plane contains ${plane.bytes.length} bytes; expected at least $minimumLength.',
      );
    }
  }

  static void _validatePlane(
    PixelPlane plane, {
    required int width,
    required int height,
    required String name,
  }) {
    if (plane.pixelStride <= 0) {
      throw StateError('$name plane pixel stride must be greater than zero.');
    }

    final int minimumRowLength = (width - 1) * plane.pixelStride + 1;

    if (plane.rowStride < minimumRowLength) {
      throw StateError(
        '$name plane row stride ${plane.rowStride} is smaller than $minimumRowLength.',
      );
    }

    final int minimumLength = (height - 1) * plane.rowStride + minimumRowLength;
    _requireBufferLength(plane, minimumLength: minimumLength, format: '$name YUV420');
  }
}
