# MP

Dart and Flutter bindings for MediaPipe Tasks.

Browser runtimes use Google's official Web packages. Native runtimes bind
directly to the MediaPipe Tasks C API and run task instances on dedicated Dart
isolates. Models are supplied by the application as bytes, a local path, or an
integrity-checked HTTPS URI.

> <!-- {=independenceNotice} -->

MP is independent software. MediaPipe is a trademark of Google LLC; this
project is not affiliated with or endorsed by Google.

<!-- {/independenceNotice} -->

## Packages

<!-- {=packageTable} -->

| Package                           | Purpose                                                                                                                        |
| --------------------------------- | ------------------------------------------------------------------------------------------------------------------------------ |
| [`mp_core`](packages/mp_core)     | Models, inputs, result containers, lifecycle, native assets, and web support                                                   |
| [`mp_vision`](packages/mp_vision) | The 11 vision tasks in the current MediaPipe Solutions guide, with image, video, and live-stream entry points where applicable |
| [`mp_camera`](packages/mp_camera) | Flutter camera conversion, orientation metadata, and latest-frame scheduling                                                   |
| [`mp_text`](packages/mp_text)     | Language detection, classification, embedding, proofreading, and summarization                                                 |
| [`mp_audio`](packages/mp_audio)   | Audio-clip and streaming classification                                                                                        |
| [`mp_genai`](packages/mp_genai)   | LLM inference, Android function calling, RAG, and image generation                                                             |

<!-- {/packageTable} -->

The six packages form one MonoChange release group and always share a version.

## Quick start

```dart
import 'package:mp_core/mp_core.dart';
import 'package:mp_text/mp_text.dart';

Future<void> main() async {
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
}
```

Read the [documentation]({{ links.docs }}) for platform setup, camera
streaming, model integrity, and the device-verification design.

## Working examples

The CLI examples each create a real task, run inference against a
digest-pinned public model, and close deterministically; the Flutter demo wires
the camera path end to end. The same entry points run in CI against the
built native runtime, so an example that stops working breaks the build.

| Example                                         | Demonstrates                                                                                   |
| ----------------------------------------------- | ---------------------------------------------------------------------------------------------- |
| `examples/cli/bin/core_model_assets.dart`       | Model assets, image and audio containers, and typed failures, runtime-free                     |
| `examples/cli/bin/vision_face_detection.dart`   | Face detection over a real photograph with boxes and keypoints                                 |
| `examples/cli/bin/vision_hand_landmarks.dart`   | Hand landmarks, handedness, and world coordinates                                              |
| `examples/cli/bin/text_language_detection.dart` | Language identification across four languages                                                  |
| `examples/cli/bin/text_tasks.dart`              | Language detection plus text embedding and cosine similarity                                   |
| `examples/cli/bin/audio_classification.dart`    | Clip classification and the native streaming contract                                          |
| `examples/cli/bin/genai_llm.dart`               | LLM session creation, streaming chunks, and cancellation                                       |
| `examples/device_demo`                          | A live camera app: conversion, monotonic timestamps, latest-frame scheduling, and rep counting |

Run one:

```sh
devenv shell native:build
dart run examples/cli/bin/vision_face_detection.dart
```

See the [examples page]({{ links.docs }}examples/) for the full list.

## API conventions

<!-- {=apiConventions} -->

- Immutable, strongly typed Dart inputs and outputs.
- Explicit task ownership through idempotent `close()` methods.
- Strictly increasing timestamps for video and stream APIs.
- Latest-frame backpressure for real-time camera pipelines.
- SHA-256 verification for remotely fetched model assets.
- Injectable runtimes and small fake backends for deterministic tests.
- No package-managed model downloads.

<!-- {/apiConventions} -->

## Lifecycle

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

## Current status

This repository is pre-release. Browser task adapters and the classic native C
surface are implemented and tested. Release artifacts, mobile packaging, and
device qualification remain gated until their platform-specific test lanes are
green. See the [support matrix]({{ links.docs }}platforms/) for the precise
contract.

<!-- {=supportDeclaration} -->

A platform is supported only when CI or a maintained device runs a real model,
resource cleanup is tested, its artifact is reproducible, and the limitation is
documented. Compilation alone is not enough.

<!-- {/supportDeclaration} -->

## Development

The repository uses a pinned Flutter SDK and `devenv`:

```sh
devenv shell install
devenv shell lint:all
devenv shell test:all
devenv shell package:check
```

Native bindings are generated from a pinned upstream MediaPipe release:

```sh
devenv shell -- dart run tool/generate_bindings.dart
devenv shell -- dart run tool/build_native.dart
```

Documentation is synchronized with `mdt`. Edit `.templates/template.t.md` and
run `devenv shell docs:update` to propagate a change to the root README, every
package README, and the docs site.

See [CONTRIBUTING.md](CONTRIBUTING.md) before opening a change. Every
releaseable pull request carries a MonoChange changeset, and all changes land
through pull requests.

## License

Apache-2.0. See [LICENSE](LICENSE) and [NOTICE](NOTICE).
