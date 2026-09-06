import 'dart:typed_data';

import 'package:mp_core/mp_core.dart';

import 'llm_inference.dart';
import 'options.dart';
import 'runtime_stub.dart' if (dart.library.js_interop) 'runtime_web.dart' as platform;

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

/// Platform adapter capable of loading MediaPipe generative AI engines.
abstract interface class GenAiRuntime {
  /// Creates an LLM inference backend.
  Future<LlmInferenceBackend> createLlmInference(LlmInferenceOptions options);
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
}
