<!-- {=packageHeader:"mp_text"} -->

# mp_text

Cross-platform MediaPipe text tasks for Dart and Flutter.

<!-- {/packageHeader} -->

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

## Install

<!-- {=packageInstall:"mp_text"} -->

Add the package:

```yaml
dependencies:
  { { name } }: ^0.1.0
```

`Cross-platform MediaPipe text tasks for Dart and Flutter.`

<!-- {/packageInstall} -->

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

The Flutter example in [`example/`](example/) detects language, classifies, and
embeds text against a model you supply.

## Failure contract

<!-- {=unsupportedContract} -->

Unsupported API and platform combinations fail explicitly with
`MpException(MpStatus.unimplemented, …)` rather than silently returning empty
results. Check `MpStatus` before treating a failure as a model or input problem.

<!-- {/unsupportedContract} -->

See the [text guide]({{ links.docs }}packages/text/) and
[model guidance]({{ links.docs }}guides/models/).

<!-- {=packageFooter:"mp_text"} -->

See the [mp_text documentation](https://ifiokjr.github.io/mediapipe/packages/text/) for
the full data contract and platform notes.

<!-- {/packageFooter} -->

<!-- {=independenceNotice} -->

MP is independent software. MediaPipe is a trademark of Google LLC; this
project is not affiliated with or endorsed by Google.

<!-- {/independenceNotice} -->
