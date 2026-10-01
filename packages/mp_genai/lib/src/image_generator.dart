import 'package:meta/meta.dart';
import 'package:mp_core/mp_core.dart';

import 'runtime.dart';

/// Image-generation model families supported by MediaPipe's Android task.
enum ImageGeneratorModelType {
  /// Stable Diffusion 1.x converted to MediaPipe's model directory format.
  stableDiffusion1,
}

/// Control-image processors supported by the image generator.
enum ImageGeneratorConditionType {
  /// Derive a face landmark condition image.
  face,

  /// Derive a Canny edge condition image.
  edge,

  /// Derive a depth condition image.
  depth,
}

/// Face-condition model configuration.
@immutable
final class FaceConditionOptions {
  /// Creates face-condition options.
  FaceConditionOptions({
    required this.pluginModel,
    required this.faceModel,
    this.minFaceDetectionConfidence = 0.5,
    this.minFacePresenceConfidence = 0.5,
  }) {
    _checkConfidence(minFaceDetectionConfidence, 'minFaceDetectionConfidence');
    _checkConfidence(minFacePresenceConfidence, 'minFacePresenceConfidence');
  }

  /// ControlNet face plugin model.
  final BaseOptions pluginModel;

  /// Face landmarker model used to create the condition image.
  final BaseOptions faceModel;

  /// Minimum face detection confidence.
  final double minFaceDetectionConfidence;

  /// Minimum face presence confidence.
  final double minFacePresenceConfidence;
}

/// Canny-edge condition configuration.
@immutable
final class EdgeConditionOptions {
  /// Creates edge-condition options.
  EdgeConditionOptions({
    required this.pluginModel,
    this.threshold1 = 100,
    this.threshold2 = 200,
    this.apertureSize = 3,
    this.l2Gradient = false,
  }) {
    if (!threshold1.isFinite || threshold1 < 0) {
      throw ArgumentError.value(threshold1, 'threshold1', 'must be finite and non-negative');
    }
    if (!threshold2.isFinite || threshold2 < 0) {
      throw ArgumentError.value(threshold2, 'threshold2', 'must be finite and non-negative');
    }
    if (threshold2 < threshold1) {
      throw ArgumentError.value(threshold2, 'threshold2', 'must not be below threshold1');
    }
    if (apertureSize != 3 && apertureSize != 5 && apertureSize != 7) {
      throw ArgumentError.value(apertureSize, 'apertureSize', 'must be 3, 5, or 7');
    }
  }

  /// ControlNet edge plugin model.
  final BaseOptions pluginModel;

  /// Lower Canny hysteresis threshold.
  final double threshold1;

  /// Upper Canny hysteresis threshold.
  final double threshold2;

  /// Sobel aperture size.
  final int apertureSize;

  /// Whether to use the more accurate L2 gradient magnitude.
  final bool l2Gradient;
}

/// Depth-condition model configuration.
@immutable
final class DepthConditionOptions {
  /// Creates depth-condition options.
  const DepthConditionOptions({required this.pluginModel, required this.depthModel});

  /// ControlNet depth plugin model.
  final BaseOptions pluginModel;

  /// Depth estimation model used to create the condition image.
  final BaseOptions depthModel;
}

/// Optional control-image processors loaded with an [ImageGenerator].
@immutable
final class ImageGeneratorConditionOptions {
  /// Creates a set of condition processors.
  ImageGeneratorConditionOptions({this.face, this.edge, this.depth}) {
    if (face == null && edge == null && depth == null) {
      throw ArgumentError('At least one condition processor must be configured.');
    }
  }

  /// Face condition configuration.
  final FaceConditionOptions? face;

  /// Edge condition configuration.
  final EdgeConditionOptions? edge;

  /// Depth condition configuration.
  final DepthConditionOptions? depth;
}

