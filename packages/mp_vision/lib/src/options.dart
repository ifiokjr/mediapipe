import 'package:meta/meta.dart';
import 'package:mp_core/mp_core.dart';

void _validateProbability(double value, String name) {
  if (!value.isFinite || value < 0 || value > 1) {
    throw ArgumentError.value(value, name, 'must be finite and between 0 and 1');
  }
}

void _validateCount(int value, String name) {
  if (value <= 0) throw ArgumentError.value(value, name, 'must be greater than zero');
}

/// Options shared by every vision task.
@immutable
abstract base class VisionTaskOptions {
  /// Creates common vision task options.
  const VisionTaskOptions({required this.baseOptions, this.runningMode = VisionRunningMode.image});

  /// Model and hardware configuration.
  final BaseOptions baseOptions;

  /// Input scheduling mode.
  final VisionRunningMode runningMode;
}

/// Configuration for face detection.
final class FaceDetectorOptions extends VisionTaskOptions {
  /// Creates face detector options.
  FaceDetectorOptions({
    required super.baseOptions,
    super.runningMode,
    this.minDetectionConfidence = 0.5,
    this.minSuppressionThreshold = 0.3,
  }) {
    _validateProbability(minDetectionConfidence, 'minDetectionConfidence');
    _validateProbability(minSuppressionThreshold, 'minSuppressionThreshold');
  }

  /// Minimum accepted face detection confidence.
  final double minDetectionConfidence;

  /// Minimum overlap threshold used by non-maximum suppression.
  final double minSuppressionThreshold;
}

/// Configuration for face landmarking.
final class FaceLandmarkerOptions extends VisionTaskOptions {
  /// Creates face landmarker options.
  FaceLandmarkerOptions({
    required super.baseOptions,
    super.runningMode,
    this.numFaces = 1,
    this.minFaceDetectionConfidence = 0.5,
    this.minFacePresenceConfidence = 0.5,
    this.minTrackingConfidence = 0.5,
    this.outputFaceBlendshapes = false,
    this.outputFacialTransformationMatrixes = false,
  }) {
    _validateCount(numFaces, 'numFaces');
    _validateProbability(minFaceDetectionConfidence, 'minFaceDetectionConfidence');
    _validateProbability(minFacePresenceConfidence, 'minFacePresenceConfidence');
    _validateProbability(minTrackingConfidence, 'minTrackingConfidence');
  }

  /// Maximum number of faces to detect.
  final int numFaces;

  /// Minimum accepted face detection confidence.
  final double minFaceDetectionConfidence;

  /// Minimum accepted face-presence confidence.
  final double minFacePresenceConfidence;

  /// Minimum confidence required to continue tracking a face.
  final double minTrackingConfidence;

  /// Whether to return face blendshape classifications.
  final bool outputFaceBlendshapes;

  /// Whether to return facial transformation matrices.
  final bool outputFacialTransformationMatrixes;
}

/// Configuration shared by hand landmarking and gesture recognition.
abstract base class HandTaskOptions extends VisionTaskOptions {
  /// Creates hand task options.
  HandTaskOptions({
    required super.baseOptions,
    super.runningMode,
    this.numHands = 1,
    this.minHandDetectionConfidence = 0.5,
    this.minHandPresenceConfidence = 0.5,
    this.minTrackingConfidence = 0.5,
  }) {
    _validateCount(numHands, 'numHands');
    _validateProbability(minHandDetectionConfidence, 'minHandDetectionConfidence');
    _validateProbability(minHandPresenceConfidence, 'minHandPresenceConfidence');
    _validateProbability(minTrackingConfidence, 'minTrackingConfidence');
  }

  /// Maximum number of hands to detect.
  final int numHands;

  /// Minimum accepted hand detection confidence.
  final double minHandDetectionConfidence;

  /// Minimum accepted hand-presence confidence.
  final double minHandPresenceConfidence;

  /// Minimum confidence required to continue tracking a hand.
  final double minTrackingConfidence;
}

/// Configuration for gesture recognition.
final class GestureRecognizerOptions extends HandTaskOptions {
  /// Creates gesture recognizer options.
  GestureRecognizerOptions({
    required super.baseOptions,
    super.runningMode,
    super.numHands,
    super.minHandDetectionConfidence,
    super.minHandPresenceConfidence,
    super.minTrackingConfidence,
    this.cannedGesturesClassifierOptions,
    this.customGesturesClassifierOptions,
  });

  /// Filters applied to the model's built-in gesture classifier.
  final ClassifierOptions? cannedGesturesClassifierOptions;

  /// Filters applied to a custom gesture classifier in the task bundle.
  final ClassifierOptions? customGesturesClassifierOptions;
}

/// Configuration for hand landmarking.
final class HandLandmarkerOptions extends HandTaskOptions {
  /// Creates hand landmarker options.
  HandLandmarkerOptions({
    required super.baseOptions,
    super.runningMode,
    super.numHands,
    super.minHandDetectionConfidence,
    super.minHandPresenceConfidence,
    super.minTrackingConfidence,
  });
}

