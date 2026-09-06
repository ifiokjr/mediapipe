import 'dart:typed_data';

import 'package:camera/camera.dart';
import 'package:mp_core/mp_core.dart';

import 'camera_frame.dart';

/// Converts `package:camera` image buffers to tightly packed MP images.
///
/// The converter understands BGRA8888, NV21, and three-plane YUV420. JPEG
/// frames must be decoded by the application before conversion.
final class MpCameraFrameConverter {
  const MpCameraFrameConverter._();

  /// Converts [cameraImage] without mutating or retaining its plane buffers.
  static MpCameraFrame convert(
    CameraImage cameraImage, {
    required int timestampMs,
    required int rotationDegrees,
    bool mirroredPreview = false,
  }) {
    if (timestampMs < 0) {
      throw ArgumentError.value(timestampMs, 'timestampMs', 'must not be negative');
    }
    if (rotationDegrees % 90 != 0) {
      throw ArgumentError.value(rotationDegrees, 'rotationDegrees', 'must be a multiple of 90');
    }

    final MpImage image = switch (cameraImage.format.group) {
      ImageFormatGroup.bgra8888 => _fromBgra8888(cameraImage),
      ImageFormatGroup.nv21 => _fromNv21(cameraImage),
      ImageFormatGroup.yuv420 => _fromYuv420(cameraImage),
      final ImageFormatGroup format => throw UnsupportedError(
        'Camera image format ${format.name} is not supported. '
        'Request BGRA8888 on iOS or NV21/YUV420 on Android.',
      ),
    };

    return MpCameraFrame(
      image: image,
      timestampMs: timestampMs,
      processingOptions: ImageProcessingOptions(
        rotationDegrees: _normalizeRotation(rotationDegrees),
      ),
      mirroredPreview: mirroredPreview,
    );
  }

  static MpImage _fromBgra8888(CameraImage image) {
    _requirePlaneCount(image, 1);
    final Plane plane = image.planes.single;
    final int rowStride = plane.bytesPerRow;
    final int minimumRowStride = image.width * 4;
    if (rowStride < minimumRowStride) {
      throw StateError('BGRA row stride $rowStride is smaller than $minimumRowStride.');
    }
    _requireBufferLength(plane, minimumLength: rowStride * image.height, format: 'BGRA8888');

    final Uint8List rgba = Uint8List(image.width * image.height * 4);
    int destination = 0;
    for (int y = 0; y < image.height; y += 1) {
      int source = y * rowStride;
      for (int x = 0; x < image.width; x += 1) {
        final int blue = plane.bytes[source];
        final int green = plane.bytes[source + 1];
        final int red = plane.bytes[source + 2];
        final int alpha = plane.bytes[source + 3];
        rgba[destination] = red;
        rgba[destination + 1] = green;
        rgba[destination + 2] = blue;
        rgba[destination + 3] = alpha;
        source += 4;
        destination += 4;
      }
    }
    return MpImage.uint8(
      width: image.width,
      height: image.height,
      format: MpImageFormat.srgba,
      data: rgba,
    );
  }

  static MpImage _fromNv21(CameraImage image) {
    _requirePlaneCount(image, 1);
    if (image.width.isOdd || image.height.isOdd) {
      throw StateError('NV21 dimensions must be even, got ${image.width}x${image.height}.');
    }
    final Plane plane = image.planes.single;
    final int rowStride = plane.bytesPerRow;
    if (rowStride < image.width) {
      throw StateError('NV21 row stride $rowStride is smaller than ${image.width}.');
    }
    final int yPlaneLength = rowStride * image.height;
    final int chromaRows = image.height ~/ 2;
    _requireBufferLength(
      plane,
      minimumLength: yPlaneLength + rowStride * chromaRows,
      format: 'NV21',
    );

    final Uint8List rgb = Uint8List(image.width * image.height * 3);
    int destination = 0;
    for (int y = 0; y < image.height; y += 1) {
      final int yRow = y * rowStride;
      final int uvRow = yPlaneLength + (y ~/ 2) * rowStride;
      for (int x = 0; x < image.width; x += 1) {
        final int uv = uvRow + (x & ~1);
        _writeYuvPixel(
          rgb,
          destination,
          y: plane.bytes[yRow + x],
          u: plane.bytes[uv + 1],
          v: plane.bytes[uv],
        );
        destination += 3;
      }
    }
    return MpImage.uint8(
      width: image.width,
      height: image.height,
      format: MpImageFormat.srgb,
      data: rgb,
    );
  }

  static MpImage _fromYuv420(CameraImage image) {
    _requirePlaneCount(image, 3);
    if (image.width.isOdd || image.height.isOdd) {
      throw StateError('YUV420 dimensions must be even, got ${image.width}x${image.height}.');
    }
    final Plane yPlane = image.planes[0];
    final Plane uPlane = image.planes[1];
    final Plane vPlane = image.planes[2];
    final int yPixelStride = yPlane.bytesPerPixel ?? 1;
    final int uPixelStride = uPlane.bytesPerPixel ?? 1;
    final int vPixelStride = vPlane.bytesPerPixel ?? 1;
    _validatePlane(
      yPlane,
      width: image.width,
      height: image.height,
      pixelStride: yPixelStride,
      name: 'Y',
    );
    _validatePlane(
      uPlane,
      width: image.width ~/ 2,
      height: image.height ~/ 2,
      pixelStride: uPixelStride,
      name: 'U',
    );
    _validatePlane(
      vPlane,
      width: image.width ~/ 2,
      height: image.height ~/ 2,
      pixelStride: vPixelStride,
      name: 'V',
    );

    final Uint8List rgb = Uint8List(image.width * image.height * 3);
    int destination = 0;
    for (int y = 0; y < image.height; y += 1) {
      final int yRow = y * yPlane.bytesPerRow;
      final int uvRow = (y ~/ 2) * uPlane.bytesPerRow;
      final int vRow = (y ~/ 2) * vPlane.bytesPerRow;
      for (int x = 0; x < image.width; x += 1) {
        _writeYuvPixel(
          rgb,
          destination,
          y: yPlane.bytes[yRow + x * yPixelStride],
          u: uPlane.bytes[uvRow + (x ~/ 2) * uPixelStride],
          v: vPlane.bytes[vRow + (x ~/ 2) * vPixelStride],
        );
        destination += 3;
      }
    }
    return MpImage.uint8(
      width: image.width,
      height: image.height,
      format: MpImageFormat.srgb,
      data: rgb,
    );
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

  static int _clampByte(int value) => value.clamp(0, 255);

  static int _normalizeRotation(int value) => ((value % 360) + 360) % 360;

  static void _requirePlaneCount(CameraImage image, int count) {
    if (image.planes.length != count) {
      throw StateError(
        '${image.format.group.name} requires $count plane(s), '
        'received ${image.planes.length}.',
      );
    }
  }

  static void _requireBufferLength(
    Plane plane, {
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
    Plane plane, {
    required int width,
    required int height,
    required int pixelStride,
    required String name,
  }) {
    if (pixelStride <= 0) {
      throw StateError('$name plane pixel stride must be greater than zero.');
    }
    final int minimumRowLength = (width - 1) * pixelStride + 1;
    if (plane.bytesPerRow < minimumRowLength) {
      throw StateError(
        '$name plane row stride ${plane.bytesPerRow} is smaller than $minimumRowLength.',
      );
    }
    final int minimumLength = (height - 1) * plane.bytesPerRow + minimumRowLength;
    _requireBufferLength(plane, minimumLength: minimumLength, format: '$name YUV420');
  }
}
