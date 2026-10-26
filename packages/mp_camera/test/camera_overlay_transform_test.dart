import 'dart:typed_data';
import 'dart:ui';

import 'package:flutter/painting.dart' show BoxFit;
import 'package:flutter_test/flutter_test.dart';
import 'package:mp_camera/mp_camera.dart';
import 'package:mp_core/mp_core.dart';

void main() {
  group('CameraOverlayTransform', () {
    test('swaps the image size for quarter-turn rotations', () {
      for (final int rotation in <int>[90, 270, -90, 450]) {
        final CameraOverlayTransform transform = CameraOverlayTransform(
          imageSize: const Size(640, 480),
          rotationDegrees: rotation,
          viewSize: const Size(100, 100),
        );

        expect(transform.uprightSize, const Size(480, 640), reason: 'rotation $rotation');
      }

      for (final int rotation in <int>[0, 180, 360]) {
        expect(
          CameraOverlayTransform(
            imageSize: const Size(640, 480),
            rotationDegrees: rotation,
            viewSize: const Size(100, 100),
          ).uprightSize,
          const Size(640, 480),
        );
      }
    });

    test('rejects invalid sizes and rotations', () {
      expect(
        () => CameraOverlayTransform(
          imageSize: Size.zero,
          rotationDegrees: 0,
          viewSize: const Size(1, 1),
        ),
        throwsArgumentError,
      );
      expect(
        () => CameraOverlayTransform(
          imageSize: const Size(1, 1),
          rotationDegrees: 45,
          viewSize: const Size(1, 1),
        ),
        throwsArgumentError,
      );
      expect(
        () => CameraOverlayTransform(
          imageSize: const Size(1, 1),
          rotationDegrees: 0,
          viewSize: const Size(0, 1),
        ),
        throwsArgumentError,
      );
    });

    test('cover crops the overflowing axis around the centre', () {
      final CameraOverlayTransform transform = CameraOverlayTransform(
        imageSize: const Size(400, 300),
        rotationDegrees: 0,
        viewSize: const Size(200, 200),
      );

      expect(transform.sourceRect, const Rect.fromLTWH(50, 0, 300, 300));
      expect(transform.destinationRect, const Rect.fromLTWH(0, 0, 200, 200));
      expect(transform.scaleX, closeTo(2 / 3, 1e-9));
      expect(transform.scaleY, closeTo(2 / 3, 1e-9));
      expect(transform.mapNormalized(0.5, 0.5), _closeToOffset(const Offset(100, 100)));
      expect(transform.mapNormalized(0, 0), _closeToOffset(const Offset(-100 / 3, 0)));
      expect(transform.mapNormalized(1, 1), _closeToOffset(const Offset(200 + 100 / 3, 200)));
    });

    test('contain letterboxes and keeps the whole image visible', () {
      final CameraOverlayTransform transform = CameraOverlayTransform(
        imageSize: const Size(400, 300),
        rotationDegrees: 0,
        viewSize: const Size(200, 200),
        fit: BoxFit.contain,
      );

      expect(transform.sourceRect, const Rect.fromLTWH(0, 0, 400, 300));
      expect(transform.destinationRect, const Rect.fromLTWH(0, 25, 200, 150));
      expect(transform.mapNormalized(0, 0), _closeToOffset(const Offset(0, 25)));
      expect(transform.mapNormalized(1, 1), _closeToOffset(const Offset(200, 175)));
      expect(transform.mapNormalized(0.5, 0.5), _closeToOffset(const Offset(100, 100)));
    });

    test('fill stretches each axis independently', () {
      final CameraOverlayTransform transform = CameraOverlayTransform(
        imageSize: const Size(400, 300),
        rotationDegrees: 0,
        viewSize: const Size(200, 600),
        fit: BoxFit.fill,
      );

      expect(transform.scaleX, closeTo(0.5, 1e-9));
      expect(transform.scaleY, closeTo(2, 1e-9));
      expect(transform.mapPixel(400, 300), _closeToOffset(const Offset(200, 600)));
    });

    test('mirrors horizontally for a front-camera preview', () {
      final CameraOverlayTransform transform = CameraOverlayTransform(
        imageSize: const Size(100, 100),
        rotationDegrees: 0,
        viewSize: const Size(100, 100),
        mirrored: true,
      );

      expect(transform.mapNormalized(0.25, 0.75), _closeToOffset(const Offset(75, 75)));
      expect(
        transform.mapBoundingBox(BoundingBox(left: 10, top: 20, width: 30, height: 40)),
        const Rect.fromLTRB(60, 20, 90, 60),
      );
    });

    test('maps landmarks, normalized rectangles, and bounding boxes', () {
      final CameraOverlayTransform transform = CameraOverlayTransform(
        imageSize: const Size(480, 640),
        rotationDegrees: 90,
        viewSize: const Size(320, 240),
        fit: BoxFit.contain,
      );

      // Upright image is 640x480; contain into 320x240 scales by 0.5 exactly.
      expect(transform.uprightSize, const Size(640, 480));
      expect(
        transform.mapLandmark(const NormalizedLandmark(x: 0.5, y: 0.25, z: 0)),
        _closeToOffset(const Offset(160, 60)),
      );
      expect(
        transform.mapNormalizedRect(NormalizedRect(left: 0.25, top: 0.5, right: 0.75, bottom: 1)),
        const Rect.fromLTRB(80, 120, 240, 240),
      );
      expect(
        transform.mapBoundingBox(BoundingBox(left: 64, top: 48, width: 128, height: 96)),
        const Rect.fromLTRB(32, 24, 96, 72),
      );
    });

    test('forFrame reads rotation and mirroring from the frame', () {
      final MpCameraFrame frame = MpCameraFrame(
        image: MpImageUint8.adopt(
          width: 4,
          height: 2,
          format: MpImageFormat.srgb,
          data: Uint8List(24),
        ),
        timestampMs: 0,
        processingOptions: ImageProcessingOptions(rotationDegrees: 270),
        mirroredPreview: true,
      );

      final CameraOverlayTransform transform = CameraOverlayTransform.forFrame(
        frame,
        viewSize: const Size(20, 40),
      );

      expect(transform.uprightSize, const Size(2, 4));
      expect(transform.mirrored, isTrue);
      expect(transform.fit, BoxFit.cover);
      expect(transform.mapNormalized(0, 0), _closeToOffset(const Offset(20, 0)));
    });
  });
}

Matcher _closeToOffset(Offset expected) => predicate<Offset>(
  (Offset actual) => (actual - expected).distance < 1e-6,
  'is close to $expected',
);
