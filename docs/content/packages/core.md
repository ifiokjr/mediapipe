---
title: mp_core
description: Shared model, media, result, lifecycle, and platform primitives.
---

`mp_core` is the only dependency shared by all task packages. It contains no task-specific public API.

## Public type groups

| Area                         | Main types                                                                        |
| ---------------------------- | --------------------------------------------------------------------------------- |
| Models and execution         | `ModelAsset`, `BaseOptions`, `MpDelegate`, `LiteRtOptions`                        |
| Images                       | `MpImage`, `MpImageFormat`, `ImageProcessingOptions`, `NormalizedRect`            |
| Audio                        | `AudioData`, `AudioRunningMode`                                                   |
| Classification and detection | `Category`, `ClassificationResult`, `Detection`, `DetectionResult`, `BoundingBox` |
| Embeddings                   | `Embedding`, `EmbeddingResult`, `EmbedderOptions`                                 |
| Landmarks and masks          | `NormalizedLandmark`, `Landmark`, `MpImage`, `MpMatrix`                           |
| Lifecycle and errors         | `MpTask`, `TaskLifecycle`, `TimestampTracker`, `MpException`, `MpStatus`          |

Task package signatures refer to these types, but the task packages do not re-export them. Application code should depend on and import `mp_core` when constructing models or media inputs.

## Model sources

`ModelAsset.path`, `ModelAsset.bytes`, and `ModelAsset.uri` make ownership explicit. Byte models are defensively copied. URI models may carry a lowercase SHA-256 digest; the browser backend verifies that digest before passing bytes to MediaPipe.

## Immutable inputs

`MpImage` validates dimensions, sample storage, and tightly packed layout when it is constructed. It supports the pixel formats accepted by MediaPipe’s C image API. `AudioData` similarly validates channel count, sample rate, and interleaved samples.

Immutable input objects avoid a subtle class of use-after-return bugs in asynchronous camera and native calls. That safety requires a copy at the public boundary; integrations can use frame dropping to keep allocation bounded.

## Lifecycle and time

All tasks implement `MpTask`. Closing is idempotent, and using a closed task fails before crossing the platform boundary. `TimestampTracker` enforces the strict ordering required by video and live-stream tasks.

## Errors

Platform errors become `MpException` values with a stable `MpStatus`, task name, message, and optional cause. Native handles and upstream error strings are always released, including when conversion throws.