/// Configuration for MediaPipe's Android image generator.
@immutable
final class ImageGeneratorOptions {
  /// Creates image-generator options.
  ImageGeneratorOptions({
    required this.modelDirectory,
    this.loraWeights,
    this.modelType = ImageGeneratorModelType.stableDiffusion1,
    this.conditions,
  }) {
    if (modelDirectory.trim().isEmpty) {
      throw ArgumentError.value(modelDirectory, 'modelDirectory', 'must not be empty');
    }
  }

  /// Directory containing the converted diffusion model files.
  final String modelDirectory;

  /// Optional LoRA weights file.
  final ModelAsset? loraWeights;

  /// Image-generation model family.
  final ImageGeneratorModelType modelType;

  /// Optional control-image processors.
  final ImageGeneratorConditionOptions? conditions;
}

/// An input image and the processor that should derive its condition map.
@immutable
final class ImageGeneratorCondition {
  /// Creates a generation condition.
  const ImageGeneratorCondition({required this.image, required this.type});

  /// Source image.
  final MpImage image;

  /// Condition processor.
  final ImageGeneratorConditionType type;
}

/// One image-generation result.
@immutable
final class ImageGeneratorResult {
  /// Creates an image-generation result.
  const ImageGeneratorResult({
    required this.generatedImage,
    required this.timestamp,
    this.conditionImage,
  });

  /// Generated sRGBA image.
  final MpImage generatedImage;

  /// Derived control image, when conditional generation was used.
  final MpImage? conditionImage;

  /// MediaPipe result timestamp.
  final Duration timestamp;
}

/// MediaPipe's experimental Android diffusion image generator.
final class ImageGenerator implements MpTask {
  ImageGenerator._(this.options, this._backend);

  /// Options used to create this generator.
  final ImageGeneratorOptions options;

  final ImageGeneratorBackend _backend;
  final TaskLifecycle _lifecycle = TaskLifecycle('ImageGenerator');

  /// Loads an image generator using [runtime], or the active platform adapter.
  static Future<ImageGenerator> create(
    ImageGeneratorOptions options, {
    GenAiRuntime? runtime,
  }) async => ImageGenerator._(
    options,
    await (runtime ?? defaultGenAiRuntime).createImageGenerator(options),
  );

  @override
  bool get isClosed => _lifecycle.isClosed;

  /// Generates an image in a single call.
  Future<ImageGeneratorResult> generate(
    String prompt, {
    required int iterations,
    required int seed,
    ImageGeneratorCondition? condition,
  }) {
    _lifecycle.ensureOpen();
    _validateGenerationInput(prompt, iterations);
    return _backend.generate(prompt, iterations: iterations, seed: seed, condition: condition);
  }

  /// Stores inputs for iterative calls to [execute].
  Future<void> setInputs(
    String prompt, {
    required int iterations,
    required int seed,
    ImageGeneratorCondition? condition,
  }) {
    _lifecycle.ensureOpen();
    _validateGenerationInput(prompt, iterations);
    return _backend.setInputs(prompt, iterations: iterations, seed: seed, condition: condition);
  }

  /// Executes the next iteration after [setInputs].
  Future<ImageGeneratorResult?> execute({bool showResult = true}) {
    _lifecycle.ensureOpen();
    return _backend.execute(showResult: showResult);
  }

  /// Creates a face, edge, or depth condition image without generating output.
  Future<MpImage> createConditionImage(MpImage image, ImageGeneratorConditionType type) {
    _lifecycle.ensureOpen();
    return _backend.createConditionImage(image, type);
  }

  @override
  Future<void> close() async {
    if (!_lifecycle.markClosed()) return;
    await _backend.close();
  }
}

void _validateGenerationInput(String prompt, int iterations) {
  if (prompt.trim().isEmpty) {
    throw ArgumentError.value(prompt, 'prompt', 'must not be empty');
  }
  if (iterations <= 0) {
    throw ArgumentError.value(iterations, 'iterations', 'must be positive');
  }
}

void _checkConfidence(double value, String name) {
  if (!value.isFinite || value < 0 || value > 1) {
    throw ArgumentError.value(value, name, 'must be finite and between 0 and 1');
  }
}
