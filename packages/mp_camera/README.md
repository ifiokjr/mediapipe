# mp_camera

Camera-frame conversion, orientation, and live-inference scheduling for MP
vision tasks in Flutter.

`mp_camera` is the only package in the SDK that depends on `package:camera`.
Portable vision, text, audio, and GenAI packages remain usable from plain Dart.

## Features

- BGRA8888 to RGBA conversion for iOS camera frames
- NV21 and row/pixel-stride-aware YUV420 conversion for Android
- Sensor and device orientation compensation
- Explicit preview mirroring metadata
- A latest-frame scheduler with drop and failure telemetry

## Usage

```dart
import 'package:camera/camera.dart';
import 'package:mp_camera/mp_camera.dart';

final clock = MpCameraClock();
final scheduler = LatestFrameScheduler<MpCameraFrame>((frame) async {
  await landmarker.detectAsync(
    frame.image,
    frame.timestampMs,
    processingOptions: frame.processingOptions,
  );
});

await controller.startImageStream((cameraImage) {
  final rotation = MpCameraRotation.degrees(
    controller.description,
    controller.value.deviceOrientation,
  );
  scheduler.submit(
    MpCameraFrameConverter.convert(
      cameraImage,
      timestampMs: clock.nextTimestampMs(),
      rotationDegrees: rotation,
      mirroredPreview: MpCameraRotation.isPreviewMirrored(controller.description),
    ),
  );
});
```

Listen to `scheduler.failures` in development and monitor `droppedCount` to
choose an appropriate camera resolution. A dropped queued frame is expected in
real-time inference; retaining stale frames is usually worse.

See the [camera guide](https://ifiokjr.github.io/mediapipe/packages/camera/).

MP is independent software and is not affiliated with or endorsed by Google.
