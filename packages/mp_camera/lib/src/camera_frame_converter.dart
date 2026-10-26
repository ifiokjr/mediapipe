import 'package:camera/camera.dart';
import 'package:mp_core/mp_core.dart';

import 'camera_frame.dart';
import 'rotation_math.dart';

/// Converts `package:camera` image buffers to tightly packed MP images.
///
/// The converter understands BGRA8888, NV21, and three-plane YUV420 and hands
/// each plane to the CPU kernels in [PixelConverter], which write one freshly
/// allocated buffer that the returned image adopts without a second copy. JPEG
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
        rotationDegrees: normalizeRotationDegrees(rotationDegrees),
      ),
      mirroredPreview: mirroredPreview,
    );
  }

  static MpImage _fromBgra8888(CameraImage image) {
    _requirePlaneCount(image, 1);

    return PixelConverter.bgra8888ToSrgba(
      width: image.width,
      height: image.height,
      plane: _plane(image.planes.single, defaultPixelStride: 4),
    );
  }

  static MpImage _fromNv21(CameraImage image) {
    _requirePlaneCount(image, 1);

    return PixelConverter.nv21ToSrgb(
      width: image.width,
      height: image.height,
      plane: _plane(image.planes.single, defaultPixelStride: 1),
    );
  }

  static MpImage _fromYuv420(CameraImage image) {
    _requirePlaneCount(image, 3);

    return PixelConverter.yuv420ToSrgb(
      width: image.width,
      height: image.height,
      y: _plane(image.planes[0], defaultPixelStride: 1),
      u: _plane(image.planes[1], defaultPixelStride: 1),
      v: _plane(image.planes[2], defaultPixelStride: 1),
    );
  }

  /// Wraps a camera plane without copying its bytes.
  ///
  /// `package:camera` omits the pixel stride on platforms whose planes are
  /// always packed, so [defaultPixelStride] supplies the format's sample size.
  static PixelPlane _plane(Plane plane, {required int defaultPixelStride}) => PixelPlane(
    bytes: plane.bytes,
    rowStride: plane.bytesPerRow,
    pixelStride: plane.bytesPerPixel ?? defaultPixelStride,
  );

  static void _requirePlaneCount(CameraImage image, int count) {
    if (image.planes.length != count) {
      throw StateError(
        '${image.format.group.name} requires $count plane(s), '
        'received ${image.planes.length}.',
      );
    }
  }
}
