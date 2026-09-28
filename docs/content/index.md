---
title: Overview
description: Packages, public APIs, runtime backends, and current platform support.
---

> <!-- {=independenceNotice} -->

MP is independent software. MediaPipe is a trademark of Google LLC; this
project is not affiliated with or endorsed by Google.

<!-- {/independenceNotice} -->

## Package layout

The workspace contains six public packages. Depend on the package for the task family you use; it brings in `mp_core` transitively. `mp_camera` is optional and only applies to Flutter applications using `package:camera`.

<PackageGrid/>

<!-- {=packageTableDocs} -->

| Package                        | Purpose                                                                                                                        |
| ------------------------------ | ------------------------------------------------------------------------------------------------------------------------------ |
| [`mp_core`](packages/core)     | Models, inputs, result containers, lifecycle, native assets, and web support                                                   |
| [`mp_vision`](packages/vision) | The 11 vision tasks in the current MediaPipe Solutions guide, with image, video, and live-stream entry points where applicable |
| [`mp_camera`](packages/camera) | Flutter camera conversion, orientation metadata, and latest-frame scheduling                                                   |
| [`mp_text`](packages/text)     | Language detection, classification, embedding, proofreading, and summarization                                                 |
| [`mp_audio`](packages/audio)   | Audio-clip and streaming classification                                                                                        |
| [`mp_genai`](packages/genai)   | LLM inference, Android function calling, RAG, and image generation                                                             |

<!-- {/packageTableDocs} -->

## Common API shape

Task constructors take task-specific options containing `BaseOptions`. Calls accept typed input and return immutable results. A task owns native or JavaScript resources until `close()` completes.

```dart
final detector = await LanguageDetector.create(
  LanguageDetectorOptions(
    baseOptions: BaseOptions(
      modelAsset: ModelAsset.path('models/language_detector.tflite'),
    ),
  ),
);

try {
  final result = await detector.detect('Bonjour tout le monde');
  print(result.topPrediction?.languageCode);
} finally {
  await detector.close();
}
```

Task constructors accept an optional runtime, so unit tests can inject a fake without loading a model or native library. Video and live-stream methods validate monotonically increasing timestamps before invoking the platform runtime.

## Task surface

The classic task packages expose the public MediaPipe Tasks families available through the upstream C and web SDKs:

<!-- {=taskSurfaceTable} -->

| Package     | Tasks                                                                                                                                                                |
| ----------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `mp_vision` | Image classification and embedding, object and face detection, image and interactive segmentation, gesture recognition, and hand, pose, face, and holistic landmarks |
| `mp_text`   | Language detection, text classification, text embedding, text proofreading, text summarization                                                                       |
| `mp_audio`  | Audio classification for clips and timestamped frames                                                                                                                |
| `mp_genai`  | LLM sessions and streaming; Android function calling, RAG, and diffusion image generation                                                                            |

<!-- {/taskSurfaceTable} -->

## Runtime boundaries

Browser adapters use pinned official JavaScript packages. Classic native tasks use generated FFI bindings to MediaPipe's aggregate C library. GenAI uses separate backends because it is not part of that C target. The [platform matrix](platforms) distinguishes implemented adapters from tested and released support.

On-device results can provide pre-submission guidance, but they are not proof. For reward, access, or identity decisions, preserve the original evidence and authorize on a secured service.

See the [quickstart](quickstart) for package installation and task lifecycle.
