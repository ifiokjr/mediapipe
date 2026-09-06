---
title: mp_genai
description: LLM inference, function calling, retrieval-augmented generation, and image generation APIs.
---

`mp_genai` contains four independent task APIs. The application supplies every model file and owns every created task until `close()` completes.

| API               | Operations                                                                                                               | Backend         |
| ----------------- | ------------------------------------------------------------------------------------------------------------------------ | --------------- |
| `LlmInference`    | Token counting; stateful or stateless generation; streaming; cancellation; session cloning; text, image, and WAV input   | Android and web |
| `GenerativeModel` | Structured messages; typed function schemas; stateless generation; chat history, rewind, clone, and constrained decoding | Android         |
| `RagPipeline`     | Gecko or Gemma embeddings; in-memory or SQLite vectors; record, retrieve, generate, and stream                           | Android         |
| `ImageGenerator`  | Stable Diffusion 1; one-shot or iterative execution; face, edge, and depth conditions                                    | Android         |

## LLM inference

`LlmInference` owns the loaded model. `LlmSession` owns conversation state and sampling options. `generateResponse` creates and closes a temporary session; use `createSession` when a conversation must retain context.

```dart
final engine = await LlmInference.create(
  LlmInferenceOptions(
    baseOptions: BaseOptions(
      modelAsset: ModelAsset.path('models/gemma.task'),
    ),
    maxTokens: 1024,
    maxTopK: 40,
  ),
);

try {
  final session = await engine.createSession(
    options: LlmSessionOptions(
      topK: 20,
      temperature: 0.7,
      randomSeed: 7,
    ),
  );
  try {
    await session.addQueryChunk('Summarize the camera frame metadata.');
    final generation = await session.generate();
    await for (final chunk in generation.chunks) {
      print(chunk.text);
    }
    final response = await generation.response;
  } finally {
    await session.close();
  }
} finally {
  await engine.close();
}
```

`LlmGeneration.cancel()` requests cancellation. Completion remains observable through `response`. Image input accepts `MpImage`; audio input accepts non-empty mono WAV bytes. Both modalities require compatible model files and graph options.

The web adapter checks unsupported options before creating a task. For example, its current upstream runtime accepts `topP == 1`. Android accepts one candidate response per generation.

## Function calling

Function schemas and responses are JSON-compatible typed Dart values. A generated `FunctionCall` is untrusted model output. Validate its name, arguments, application permissions, and current state before running application code.

```dart
final lookupAction = FunctionDeclaration(
  name: 'lookup_action',
  description: 'Look up an action by its stable identifier.',
  parameters: FunctionSchema(
    type: FunctionSchemaType.object,
    properties: {
      'id': FunctionSchema(type: FunctionSchemaType.string),
    },
    requiredProperties: ['id'],
  ),
);

final model = await GenerativeModel.create(
  GenerativeModelOptions(
    inferenceOptions: llmOptions,
    formatter: FunctionCallingFormatter.gemma,
    tools: [FunctionTool([lookupAction])],
  ),
);

try {
  final response = await model.generateContent([
    GenAiContent.text(role: 'user', text: 'Check action act_123.'),
  ]);
  final calls = response.candidates
      .expand((candidate) => candidate.content.parts)
      .whereType<GenAiFunctionCallPart>();
  for (final part in calls) {
    validateAndDispatch(part.call);
  }
} finally {
  await model.close();
}
```

`startChat()` returns a `FunctionCallingChat`. It supports `sendMessage`, `sendText`, `history`, `last`, `rewind`, `clone`, `enableConstraint`, and `disableConstraint`. Closing a model also closes its Android chat handles.

## Retrieval-augmented generation

`RagPipeline` combines an embedder, semantic memory, retrieval settings, a prompt template, and an LLM. Use `InMemoryVectorStoreOptions` for process-local data or `SqliteVectorStoreOptions` for a persistent store.

```dart
final rag = await RagPipeline.create(
  RagPipelineOptions(
    embeddingModel: GeckoEmbeddingModelOptions(
      model: ModelAsset.path('models/gecko.tflite'),
      tokenizer: ModelAsset.path('models/sentencepiece.model'),
    ),
    vectorStore: const InMemoryVectorStoreOptions(),
    inferenceOptions: llmOptions,
    promptTemplate: 'Context: %s\nQuestion: %s',
  ),
);

try {
  await rag.record(
    RagDocument(
      text: 'Action act_123 requires a single unedited camera capture.',
      metadata: {'actionId': 'act_123'},
    ),
  );
  final matches = await rag.retrieve(
    'What evidence does act_123 require?',
    options: RagRetrievalOptions(topK: 3),
  );
  final response = await rag.generate('What evidence does act_123 require?');
} finally {
  await rag.close();
}
```

`RagGenerationChunk.text` is the partial text supplied by the upstream callback. Do not assume it is always a delta; concatenate or replace text according to the model backend you have qualified.

## Image generation

`ImageGeneratorOptions.modelDirectory` points to a converted Stable Diffusion 1 model directory. Optional condition processors require their own plugin and preprocessing models.

```dart
final generator = await ImageGenerator.create(
  ImageGeneratorOptions(modelDirectory: 'models/stable-diffusion'),
);

try {
  final result = await generator.generate(
    'A simple diagram of a camera verification pipeline',
    iterations: 20,
    seed: 42,
  );
  final MpImage image = result.generatedImage;
} finally {
  await generator.close();
}
```

For stepwise execution, call `setInputs` once and then `execute`. `execute(showResult: false)` may return `null`. `createConditionImage` runs a configured face, edge, or depth processor without generating an output image.

## Platform and model constraints

- The Android plugin compiles against pinned MediaPipe and Google AI Edge artifacts. Its LLM constructor is covered by a device test; successful model-backed qualification is pending.
- The web backend implements only `LlmInference` and loads the pinned official MediaPipe GenAI JavaScript package.
- iOS and desktop calls currently return `MpStatus.unimplemented`.
- MediaPipe deprecated its Android LLM Inference API in favor of LiteRT-LM.
- MediaPipe describes the Android image generator as experimental.
- Large model files should be stored outside the application bundle when platform limits require it. Verify downloaded model bytes before passing their local path to an API.

## Output handling

Generated text, function calls, and retrieved metadata are untrusted inputs. They may guide an on-device pre-check, but they must not directly authorize rewards, identity claims, access, or remote writes.
