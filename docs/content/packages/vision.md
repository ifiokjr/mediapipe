---
title: mp_vision
description: Vision task APIs, running modes, result types, and mask ownership.
---

## Task API

| Task                   | Image method | Video method        | Live method      | Result                     |
| ---------------------- | ------------ | ------------------- | ---------------- | -------------------------- |
| `FaceDetector`         | `detect`     | `detectForVideo`    | `detectAsync`    | `DetectionResult`          |
| `FaceLandmarker`       | `detect`     | `detectForVideo`    | `detectAsync`    | `FaceLandmarkerResult`     |
| `GestureRecognizer`    | `recognize`  | `recognizeForVideo` | `recognizeAsync` | `GestureRecognizerResult`  |
| `HandLandmarker`       | `detect`     | `detectForVideo`    | `detectAsync`    | `HandLandmarkerResult`     |
| `HolisticLandmarker`   | `detect`     | `detectForVideo`    | `detectAsync`    | `HolisticLandmarkerResult` |
| `ImageClassifier`      | `classify`   | `classifyForVideo`  | `classifyAsync`  | `ClassificationResult`     |
| `ImageEmbedder`        | `embed`      | `embedForVideo`     | `embedAsync`     | `EmbeddingResult`          |
| `ImageSegmenter`       | `segment`    | `segmentForVideo`   | `segmentAsync`   | `ImageSegmenterResult`     |
| `InteractiveSegmenter` | `segment`    | —                   | —                | `ImageSegmenterResult`     |
| `ObjectDetector`       | `detect`     | `detectForVideo`    | `detectAsync`    | `DetectionResult`          |
| `PoseLandmarker`       | `detect`     | `detectForVideo`    | `detectAsync`    | `PoseLandmarkerResult`     |

Every task is created with `TaskName.create(TaskNameOptions(...))` and closed with `close()`. Classification, embedding, landmark, detection, mask, and matrix containers come from `mp_core` and are immutable. Live results are read from the task's `results` stream as `VisionLiveResult<T>` values.

## Option groups

All option classes require `BaseOptions` and, except for `InteractiveSegmenterOptions`, accept a `VisionRunningMode`. Detector and landmarker options expose task-specific confidence thresholds and result counts. Classifier-based tasks use `ClassifierOptions`; embedders use `EmbedderOptions`.

Mask and optional-output switches are disabled or conservative by default:

- `FaceLandmarkerOptions` can return blendshapes and facial transformation matrices.
- `HolisticLandmarkerOptions` can return face blendshapes and pose segmentation masks.
- `PoseLandmarkerOptions` can return pose segmentation masks.
- `ImageSegmenterOptions` returns confidence masks by default and can return a category mask.

`ImageProcessingOptions` supplies a clockwise rotation in multiples of 90 degrees and an optional normalized region of interest for one call. Task construction options remain unchanged between calls.

## Running modes

Construct the task with exactly one `VisionRunningMode`. Calling an image method on a video task, reusing a timestamp, or submitting a frame after close fails immediately in Dart.

The web and current native adapters serialize live-stream submissions over the upstream video APIs, then emit copied results in timestamp order. Native C callbacks remain disabled until the bridge can copy callback-owned memory safely from native worker threads.

## Segmentation masks

Native and web mask storage is copied into `MpImage` before the upstream result is closed. Keep mask output disabled when it is not needed; full-resolution floating-point masks can dominate result size.
