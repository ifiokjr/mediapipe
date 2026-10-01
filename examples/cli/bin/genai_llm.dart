// Run with: dart run examples/bin/genai_llm.dart
//
// Constructs an `LlmInference` engine, opens a session, and streams a response.
//
// GenAI needs a large model file that MediaPipe distributes separately, so this
// example requires `MP_LLM_MODEL` to point at one. Without it the example
// explains the requirement and prints the platform contract instead of failing,
// which keeps it runnable in CI and on every developer machine.
//
//   MP_LLM_MODEL=models/gemma-2b-it-cpu-int4.bin \
//     dart run examples/bin/genai_llm.dart

import 'dart:io';

import 'package:mp_core/mp_core.dart';
import 'package:mp_genai/mp_genai.dart';

Future<void> main() async {
  final String? modelPath = Platform.environment['MP_LLM_MODEL'];
  if (modelPath == null || modelPath.isEmpty) {
    _printContract();
    return;
  }
  final File model = File(modelPath);
  if (!model.existsSync()) {
    stderr.writeln('MP_LLM_MODEL points at a missing file: ${model.path}');
    exitCode = 1;
    return;
  }

  final LlmInference engine = await LlmInference.create(
    LlmInferenceOptions(
      baseOptions: BaseOptions(modelAsset: ModelAsset.path(model.path)),
      maxTokens: 1024,
    ),
  );

  try {
    stdout.writeln('== Stateless generation ==');
    final LlmGeneration generation = await engine.generateResponse(
      'Name three on-device machine learning tradeoffs in one sentence each.',
    );
    await for (final LlmGenerationChunk chunk in generation.chunks) {
      stdout.write(chunk.text);
      if (chunk.isDone) break;
    }
    // `response` must be consumed: it also closes the temporary session.
    stdout.writeln('\ncomplete: ${(await generation.response).length} characters');

    stdout.writeln('\n== Stateful session ==');
    final LlmSession session = await engine.createSession();
    try {
      await session.addQueryChunk('Remember the number 42.');
      final LlmGeneration first = await session.generate();
      await first.response;
      // The session keeps context across turns, so the follow-up can refer back.
      await session.addQueryChunk('What number did I ask you to remember?');
      final LlmGeneration second = await session.generate();
      stdout.writeln('follow-up: ${await second.response}');
    } finally {
      await session.close();
    }
  } on MpException catch (error) {
    stderr.writeln('Generation failed: $error');
    exitCode = 1;
  } finally {
    await engine.close();
  }
}

void _printContract() {
  stdout.writeln('''
MP_LLM_MODEL is not set, so no model was loaded.

GenAI is the one task family that MediaPipe does not ship inside its aggregate C
library, so `mp_genai` uses dedicated backends:

  - Android: a MethodChannel plugin over the MediaPipe Java GenAI APIs. This
    covers LLM inference, function calling, RAG, and image generation.
  - Web: the official `@mediapipe/tasks-genai` bundle, limited to LLM
    inference.
  - iOS, macOS, Linux, Windows: no upstream backend, so calls fail with
    MpStatus.unimplemented.

Supply a model to run the full example:

  MP_LLM_MODEL=models/gemma-2b-it-cpu-int4.bin dart run examples/bin/genai_llm.dart
''');
}
