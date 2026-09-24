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

Each package ships a runnable example that creates a real task, runs inference,
and closes it deterministically. The same entry points are compiled in CI for
the browser and executed on device, so an example that stops compiling breaks
the build.

| Example                      | Demonstrates                                                                |
| ---------------------------- | --------------------------------------------------------------------------- |
| `packages/mp_core/example`   | Model assets, image containers, and lifecycle without a runtime             |
| `packages/mp_vision/example` | Face detection and image classification on a bundled sample image           |
| `packages/mp_text/example`   | A Flutter app that detects language, classifies, and embeds text            |
| `packages/mp_audio/example`  | Audio classification over a synthesized clip and a timestamped frame stream |
| `packages/mp_genai/example`  | LLM session creation, streaming chunks, and cancellation                    |
| `packages/mp_camera/example` | Camera frame conversion and latest-frame scheduling without a live camera   |

Run an example directly:

```sh
cd packages/mp_text/example
repo-flutter run
```

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
