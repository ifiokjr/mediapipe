---
title: mp_vision
description: Vision task APIs, running modes, result types, and mask ownership.
---

## Tasks

- `FaceDetector`
- `FaceLandmarker`
- `GestureRecognizer`
- `HandLandmarker`
- `HolisticLandmarker`
- `ImageClassifier`
- `ImageEmbedder`
- `ImageSegmenter`
- `InteractiveSegmenter`
- `ObjectDetector`
- `PoseLandmarker`

Each task has task-specific options and result types. Classification, embedding, landmark, detection, mask, and matrix containers come from `mp_core` and are immutable.

## Running modes

Construct the task with exactly one `VisionRunningMode`. Calling an image method on a video task, reusing a timestamp, or submitting a frame after close fails immediately in Dart.

Live browser calls are serialized over the official video-mode APIs. Native live callbacks are used only when their result ownership can be copied safely before the callback returns.

## Segmentation masks

Native and web mask storage is copied into `MpImage` before the upstream result is closed. Keep mask output disabled when it is not needed; full-resolution floating-point masks can dominate result size.
