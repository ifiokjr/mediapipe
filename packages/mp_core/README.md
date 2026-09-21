<!-- {=packageHeader:"mp_core"} -->

# mp_core

Shared types, model configuration, and runtime primitives for MP tasks.

<!-- {/packageHeader} -->

Use `mp_core` directly when building a custom task adapter, or transitively
through `mp_vision`, `mp_text`, `mp_audio`, or `mp_genai`.

## What it provides

<!-- {=packageTasks:"mp_core"} -->

- Model assets, image and audio containers, result types, errors, and task lifecycle

<!-- {/packageTasks} -->

- Immutable image, audio, landmark, classification, detection, embedding, and
  segmentation containers.
- Models loaded from bytes, local paths, or absolute URIs.
- Optional SHA-256 verification for remotely loaded models.
- CPU, GPU, Edge TPU NNAPI, and LiteRT delegate configuration.
- Task lifecycle, status errors, timestamp validation, and injectable runtimes.
- Generated FFI bindings for the public MediaPipe Tasks C headers.
- Shared browser module and model-asset helpers.

## Model assets

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

Combine a model with a delegate:

```dart
final options = BaseOptions(modelAsset: local, delegate: MpDelegate.cpu);
```

## Ownership

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

## Failure contract

<!-- {=unsupportedContract} -->

Unsupported API and platform combinations fail explicitly with
`MpException(MpStatus.unimplemented, …)` rather than silently returning empty
results. Check `MpStatus` before treating a failure as a model or input problem.

<!-- {/unsupportedContract} -->

## Where to go next

<!-- {=docsLinks} -->

- [Package and API documentation](https://ifiokjr.github.io/mediapipe/)
- [Platform support matrix](https://ifiokjr.github.io/mediapipe/platforms/)
- [Guides](https://ifiokjr.github.io/mediapipe/guides/models/)
- [Examples](https://github.com/ifiokjr/mediapipe/tree/main/examples)

<!-- {/docsLinks} -->

<!-- {=independenceNotice} -->

MP is independent software. MediaPipe is a trademark of Google LLC; this
project is not affiliated with or endorsed by Google.

<!-- {/independenceNotice} -->
