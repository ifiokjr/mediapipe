# mp_text

MediaPipe text task APIs for Dart and Flutter.

## Tasks

- `LanguageDetector`
- `TextClassifier`
- `TextEmbedder`
- `TextProofreader`
- `TextSummarizer`

Each task owns its native or browser handle, accepts an injectable runtime for
tests, and returns immutable results.

The first three tasks have C and browser backends. MediaPipe exposes
proofreading and summarization on Android and iOS; those plugin bridges compile
and launch on both platforms, while model-backed device tests are still
pending. Other targets return `MpStatus.unimplemented` for those two tasks.

## Usage

```dart
import 'package:mp_core/mp_core.dart';
import 'package:mp_text/mp_text.dart';

final detector = await LanguageDetector.create(
  LanguageDetectorOptions(
    baseOptions: BaseOptions(
      modelAsset: ModelAsset.path('models/language_detector.tflite'),
    ),
  ),
);

try {
  final result = await detector.detect('Bonjour tout le monde');
  final language = result.topPrediction;
  print('${language?.languageCode}: ${language?.probability}');
} finally {
  await detector.close();
}
```

On the web, import `package:mp_text/mp_text_web.dart` when configuring a custom
CDN or self-hosted MediaPipe module location. Native models may come from a
path, bytes, or an integrity-checked HTTPS URI.

See the [text guide](https://ifiokjr.github.io/mediapipe/packages/text/) and
[model guidance](https://ifiokjr.github.io/mediapipe/guides/models/).

MP is independent software and is not affiliated with or endorsed by Google.
