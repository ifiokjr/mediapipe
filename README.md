# MP

Dart and Flutter bindings for MediaPipe Tasks.

Browser runtimes use Google's official Web packages. Native runtimes bind
directly to the MediaPipe Tasks C API and run task instances on dedicated Dart
isolates. Models are supplied by the application as bytes, a local path, or an
integrity-checked HTTPS URI.

> MP is independent software. MediaPipe is a trademark of Google LLC; this
> project is not affiliated with or endorsed by Google.

## Packages

| Package                           | Purpose                                                                                                                        |
| --------------------------------- | ------------------------------------------------------------------------------------------------------------------------------ |
| [`mp_core`](packages/mp_core)     | Models, inputs, result containers, lifecycle, native assets, and web support                                                   |
| [`mp_vision`](packages/mp_vision) | The 11 vision tasks in the current MediaPipe Solutions guide, with image, video, and live-stream entry points where applicable |
| [`mp_camera`](packages/mp_camera) | Flutter camera conversion, orientation metadata, and latest-frame scheduling                                                   |
| [`mp_text`](packages/mp_text)     | Language detection, classification, embedding, proofreading, and summarization                                                 |
| [`mp_audio`](packages/mp_audio)   | Audio-clip and streaming classification                                                                                        |
| [`mp_genai`](packages/mp_genai)   | LLM inference, Android function calling, RAG, and image generation                                                             |

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

Read the [documentation](https://ifiokjr.github.io/mediapipe/) for platform
setup, camera streaming, model integrity, and the device-verification design.

## API conventions

- Immutable, strongly typed Dart inputs and outputs.
- Explicit task ownership through idempotent `close()` methods.
- Strictly increasing timestamps for video and stream APIs.
- Latest-frame backpressure for real-time camera pipelines.
- SHA-256 verification for remotely fetched model assets.
- Injectable runtimes and small fake backends for deterministic tests.
- No package-managed model downloads.

## Current status

This repository is pre-release. Browser task adapters and the classic native C
surface are implemented and tested. Release artifacts, mobile packaging, and
device qualification remain gated until their platform-specific test lanes are
green. See the [support matrix](https://ifiokjr.github.io/mediapipe/platforms/)
for the precise contract; unsupported combinations fail explicitly.

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

See [CONTRIBUTING.md](CONTRIBUTING.md) before opening a change. Every
releaseable pull request carries a MonoChange changeset, and all changes land
through pull requests.

## License

Apache-2.0. See [LICENSE](LICENSE) and [NOTICE](NOTICE).
