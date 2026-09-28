<!-- {=packageHeader:"mp_audio"} -->

# mp_audio

Cross-platform MediaPipe audio tasks for Dart and Flutter.

<!-- {/packageHeader} -->

Typed audio classification for independent clips and timestamped live audio.

## Install

<!-- {=packageInstall:"mp_audio"} -->

Add the package:

```yaml
dependencies:
  { { name } }: ^0.1.0
```

`Cross-platform MediaPipe audio tasks for Dart and Flutter.`

<!-- {/packageInstall} -->

## Usage

```dart
import 'dart:typed_data';

import 'package:mp_audio/mp_audio.dart';
import 'package:mp_core/mp_core.dart';

final classifier = await AudioClassifier.create(
  AudioClassifierOptions(
    baseOptions: BaseOptions(
      modelAsset: ModelAsset.path('models/audio_classifier.tflite'),
    ),
  ),
);

try {
  final audio = AudioData(
    samples: Float32List.fromList(monoSamples),
    sampleRateHz: 16000,
    channelCount: 1,
  );
  final result = await classifier.classify(audio);
  print(result.classifications.first.classifications.first.categories.first);
} finally {
  await classifier.close();
}
```

Streaming mode uses strictly increasing millisecond timestamps and exposes
results as a Dart stream. The runtime copies caller-owned sample buffers before
crossing a native or browser boundary.

The example in [`example/`](example/) classifies a synthesized clip and a
timestamped frame sequence, so it runs without microphone hardware.

## Current platform contract

Native audio supports clips only; stream mode returns `MpStatus.unimplemented`
until the callback-copy bridge lands. The browser adapter classifies each chunk
as an independent clip and adjusts its timestamp.

## Failure contract

<!-- {=unsupportedContract} -->

Unsupported API and platform combinations fail explicitly with
`MpException(MpStatus.unimplemented, …)` rather than silently returning empty
results. Check `MpStatus` before treating a failure as a model or input problem.

<!-- {/unsupportedContract} -->

See the [audio guide]({{ links.docs }}packages/audio/) for running modes and
the current platform contract.

<!-- {=packageFooter:"mp_audio"} -->

See the [mp_audio documentation](https://ifiokjr.github.io/mediapipe/packages/audio/) for
the full data contract and platform notes.

<!-- {/packageFooter} -->

<!-- {=independenceNotice} -->

MP is independent software. MediaPipe is a trademark of Google LLC; this
project is not affiliated with or endorsed by Google.

<!-- {/independenceNotice} -->