/// Configuration for holistic landmarking.
final class HolisticLandmarkerOptions extends VisionTaskOptions {
  /// Creates holistic landmarker options.
  HolisticLandmarkerOptions({
    required super.baseOptions,
    super.runningMode,
    this.minFaceDetectionConfidence = 0.5,
    this.minFaceSuppressionThreshold = 0.3,
    this.minFacePresenceConfidence = 0.5,
    this.outputFaceBlendshapes = false,
    this.minPoseDetectionConfidence = 0.5,
    this.minPoseSuppressionThreshold = 0.3,
    this.minPosePresenceConfidence = 0.5,
    this.outputPoseSegmentationMasks = false,
    this.minHandLandmarksConfidence = 0.5,
  }) {
    _validateProbability(minFaceDetectionConfidence, 'minFaceDetectionConfidence');
    _validateProbability(minFaceSuppressionThreshold, 'minFaceSuppressionThreshold');
    _validateProbability(minFacePresenceConfidence, 'minFacePresenceConfidence');
    _validateProbability(minPoseDetectionConfidence, 'minPoseDetectionConfidence');
    _validateProbability(minPoseSuppressionThreshold, 'minPoseSuppressionThreshold');
    _validateProbability(minPosePresenceConfidence, 'minPosePresenceConfidence');
    _validateProbability(minHandLandmarksConfidence, 'minHandLandmarksConfidence');
  }

  /// Minimum accepted face detection confidence.
  final double minFaceDetectionConfidence;

  /// Minimum face non-maximum-suppression threshold.
  final double minFaceSuppressionThreshold;

  /// Minimum accepted face-presence confidence.
  final double minFacePresenceConfidence;

  /// Whether to return face blendshapes.
  final bool outputFaceBlendshapes;

  /// Minimum accepted pose detection confidence.
  final double minPoseDetectionConfidence;

  /// Minimum pose non-maximum-suppression threshold.
  final double minPoseSuppressionThreshold;

  /// Minimum accepted pose-presence confidence.
  final double minPosePresenceConfidence;

  /// Whether to return pose segmentation masks.
  final bool outputPoseSegmentationMasks;

  /// Minimum accepted hand landmark confidence.
  final double minHandLandmarksConfidence;
}

/// Configuration for image classification.
final class ImageClassifierOptions extends VisionTaskOptions {
  /// Creates image classifier options.
  const ImageClassifierOptions({
    required super.baseOptions,
    super.runningMode,
    this.classifierOptions,
  });

  /// Optional result filtering configuration.
  final ClassifierOptions? classifierOptions;
}

/// Configuration for image embedding.
final class ImageEmbedderOptions extends VisionTaskOptions {
  /// Creates image embedder options.
  const ImageEmbedderOptions({
    required super.baseOptions,
    super.runningMode,
    this.embedderOptions = const EmbedderOptions(),
  });

  /// Embedding output configuration.
  final EmbedderOptions embedderOptions;
}

/// Configuration for image segmentation.
base class ImageSegmenterOptions extends VisionTaskOptions {
  /// Creates image segmenter options.
  ImageSegmenterOptions({
    required super.baseOptions,
    super.runningMode,
    this.displayNamesLocale,
    this.outputConfidenceMasks = true,
    this.outputCategoryMask = false,
  }) {
    if (!outputConfidenceMasks && !outputCategoryMask) {
      throw ArgumentError('At least one segmentation-mask output must be enabled.');
    }
  }

  /// Locale used for category display names in model metadata.
  final String? displayNamesLocale;

  /// Whether to return one confidence mask per category.
  final bool outputConfidenceMasks;

  /// Whether to return a category-index mask.
  final bool outputCategoryMask;
}

/// Configuration for interactive segmentation.
final class InteractiveSegmenterOptions extends ImageSegmenterOptions {
  /// Creates interactive segmenter options.
  InteractiveSegmenterOptions({
    required super.baseOptions,
    super.outputConfidenceMasks,
    super.outputCategoryMask,
  });
}

/// Configuration for object detection.
final class ObjectDetectorOptions extends VisionTaskOptions {
  /// Creates object detector options.
  const ObjectDetectorOptions({
    required super.baseOptions,
    super.runningMode,
    this.classifierOptions,
  });

  /// Optional result filtering configuration.
  final ClassifierOptions? classifierOptions;
}

/// Configuration for pose landmarking.
final class PoseLandmarkerOptions extends VisionTaskOptions {
  /// Creates pose landmarker options.
  PoseLandmarkerOptions({
    required super.baseOptions,
    super.runningMode,
    this.numPoses = 1,
    this.minPoseDetectionConfidence = 0.5,
    this.minPosePresenceConfidence = 0.5,
    this.minTrackingConfidence = 0.5,
    this.outputSegmentationMasks = false,
  }) {
    _validateCount(numPoses, 'numPoses');
    _validateProbability(minPoseDetectionConfidence, 'minPoseDetectionConfidence');
    _validateProbability(minPosePresenceConfidence, 'minPosePresenceConfidence');
    _validateProbability(minTrackingConfidence, 'minTrackingConfidence');
  }

  /// Maximum number of poses to detect.
  final int numPoses;

  /// Minimum accepted pose detection confidence.
  final double minPoseDetectionConfidence;

  /// Minimum accepted pose-presence confidence.
  final double minPosePresenceConfidence;

  /// Minimum confidence required to continue tracking a pose.
  final double minTrackingConfidence;

  /// Whether to return pose segmentation masks.
  final bool outputSegmentationMasks;
}
