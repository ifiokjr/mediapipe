import 'dart:typed_data';

import 'package:mp_core/mp_core.dart';

import 'function_calling.dart';
import 'image_generator.dart';
import 'llm_inference.dart';
import 'options.dart';
import 'rag.dart';
import 'runtime_stub.dart'
    if (dart.library.io) 'runtime_native.dart'
    if (dart.library.js_interop) 'runtime_web.dart'
    as platform;

/// Native or web engine implementation used by [LlmInference].
abstract interface class LlmInferenceBackend implements MpTask {
  /// Creates an empty stateful session.
  Future<LlmSessionBackend> createSession(LlmSessionOptions options);

  /// Counts model tokens without generating a response.
  Future<int> sizeInTokens(String text);
}

/// Native or web session implementation used by [LlmSession].
abstract interface class LlmSessionBackend implements MpTask {
  /// Appends text to the session context.
  Future<void> addQueryChunk(String text);

  /// Appends an image to the session context.
  Future<void> addImage(MpImage image);

  /// Appends mono WAV data to the session context.
  Future<void> addAudio(Uint8List wavBytes);

  /// Starts generation and returns a cancellable result.
  Future<LlmGeneration> generate();

  /// Counts model tokens without generating a response.
  Future<int> sizeInTokens(String text);

  /// Creates a session that shares this session's current context.
  Future<LlmSessionBackend> clone();

  /// Applies mutable sampling options to an existing session.
  Future<void> updateOptions(LlmSessionOptions options);
}

/// Native image-generation implementation used by [ImageGenerator].
abstract interface class ImageGeneratorBackend implements MpTask {
  /// Generates an image in one call.
  Future<ImageGeneratorResult> generate(
    String prompt, {
    required int iterations,
    required int seed,
    ImageGeneratorCondition? condition,
  });

  /// Stores inputs for incremental execution.
  Future<void> setInputs(
    String prompt, {
    required int iterations,
    required int seed,
    ImageGeneratorCondition? condition,
  });

  /// Executes one incremental generation step.
  Future<ImageGeneratorResult?> execute({required bool showResult});

  /// Creates a processed condition image.
  Future<MpImage> createConditionImage(MpImage image, ImageGeneratorConditionType type);
}

/// Native structured-generation implementation used by [GenerativeModel].
abstract interface class FunctionCallingBackend implements MpTask {
  /// Generates a response for a stateless content sequence.
  Future<GenerateContentResponse> generateContent(List<GenAiContent> contents);

  /// Starts a stateful chat session.
  Future<FunctionCallingChatBackend> startChat();
}

/// Native stateful-chat implementation used by [FunctionCallingChat].
abstract interface class FunctionCallingChatBackend implements MpTask {
  /// Sends one structured message.
  Future<GenerateContentResponse> sendMessage(GenAiContent content);

  /// Removes the most recent exchange.
  Future<ChatRewindResult> rewind();

  /// Returns conversation history.
  Future<List<GenAiContent>> history();

  /// Returns the latest content entry.
  Future<GenAiContent> last();

  /// Clones the current conversation.
  Future<FunctionCallingChatBackend> clone();

  /// Enables constrained decoding.
  Future<void> enableConstraint(FunctionCallingConstraint constraint);

  /// Disables constrained decoding.
  Future<void> disableConstraint();
}

/// Native retrieval-augmented generation implementation used by [RagPipeline].
abstract interface class RagPipelineBackend implements MpTask {
  /// Records one semantic-memory document.
  Future<bool> record(RagDocument document);

  /// Records a document batch.
  Future<bool> recordAll(List<RagDocument> documents);

  /// Retrieves semantically similar documents.
  Future<List<RagRetrievalEntity>> retrieve(String query, RagRetrievalOptions options);

  /// Retrieves context and generates a complete response.
  Future<String> generate(String query, RagRetrievalOptions options);

  /// Retrieves context and streams a response.
  Stream<RagGenerationChunk> generateStreaming(String query, RagRetrievalOptions options);
}

/// Platform adapter capable of loading MediaPipe generative AI engines.
abstract interface class GenAiRuntime {
  /// Creates an LLM inference backend.
  Future<LlmInferenceBackend> createLlmInference(LlmInferenceOptions options);

  /// Creates an image-generator backend.
  Future<ImageGeneratorBackend> createImageGenerator(ImageGeneratorOptions options);

  /// Creates a structured generation and function-calling backend.
  Future<FunctionCallingBackend> createGenerativeModel(GenerativeModelOptions options);

  /// Creates a retrieval-augmented generation backend.
  Future<RagPipelineBackend> createRagPipeline(RagPipelineOptions options);
}

/// The adapter selected for the active platform.
GenAiRuntime get defaultGenAiRuntime => platform.createGenAiRuntime();

/// An adapter used when the current build has no linked MediaPipe runtime.
final class UnsupportedGenAiRuntime implements GenAiRuntime {
  /// Creates an unsupported adapter for [platform].
  const UnsupportedGenAiRuntime(this.platform);

  /// The platform for which no implementation was linked.
  final MpPlatform platform;

  @override
  Future<LlmInferenceBackend> createLlmInference(LlmInferenceOptions options) async =>
      throw MpException(
        MpStatus.unimplemented,
        'No LlmInference backend is linked for ${platform.name}.',
        task: 'LlmInference',
      );

  @override
  Future<ImageGeneratorBackend> createImageGenerator(ImageGeneratorOptions options) async =>
      throw MpException(
        MpStatus.unimplemented,
        'No ImageGenerator backend is linked for ${platform.name}.',
        task: 'ImageGenerator',
      );

  @override
  Future<FunctionCallingBackend> createGenerativeModel(GenerativeModelOptions options) async =>
      throw MpException(
        MpStatus.unimplemented,
        'No GenerativeModel backend is linked for ${platform.name}.',
        task: 'GenerativeModel',
      );

  @override
  Future<RagPipelineBackend> createRagPipeline(RagPipelineOptions options) async =>
      throw MpException(
        MpStatus.unimplemented,
        'No RagPipeline backend is linked for ${platform.name}.',
        task: 'RagPipeline',
      );
}
