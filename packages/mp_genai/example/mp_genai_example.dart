import 'package:mp_core/mp_core.dart';
import 'package:mp_genai/mp_genai.dart';

/// A tour of the generative surface: engine and session options, prompt
/// templates, function-calling declarations, and chunk values.
///
/// Each snippet is a runnable check. For a session that streams chunks and
/// demonstrates cancellation against a real on-device model, run:
///
/// ```sh
/// MP_LLM_MODEL=models/gemma-2b-it-cpu-int4.bin \
///   dart run examples/cli/bin/genai_llm.dart
/// ```
void main() {
  // Engine options bound the session budget; an empty prompt budget or a
  // sampling ceiling of zero is rejected at construction.
  final LlmInferenceOptions engine = LlmInferenceOptions(
    baseOptions: BaseOptions(modelAsset: ModelAsset.path('model.task')),
  );
  assert(engine.maxTokens == 512);
  assert(
    _throwsArgumentError(
      () => LlmInferenceOptions(
        baseOptions: BaseOptions(modelAsset: ModelAsset.path('model.task')),
        maxTokens: 0,
      ),
    ),
  );

  // A session may not sample beyond the engine's top-K ceiling, and mutable
  // session options are adjusted with `LlmSession.updateOptions` after
  // creation — the LoRA asset itself is fixed for the session's lifetime.
  final LlmSessionOptions session = LlmSessionOptions(topK: 20, temperature: 0.4);
  assert(session.topK == 20 && session.temperature == 0.4);

  // Prompt templates prepend and append scaffolding around each turn without
  // touching the model weights.
  const PromptTemplates templates = PromptTemplates(userSuffix: '<end_of_turn>');
  assert(templates.userSuffix == '<end_of_turn>');

  // Function-calling tools declare a JSON schema; argument payloads must be
  // JSON values, so a Dart object is rejected up front.
  final FunctionTool weather = FunctionTool(<FunctionDeclaration>[
    FunctionDeclaration(
      name: 'lookup_weather',
      description: 'Report the weather for a place.',
      parameters: FunctionSchema(
        type: FunctionSchemaType.object,
        properties: <String, FunctionSchema>{
          'place': FunctionSchema(type: FunctionSchemaType.string),
        },
        requiredProperties: const <String>['place'],
      ),
    ),
  ]);
  assert(weather.declarations.single.name == 'lookup_weather');

  // Streamed chunks are value types, so progress handling can compare them
  // directly by content.
  const LlmGenerationChunk chunk = LlmGenerationChunk(text: 'Hi', isDone: false);
  assert(chunk == const LlmGenerationChunk(text: 'Hi', isDone: false));
  assert(chunk != const LlmGenerationChunk(text: 'Hi', isDone: true));
}

bool _throwsArgumentError(void Function() body) {
  try {
    body();
    return false;
  } on ArgumentError {
    return true;
  }
}
