---
title: Live streams
description: Keep camera and audio inference ordered, bounded, and current.
---

## Use a monotonic clock

Video and stream timestamps must increase. Wall clocks can jump and multiple frames can arrive in one millisecond. `MpCameraClock` uses elapsed time and advances equal readings, making it suitable for vision task timestamps.

## Bound the queue

Do not await every camera frame in an unbounded callback queue. If a model takes 45 ms and the camera produces a frame every 16 ms, old results become less useful with every callback. `LatestFrameScheduler` keeps the active frame and only the newest waiting frame.

Its `submittedCount`, `processedCount`, `droppedCount`, `staleCount`, and `failedCount` values expose queue behavior. Processing errors appear on `failures` without stopping subsequent frames. A consistently high drop ratio usually means the capture resolution, model, or delegate should change.

## Skip frames before converting them

A dropped frame still paid for its pixel conversion. When the camera runs at 30 or 60 frames per second and the model sustains far fewer, decide first: `FramePacer.targetFps(15)` admits one timestamp per interval, so a skipped callback costs nothing at all. Pass `maxQueueAge` to the scheduler as well when a long inference stall should discard the frame that waited through it rather than run it late; leave it unset for offline video, where every frame matters.

```dart
final pacer = FramePacer.targetFps(15);
final scheduler = LatestFrameScheduler<MpCameraFrame>(
  (frame) => landmarker.detectAsync(frame.image, frame.timestampMs),
  maxQueueAge: const Duration(milliseconds: 150),
);

void onCameraImage(CameraImage image) {
  final timestampMs = clock.nextTimestampMs();
  if (!pacer.admit(timestampMs)) return;
  scheduler.submit(MpCameraFrameConverter.convert(image, timestampMs: timestampMs, rotationDegrees: rotation));
}
```

## Watch the numbers

`scheduler.stats` returns a snapshot with the counters above plus `processedPerSecond`, the last and rolling p50/p95 queue wait, and processing time over a bounded window. A rising queue wait means frames arrive faster than inference runs; a rising processing time points at the model or delegate. Every processed frame is also wrapped in a `dart:developer` timeline task named `LatestFrameScheduler.process`, so DevTools shows where each frame's budget went. `LatencyWindow` is public for timing your own stages the same way.

## Respect platform semantics

- Vision and audio `results` streams are broadcast with no replay buffer. Subscribe before submitting the first frame or chunk; a result emitted with no listener attached is dropped. Processing failures are reported on the stream and on the future returned by the submitting call.
- Text, generative, and RAG streaming APIs buffer events until you subscribe, so a fast first chunk is never lost.
- Native and web vision currently serialize calls through their video APIs, then publish each copied result on `results`. There is no upstream callback path, so results arrive in order but not concurrently with a still-running inference.
- Native callback entry points remain disabled until the bridge can copy callback-owned memory safely from native worker threads. Until then, `liveStream` mode is a compatibility shim over the video API rather than true streaming inference.
- Web audio treats each chunk as an independent clip and adjusts its timestamp.
- Native audio stream mode remains unavailable until the callback-copy bridge is complete.

Compatibility adapters preserve ordering and shape, but they cannot create temporal state that the upstream runtime does not expose.

## Shut down in order

Stop the camera or microphone callback, close the frame scheduler so it drains retained work, cancel result subscriptions, and then close the task. This prevents a frame from arriving after its task handle has been released.
