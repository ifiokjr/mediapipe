import 'package:meta/meta.dart';
import 'package:mp_core/mp_core.dart';

/// Preferred execution backend for LLM inference.
enum LlmBackend {
  /// Let the runtime choose the model's default backend.
  defaultBackend,

  /// Execute on the CPU.
  cpu,

  /// Execute on the GPU.
  gpu,
}

/// Vision encoder and adapter assets for a multimodal model.
@immutable
final class VisionModelOptions {
  /// Creates vision modality options.
  const VisionModelOptions({this.encoder, this.adapter});

  /// Optional vision encoder model.
  final ModelAsset? encoder;

  /// Optional projection adapter model.
  final ModelAsset? adapter;
}

/// Audio encoder configuration for a multimodal model.
@immutable
final class AudioModelOptions {
  /// Creates audio modality options.
  AudioModelOptions({required this.maxAudioSequenceLength}) {
    if (maxAudioSequenceLength <= 0) {
      throw ArgumentError.value(
        maxAudioSequenceLength,
        'maxAudioSequenceLength',
        'must be greater than zero',
      );
    }
  }

  /// Maximum sequence length accepted by the audio encoder.
  final int maxAudioSequenceLength;
}

/// Engine-wide LLM inference configuration.
@immutable
final class LlmInferenceOptions {
  /// Creates LLM inference options.
  LlmInferenceOptions({
    required this.baseOptions,
    this.maxTokens = 512,
    this.maxTopK = 40,
    this.maxNumImages = 0,
    this.supportAudio = false,
    Iterable<int> supportedLoraRanks = const <int>[],
    this.preferredBackend = LlmBackend.defaultBackend,
    this.visionModelOptions,
    this.audioModelOptions,
    this.forceF32 = false,
    this.disableRewinding = false,
  }) : supportedLoraRanks = List<int>.unmodifiable(supportedLoraRanks) {
    if (maxTokens <= 0) throw ArgumentError.value(maxTokens, 'maxTokens', 'must be positive');
    if (maxTopK <= 0) throw ArgumentError.value(maxTopK, 'maxTopK', 'must be positive');
    if (maxNumImages < 0) {
      throw ArgumentError.value(maxNumImages, 'maxNumImages', 'must not be negative');
    }
    if (this.supportedLoraRanks.any((int rank) => rank <= 0)) {
      throw ArgumentError.value(
        this.supportedLoraRanks,
        'supportedLoraRanks',
        'must contain only positive ranks',
      );
    }
    if (maxNumImages > 0 && visionModelOptions == null) {
      throw ArgumentError.value(maxNumImages, 'maxNumImages', 'requires visionModelOptions');
    }
    if (supportAudio && audioModelOptions == null) {
      throw ArgumentError.value(supportAudio, 'supportAudio', 'requires audioModelOptions');
    }
  }

  /// Model and hardware configuration.
  final BaseOptions baseOptions;

  /// Maximum combined input and output token count.
  final int maxTokens;

  /// Largest top-k sampling value sessions may request.
  final int maxTopK;

  /// Maximum images accepted by a request.
  final int maxNumImages;

  /// Whether audio prompts are enabled.
  final bool supportAudio;

  /// LoRA ranks preallocated by the engine.
  final List<int> supportedLoraRanks;

  /// Preferred execution backend.
  final LlmBackend preferredBackend;

  /// Vision modality configuration.
  final VisionModelOptions? visionModelOptions;

  /// Audio modality configuration.
  final AudioModelOptions? audioModelOptions;

  /// Whether web inference should force 32-bit floating-point precision.
  final bool forceF32;

  /// Whether memory-saving mode should disable fast context rewinding.
  final bool disableRewinding;
}

/// Prompt wrappers applied by models with role-specific chat templates.
@immutable
final class PromptTemplates {
  /// Creates prompt templates.
  const PromptTemplates({
    this.userPrefix = '',
    this.userSuffix = '',
    this.modelPrefix = '',
    this.modelSuffix = '',
    this.systemPrefix = '',
    this.systemSuffix = '',
  });

  /// Prefix inserted before user content.
  final String userPrefix;

  /// Suffix inserted after user content.
  final String userSuffix;

  /// Prefix inserted before model content.
  final String modelPrefix;

  /// Suffix inserted after model content.
  final String modelSuffix;

  /// Prefix inserted before system content.
  final String systemPrefix;

  /// Suffix inserted after system content.
  final String systemSuffix;
}

/// Optional graph features for a session.
@immutable
final class LlmGraphOptions {
  /// Creates graph options.
  const LlmGraphOptions({
    this.includeTokenCostCalculator = true,
    this.enableVisionModality = false,
    this.enableAudioModality = false,
  });

  /// Whether token counting should be included in the graph.
  final bool includeTokenCostCalculator;

  /// Whether vision inputs are enabled.
  final bool enableVisionModality;

  /// Whether audio inputs are enabled.
  final bool enableAudioModality;
}

/// Sampling and graph configuration for one stateful LLM session.
@immutable
final class LlmSessionOptions {
  /// Creates session options.
  LlmSessionOptions({
    this.topK = 40,
    this.topP = 1,
    this.temperature = 0.8,
    this.randomSeed = 0,
    this.loraAsset,
    this.graphOptions,
    this.constraintHandle,
    this.promptTemplates,
    this.numResponses = 1,
  }) {
    if (topK <= 0) throw ArgumentError.value(topK, 'topK', 'must be positive');
    if (!topP.isFinite || topP <= 0 || topP > 1) {
      throw ArgumentError.value(topP, 'topP', 'must be finite and in the range (0, 1]');
    }
    if (!temperature.isFinite || temperature < 0) {
      throw ArgumentError.value(temperature, 'temperature', 'must be finite and non-negative');
    }
    if (constraintHandle != null && constraintHandle! <= 0) {
      throw ArgumentError.value(constraintHandle, 'constraintHandle', 'must be positive');
    }
    if (numResponses <= 0) {
      throw ArgumentError.value(numResponses, 'numResponses', 'must be positive');
    }
  }

  /// Number of highest-probability tokens considered at each step.
  final int topK;

  /// Cumulative probability used by nucleus sampling.
  final double topP;

  /// Logit sampling temperature.
  final double temperature;

  /// Deterministic random seed.
  final int randomSeed;

  /// Optional LoRA model asset.
  final ModelAsset? loraAsset;

  /// Optional graph features.
  final LlmGraphOptions? graphOptions;

  /// Optional native constrained-decoding handle.
  final int? constraintHandle;

  /// Optional role-specific prompt wrappers.
  final PromptTemplates? promptTemplates;

  /// Number of candidate responses requested on supported runtimes.
  final int numResponses;
}
