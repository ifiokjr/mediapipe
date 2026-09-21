<!-- {=packageHeader:"mp_camera"} -->

# mp_camera

Camera frame conversion and scheduling for MP vision tasks in Flutter.

<!-- {/packageHeader} -->

`mp_camera` is the only package in the SDK that depends on `package:camera`.
Portable vision, text, audio, and GenAI packages remain usable from plain Dart.

## Features

- BGRA8888 to RGBA conversion for iOS camera frames
- NV21 and row/pixel-stride-aware YUV420 conversion for Android
- Sensor and device orientation compensation
- Explicit preview mirroring metadata
- A latest-frame scheduler with drop and failure telemetry

## Install

<!-- {=packageInstall:"mp_camera"} -->

Add the package:

```yaml
dependencies:
  mp_camera: ^0.1.0
```

`Camera frame conversion and scheduling for MP vision tasks in Flutter.`

<!-- {/packageInstall} -->

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

The example in [`example/`](example/) exercises conversion and scheduling with
synthetic frames, so it runs without a live camera.

## Failure contract

<!-- {=unsupportedContract} -->

Unsupported API and platform combinations fail explicitly with
`MpException(MpStatus.unimplemented, …)` rather than silently returning empty
results. Check `MpStatus` before treating a failure as a model or input problem.

<!-- {/unsupportedContract} -->

See the [camera guide]({{ links.docs }}packages/camera/).

<!-- {=packageFooter:"mp_camera"} -->

See the [mp_camera documentation](https://ifiokjr.github.io/mediapipe/packages/camera/) for
the full data contract and platform notes.

<!-- {/packageFooter} -->

<!-- {=independenceNotice} -->

MP is independent software. MediaPipe is a trademark of Google LLC; this
project is not affiliated with or endorsed by Google.

<!-- {/independenceNotice} -->
