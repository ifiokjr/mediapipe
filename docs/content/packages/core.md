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

<!-- {=modelContract} -->

Models are application data, not SDK configuration. Supply one as bytes, a local
path, or an absolute HTTPS URI, and pin remote models with a SHA-256 digest:

```dart
final local = ModelAsset.path('models/gesture_recognizer.task');
final memory = ModelAsset.bytes(Uint8List.fromList(modelBytes));
final remote = ModelAsset.uri(
  Uri.parse('https://cdn.example.com/models/gesture_recognizer.task'),
  sha256: '0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef',
);
```

The SDK never chooses or downloads a model without an explicit `ModelAsset`.
Publish immutable, versioned model URLs and always provide a digest for
production clients.

<!-- {/modelContract} -->

## Immutable inputs

`MpImage` validates dimensions, sample storage, and tightly packed layout when it is constructed. It supports the pixel formats accepted by MediaPipe’s C image API. `AudioData` similarly validates channel count, sample rate, and interleaved samples.

Immutable input objects avoid a subtle class of use-after-return bugs in asynchronous camera and native calls. That safety requires a copy at the public boundary; integrations can use frame dropping to keep allocation bounded.

## Lifecycle and time

All tasks implement `MpTask`. Closing is idempotent, and using a closed task fails before crossing the platform boundary. `TimestampTracker` enforces the strict ordering required by video and live-stream tasks.

<!-- {=lifecycleContract} -->

Every created task implements `MpTask`. Call `close()` when inference is no
longer needed. Closing twice is safe, and invoking a closed task fails
immediately with `MpTaskClosedError`.

```dart
final detector = await ObjectDetector.create(options);
try {
  final result = await detector.detect(image);
  // Use the result.
} finally {
  await detector.close();
}
```

Long-lived tasks belong near the owning feature boundary, not inside a
per-frame callback. A task serializes its native calls, so handles are never
entered concurrently.

<!-- {/lifecycleContract} -->

## Errors

Platform errors become `MpException` values with a stable `MpStatus`, task name, message, and optional cause. Native handles and upstream error strings are always released, including when conversion throws.

<!-- {=unsupportedContract} -->

Unsupported API and platform combinations fail explicitly with
`MpException(MpStatus.unimplemented, …)` rather than silently returning empty
results. Check `MpStatus` before treating a failure as a model or input problem.

<!-- {/unsupportedContract} -->

## Design conventions

These rules hold across every task package:

<!-- {=apiConventions} -->

- Immutable, strongly typed Dart inputs and outputs.
- Explicit task ownership through idempotent `close()` methods.
- Strictly increasing timestamps for video and stream APIs.
- Latest-frame backpressure for real-time camera pipelines.
- SHA-256 verification for remotely fetched model assets.
- Injectable runtimes and small fake backends for deterministic tests.
- No package-managed model downloads.

<!-- {/apiConventions} -->
