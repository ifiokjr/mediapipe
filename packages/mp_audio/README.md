# mp_audio

Typed MediaPipe audio classification for independent clips and timestamped live
audio in Dart and Flutter.

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

See the [audio guide](https://ifiokjr.github.io/mediapipe/packages/audio/) for
running modes and the current platform contract.

MP is independent software and is not affiliated with or endorsed by Google.
