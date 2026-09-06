---
title: mp_camera
description: A small, explicit bridge from package:camera frames to MP vision inputs.
---

`mp_camera` is the Flutter-specific seam inspired by lessons from the community Google ML Kit plugins. It keeps camera acquisition separate from model inference while standardizing the difficult parts: pixel formats, row strides, rotation metadata, timestamps, and backpressure.

## Convert a frame

Configure `package:camera` to request `ImageFormatGroup.nv21` on Android and `ImageFormatGroup.bgra8888` on iOS. Some camera implementations still return three-plane YUV420; the converter handles its independent row and pixel strides.

```dart
final clock = MpCameraClock();

void onCameraImage(CameraImage image) {
  final rotation = MpCameraRotation.degrees(
    camera.description,
    camera.value.deviceOrientation,
  );
  final frame = MpCameraFrameConverter.convert(
    image,
    timestampMs: clock.nextTimestampMs(),
    rotationDegrees: rotation,
    mirroredPreview: MpCameraRotation.isPreviewMirrored(camera.description),
  );
  scheduler.submit(frame);
}
```

The conversion produces tightly packed RGB or RGBA bytes. `mirroredPreview` describes presentation only: inference receives the unmirrored sensor image.

## Keep results fresh

Camera callbacks frequently arrive faster than inference. `LatestFrameScheduler` processes one frame and retains at most the newest waiting frame. Older waiting frames are dropped and counted, preventing an unbounded queue of large buffers.

```dart
final scheduler = LatestFrameScheduler<MpCameraFrame>((frame) async {
  await landmarker.detectAsync(
    frame.image,
    frame.timestampMs,
    processingOptions: frame.processingOptions,
  );
});
```

Processing errors are published on `scheduler.failures` and increment `failedCount`; a failed callback does not stop later frames. The package does not own `CameraController`, render a preview, or request permissions.
