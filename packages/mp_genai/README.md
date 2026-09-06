# mp_genai

MediaPipe LLM session and generation APIs for Dart and Flutter.

## APIs

- Reusable inference engines and stateful sessions
- Incremental text generation with cancellation
- Session cloning and mutable sampling options
- Image and mono-WAV prompt inputs on supported models
- LoRA adapters and prompt templates
- Token counting and explicit model limits

## Usage

```dart
import 'package:mp_core/mp_core.dart';
import 'package:mp_genai/mp_genai.dart';

final engine = await LlmInference.create(
  LlmInferenceOptions(
    baseOptions: BaseOptions(modelAsset: ModelAsset.path('models/gemma.task')),
    maxTokens: 1024,
  ),
);

try {
  final generation = await engine.generateResponse('Name three visible safety risks.');
  await for (final chunk in generation.chunks) {
    print(chunk.text);
  }
  print(await generation.response);
} finally {
  await engine.close();
}
```

MediaPipe's Android LLM Inference API is deprecated in favor of LiteRT-LM. MP
keeps backend-specific types out of the public Dart API. Check the support
matrix before selecting a target platform.

See the [GenAI guide](https://ifiokjr.github.io/mediapipe/packages/genai/).

MP is independent software and is not affiliated with or endorsed by Google.
