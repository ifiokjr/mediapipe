---
title: Live streams
description: Keep camera and audio inference ordered, bounded, and current.
---

## Use a monotonic clock

Video and stream timestamps must increase. Wall clocks can jump and multiple frames can arrive in one millisecond. `MpCameraClock` uses elapsed time and advances equal readings, making it suitable for vision task timestamps.

## Bound the queue

Do not await every camera frame in an unbounded callback queue. If a model takes 45 ms and the camera produces a frame every 16 ms, old results become less useful with every callback. `LatestFrameScheduler` keeps the active frame and only the newest waiting frame.

Its `submittedCount`, `processedCount`, `droppedCount`, and `failedCount` values expose queue behavior. Processing errors appear on `failures` without stopping subsequent frames. A consistently high drop ratio usually means the capture resolution, model, or delegate should change.

## Respect platform semantics

- Vision and audio `results` streams are broadcast with no replay buffer. Subscribe before submitting the first frame or chunk; a result emitted with no listener attached is dropped.
- Native and web vision currently serialize calls through their video APIs, then publish each copied result on `results`. There is no upstream callback path, so results arrive in order but not concurrently with a still-running inference.
- Native callback entry points remain disabled until the bridge can copy callback-owned memory safely from native worker threads. Until then, `liveStream` mode is a compatibility shim over the video API rather than true streaming inference.
- Web audio treats each chunk as an independent clip and adjusts its timestamp.
- Native audio stream mode remains unavailable until the callback-copy bridge is complete.

Compatibility adapters preserve ordering and shape, but they cannot create temporal state that the upstream runtime does not expose.

## Shut down in order

Stop the camera or microphone callback, close the frame scheduler so it drains retained work, cancel result subscriptions, and then close the task. This prevents a frame from arriving after its task handle has been released.
