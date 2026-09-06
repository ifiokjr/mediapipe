# mp_genai

Dart APIs for MediaPipe generative AI tasks.

## API surface

| API               | Purpose                                                                                             | Implemented backends |
| ----------------- | --------------------------------------------------------------------------------------------------- | -------------------- |
| `LlmInference`    | Stateful and stateless text generation, token counting, multimodal input, LoRA, and session cloning | Android, web         |
| `GenerativeModel` | Structured content and function-call generation with chat history and constraints                   | Android              |
| `RagPipeline`     | Gecko or Gemma embeddings, in-memory or SQLite retrieval, and LLM generation                        | Android              |
| `ImageGenerator`  | Stable Diffusion 1 generation and face, edge, or depth conditioning                                 | Android              |

Model files are supplied by the application and are not included in this
package.

## LLM example

```dart
import 'package:mp_core/mp_core.dart';
import 'package:mp_genai/mp_genai.dart';

final engine = await LlmInference.create(
  LlmInferenceOptions(
    baseOptions: BaseOptions(
      modelAsset: ModelAsset.path('models/gemma.task'),
    ),
    maxTokens: 1024,
  ),
);

try {
  final generation = await engine.generateResponse(
    'List three visible safety risks.',
  );
  await for (final chunk in generation.chunks) {
    print(chunk.text);
  }
  print(await generation.response);
} finally {
  await engine.close();
}
```

Every model, session, chat, pipeline, and generator owns platform resources.
Call `close()` when it is no longer needed. Unsupported API/platform
combinations throw an `MpException` with `MpStatus.unimplemented`.

## Current qualification

The web LLM adapter is implemented. The Android plugin and its four task
families compile in the example application; real-model Android tests are still
pending because the required model files are distributed separately. iOS,
macOS, Linux, and Windows have no `mp_genai` backend in this release.

MediaPipe's Android LLM Inference API is deprecated in favor of LiteRT-LM, and
the Android image generator is experimental. These upstream statuses are kept
out of the Dart type system but are relevant when choosing a backend.

See the [GenAI API guide](https://ifiokjr.github.io/mediapipe/packages/genai/)
and [platform matrix](https://ifiokjr.github.io/mediapipe/platforms/).

MP is independent software and is not affiliated with or endorsed by Google.
