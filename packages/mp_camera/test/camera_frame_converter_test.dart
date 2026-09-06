import 'dart:typed_data';

import 'package:camera/camera.dart';
import 'package:camera_platform_interface/camera_platform_interface.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mp_camera/mp_camera.dart';
import 'package:mp_core/mp_core.dart';

void main() {
  group('MpCameraFrameConverter', () {
    test('converts padded BGRA rows to tightly packed RGBA', () {
      final CameraImage image = _cameraImage(
        width: 2,
        height: 1,
        format: ImageFormatGroup.bgra8888,
        planes: [
          _plane(
            <int>[30, 20, 10, 255, 60, 50, 40, 128, 99, 99, 99, 99],
            bytesPerRow: 12,
            bytesPerPixel: 4,
          ),
        ],
      );

      final MpCameraFrame frame = MpCameraFrameConverter.convert(
        image,
        timestampMs: 7,
        rotationDegrees: -90,
        mirroredPreview: true,
      );

      expect(frame.timestampMs, 7);
      expect(frame.processingOptions.rotationDegrees, 270);
      expect(frame.mirroredPreview, isTrue);
      expect(frame.image.format, MpImageFormat.srgba);
      expect((frame.image as MpImageUint8).data, <int>[10, 20, 30, 255, 40, 50, 60, 128]);
    });

    test('converts neutral NV21 using row strides', () {
      final CameraImage image = _cameraImage(
        width: 2,
        height: 2,
        format: ImageFormatGroup.nv21,
        planes: [
          _plane(
            <int>[16, 235, 99, 99, 81, 145, 99, 99, 128, 128, 99, 99],
            bytesPerRow: 4,
            bytesPerPixel: 1,
          ),
        ],
      );

      final MpCameraFrame frame = MpCameraFrameConverter.convert(
        image,
        timestampMs: 1,
        rotationDegrees: 0,
      );
      final Uint8List pixels = (frame.image as MpImageUint8).data;

      expect(pixels.sublist(0, 3), <int>[0, 0, 0]);
      expect(pixels.sublist(3, 6), <int>[255, 255, 255]);
      expect(pixels.sublist(6, 9), <int>[76, 76, 76]);
      expect(pixels.sublist(9, 12), <int>[150, 150, 150]);
    });

    test('converts YUV420 with independent row and pixel strides', () {
      final CameraImage image = _cameraImage(
        width: 2,
        height: 2,
        format: ImageFormatGroup.yuv420,
        planes: [
          _plane(<int>[82, 82, 0, 82, 82, 0], bytesPerRow: 3, bytesPerPixel: 1),
          _plane(<int>[90, 0], bytesPerRow: 2, bytesPerPixel: 2),
          _plane(<int>[240, 0], bytesPerRow: 2, bytesPerPixel: 2),
        ],
      );

      final MpCameraFrame frame = MpCameraFrameConverter.convert(
        image,
        timestampMs: 2,
        rotationDegrees: 90,
      );
      final Uint8List pixels = (frame.image as MpImageUint8).data;

      for (int offset = 0; offset < pixels.length; offset += 3) {
        expect(pixels.sublist(offset, offset + 3), <int>[255, 1, 0]);
      }
    });

    test('rejects unsupported formats and invalid timestamps', () {
      final CameraImage image = _cameraImage(
        width: 1,
        height: 1,
        format: ImageFormatGroup.jpeg,
        planes: [
          _plane(<int>[0], bytesPerRow: 1, bytesPerPixel: 1),
        ],
      );

      expect(
        () => MpCameraFrameConverter.convert(image, timestampMs: 0, rotationDegrees: 0),
        throwsUnsupportedError,
      );
      expect(
        () => MpCameraFrameConverter.convert(image, timestampMs: -1, rotationDegrees: 0),
        throwsArgumentError,
      );
    });
  });
}

CameraImage _cameraImage({
  required int width,
  required int height,
  required ImageFormatGroup format,
  required List<CameraImagePlane> planes,
}) => CameraImage.fromPlatformInterface(
  CameraImageData(
    format: CameraImageFormat(format, raw: 0),
    height: height,
    lensAperture: 0,
    planes: planes,
    sensorExposureTime: 0,
    sensorSensitivity: 0,
    width: width,
  ),
);

CameraImagePlane _plane(List<int> bytes, {required int bytesPerRow, required int bytesPerPixel}) =>
    CameraImagePlane(
      bytes: Uint8List.fromList(bytes),
      bytesPerPixel: bytesPerPixel,
      bytesPerRow: bytesPerRow,
    );
