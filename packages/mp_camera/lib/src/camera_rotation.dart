import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Resolves camera sensor and device orientation into MP image rotation.
///
/// Android camera buffers need device-orientation compensation. iOS camera
/// frames already carry the sensor orientation used by `package:camera`.
final class MpCameraRotation {
  const MpCameraRotation._();

  static const Map<DeviceOrientation, int> _deviceDegrees = <DeviceOrientation, int>{
    DeviceOrientation.portraitUp: 0,
    DeviceOrientation.landscapeLeft: 90,
    DeviceOrientation.portraitDown: 180,
    DeviceOrientation.landscapeRight: 270,
  };

  /// Returns the clockwise rotation required before inference.
  static int degrees(
    CameraDescription camera,
    DeviceOrientation orientation, {
    TargetPlatform? platform,
  }) {
    final TargetPlatform target = platform ?? defaultTargetPlatform;
    final int sensor = _normalize(camera.sensorOrientation);
    if (target != TargetPlatform.android) return sensor;

    final int device = _deviceDegrees[orientation]!;
    return switch (camera.lensDirection) {
      CameraLensDirection.front => _normalize(sensor + device),
      CameraLensDirection.back || CameraLensDirection.external => _normalize(sensor - device),
    };
  }

  /// Whether a camera preview is conventionally mirrored.
  static bool isPreviewMirrored(CameraDescription camera) =>
      camera.lensDirection == CameraLensDirection.front;

  static int _normalize(int value) => ((value % 360) + 360) % 360;
}
