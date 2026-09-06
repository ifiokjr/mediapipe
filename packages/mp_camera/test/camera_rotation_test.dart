import 'package:camera/camera.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mp_camera/mp_camera.dart';

void main() {
  group('MpCameraRotation', () {
    const CameraDescription back = CameraDescription(
      name: 'back',
      lensDirection: CameraLensDirection.back,
      sensorOrientation: 90,
    );
    const CameraDescription front = CameraDescription(
      name: 'front',
      lensDirection: CameraLensDirection.front,
      sensorOrientation: 270,
    );

    test('compensates Android back cameras against device orientation', () {
      expect(
        MpCameraRotation.degrees(
          back,
          DeviceOrientation.landscapeLeft,
          platform: TargetPlatform.android,
        ),
        0,
      );
      expect(
        MpCameraRotation.degrees(
          back,
          DeviceOrientation.landscapeRight,
          platform: TargetPlatform.android,
        ),
        180,
      );
    });

    test('compensates Android front cameras in the opposite direction', () {
      expect(
        MpCameraRotation.degrees(
          front,
          DeviceOrientation.landscapeLeft,
          platform: TargetPlatform.android,
        ),
        0,
      );
      expect(
        MpCameraRotation.degrees(
          front,
          DeviceOrientation.landscapeRight,
          platform: TargetPlatform.android,
        ),
        180,
      );
    });

    test('uses sensor orientation on non-Android platforms', () {
      expect(
        MpCameraRotation.degrees(
          back,
          DeviceOrientation.portraitDown,
          platform: TargetPlatform.iOS,
        ),
        90,
      );
    });

    test('only front-camera previews are mirrored', () {
      expect(MpCameraRotation.isPreviewMirrored(front), isTrue);
      expect(MpCameraRotation.isPreviewMirrored(back), isFalse);
    });
  });
}
