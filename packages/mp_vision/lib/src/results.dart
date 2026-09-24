import 'dart:typed_data';

import 'package:collection/collection.dart';
import 'package:meta/meta.dart';
import 'package:mp_core/mp_core.dart';

const DeepCollectionEquality _deepEquality = DeepCollectionEquality();

List<List<T>> _immutableNested<T>(Iterable<Iterable<T>> values) =>
    List<List<T>>.unmodifiable(values.map(List<T>.unmodifiable));

/// Landmarks, handedness, and recognized gestures for detected hands.
@immutable
final class GestureRecognizerResult {
  /// Creates an immutable gesture recognition result.
  GestureRecognizerResult({
    required Iterable<Iterable<Category>> gestures,
    required Iterable<Iterable<Category>> handedness,
    required Iterable<Iterable<NormalizedLandmark>> landmarks,
    required Iterable<Iterable<Landmark>> worldLandmarks,
  }) : gestures = _immutableNested(gestures),
       handedness = _immutableNested(handedness),
       landmarks = _immutableNested(landmarks),
       worldLandmarks = _immutableNested(worldLandmarks);

  /// Recognized gestures for each hand.
  final List<List<Category>> gestures;

  /// Handedness classifications for each hand.
  final List<List<Category>> handedness;

  /// Hand landmarks in normalized image coordinates.
  final List<List<NormalizedLandmark>> landmarks;

  /// Hand landmarks in world coordinates.
  final List<List<Landmark>> worldLandmarks;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is GestureRecognizerResult &&
          _deepEquality.equals(gestures, other.gestures) &&
          _deepEquality.equals(handedness, other.handedness) &&
          _deepEquality.equals(landmarks, other.landmarks) &&
          _deepEquality.equals(worldLandmarks, other.worldLandmarks);

  @override
  int get hashCode => Object.hash(
    _deepEquality.hash(gestures),
    _deepEquality.hash(handedness),
    _deepEquality.hash(landmarks),
    _deepEquality.hash(worldLandmarks),
  );
}

/// Landmarks and handedness for detected hands.
@immutable
final class HandLandmarkerResult {
  /// Creates an immutable hand landmark result.
  HandLandmarkerResult({
    required Iterable<Iterable<Category>> handedness,
    required Iterable<Iterable<NormalizedLandmark>> landmarks,
    required Iterable<Iterable<Landmark>> worldLandmarks,
  }) : handedness = _immutableNested(handedness),
       landmarks = _immutableNested(landmarks),
       worldLandmarks = _immutableNested(worldLandmarks);

  /// Handedness classifications for each hand.
  final List<List<Category>> handedness;

  /// Hand landmarks in normalized image coordinates.
  final List<List<NormalizedLandmark>> landmarks;

  /// Hand landmarks in world coordinates.
  final List<List<Landmark>> worldLandmarks;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is HandLandmarkerResult &&
          _deepEquality.equals(handedness, other.handedness) &&
          _deepEquality.equals(landmarks, other.landmarks) &&
          _deepEquality.equals(worldLandmarks, other.worldLandmarks);

  @override
  int get hashCode => Object.hash(
    _deepEquality.hash(handedness),
    _deepEquality.hash(landmarks),
    _deepEquality.hash(worldLandmarks),
  );
}

/// Landmarks, blendshapes, and transforms for detected faces.
@immutable
final class FaceLandmarkerResult {
  /// Creates an immutable face landmark result.
  FaceLandmarkerResult({
    required Iterable<Iterable<NormalizedLandmark>> faceLandmarks,
    Iterable<Classifications> faceBlendshapes = const <Classifications>[],
    Iterable<MpMatrix> facialTransformationMatrixes = const <MpMatrix>[],
  }) : faceLandmarks = _immutableNested(faceLandmarks),
       faceBlendshapes = List<Classifications>.unmodifiable(faceBlendshapes),
       facialTransformationMatrixes = List<MpMatrix>.unmodifiable(facialTransformationMatrixes);

  /// Detected landmarks for each face.
  final List<List<NormalizedLandmark>> faceLandmarks;

  /// Optional blendshape classifications for each face.
  final List<Classifications> faceBlendshapes;

  /// Optional canonical-to-detected-face transformation matrices.
  final List<MpMatrix> facialTransformationMatrixes;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is FaceLandmarkerResult &&
          _deepEquality.equals(faceLandmarks, other.faceLandmarks) &&
          _deepEquality.equals(faceBlendshapes, other.faceBlendshapes) &&
          _deepEquality.equals(facialTransformationMatrixes, other.facialTransformationMatrixes);

  @override
  int get hashCode => Object.hash(
    _deepEquality.hash(faceLandmarks),
    _deepEquality.hash(faceBlendshapes),
    _deepEquality.hash(facialTransformationMatrixes),
  );
}

/// Pose, face, and hand landmarks returned together by holistic landmarking.
@immutable
final class HolisticLandmarkerResult {
  /// Creates an immutable holistic landmark result.
  HolisticLandmarkerResult({
    required Iterable<Iterable<NormalizedLandmark>> faceLandmarks,
    required Iterable<Iterable<NormalizedLandmark>> poseLandmarks,
    required Iterable<Iterable<Landmark>> poseWorldLandmarks,
    required Iterable<Iterable<NormalizedLandmark>> leftHandLandmarks,
    required Iterable<Iterable<Landmark>> leftHandWorldLandmarks,
    required Iterable<Iterable<NormalizedLandmark>> rightHandLandmarks,
    required Iterable<Iterable<Landmark>> rightHandWorldLandmarks,
    Iterable<Classifications> faceBlendshapes = const <Classifications>[],
    Iterable<MpImage> poseSegmentationMasks = const <MpImage>[],
  }) : faceLandmarks = _immutableNested(faceLandmarks),
       poseLandmarks = _immutableNested(poseLandmarks),
       poseWorldLandmarks = _immutableNested(poseWorldLandmarks),
       leftHandLandmarks = _immutableNested(leftHandLandmarks),
       leftHandWorldLandmarks = _immutableNested(leftHandWorldLandmarks),
       rightHandLandmarks = _immutableNested(rightHandLandmarks),
       rightHandWorldLandmarks = _immutableNested(rightHandWorldLandmarks),
       faceBlendshapes = List<Classifications>.unmodifiable(faceBlendshapes),
       poseSegmentationMasks = List<MpImage>.unmodifiable(poseSegmentationMasks);

  /// Detected face landmarks.
  final List<List<NormalizedLandmark>> faceLandmarks;

  /// Optional face blendshape classifications.
  final List<Classifications> faceBlendshapes;

  /// Detected pose landmarks in image coordinates.
  final List<List<NormalizedLandmark>> poseLandmarks;

  /// Detected pose landmarks in world coordinates.
  final List<List<Landmark>> poseWorldLandmarks;

  /// Optional pose segmentation masks.
  final List<MpImage> poseSegmentationMasks;

  /// Detected left-hand landmarks in image coordinates.
  final List<List<NormalizedLandmark>> leftHandLandmarks;

  /// Detected left-hand landmarks in world coordinates.
  final List<List<Landmark>> leftHandWorldLandmarks;

  /// Detected right-hand landmarks in image coordinates.
  final List<List<NormalizedLandmark>> rightHandLandmarks;

  /// Detected right-hand landmarks in world coordinates.
  final List<List<Landmark>> rightHandWorldLandmarks;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is HolisticLandmarkerResult &&
          _deepEquality.equals(faceLandmarks, other.faceLandmarks) &&
          _deepEquality.equals(poseLandmarks, other.poseLandmarks) &&
          _deepEquality.equals(poseWorldLandmarks, other.poseWorldLandmarks) &&
          _deepEquality.equals(leftHandLandmarks, other.leftHandLandmarks) &&
          _deepEquality.equals(leftHandWorldLandmarks, other.leftHandWorldLandmarks) &&
          _deepEquality.equals(rightHandLandmarks, other.rightHandLandmarks) &&
          _deepEquality.equals(rightHandWorldLandmarks, other.rightHandWorldLandmarks) &&
          _deepEquality.equals(faceBlendshapes, other.faceBlendshapes) &&
          _deepEquality.equals(poseSegmentationMasks, other.poseSegmentationMasks);

  @override
  int get hashCode => Object.hash(
    _deepEquality.hash(faceLandmarks),
    _deepEquality.hash(poseLandmarks),
    _deepEquality.hash(poseWorldLandmarks),
    _deepEquality.hash(leftHandLandmarks),
    _deepEquality.hash(leftHandWorldLandmarks),
    _deepEquality.hash(rightHandLandmarks),
    _deepEquality.hash(rightHandWorldLandmarks),
    _deepEquality.hash(faceBlendshapes),
    _deepEquality.hash(poseSegmentationMasks),
  );
}

/// Pose landmarks and optional segmentation masks.
@immutable
final class PoseLandmarkerResult {
  /// Creates an immutable pose landmark result.
  PoseLandmarkerResult({
    required Iterable<Iterable<NormalizedLandmark>> landmarks,
    required Iterable<Iterable<Landmark>> worldLandmarks,
    Iterable<MpImage> segmentationMasks = const <MpImage>[],
  }) : landmarks = _immutableNested(landmarks),
       worldLandmarks = _immutableNested(worldLandmarks),
       segmentationMasks = List<MpImage>.unmodifiable(segmentationMasks);

  /// Pose landmarks in normalized image coordinates.
  final List<List<NormalizedLandmark>> landmarks;

  /// Pose landmarks in world coordinates.
  final List<List<Landmark>> worldLandmarks;

  /// Optional masks for detected poses.
  final List<MpImage> segmentationMasks;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is PoseLandmarkerResult &&
          _deepEquality.equals(landmarks, other.landmarks) &&
          _deepEquality.equals(worldLandmarks, other.worldLandmarks) &&
          _deepEquality.equals(segmentationMasks, other.segmentationMasks);

  @override
  int get hashCode => Object.hash(
    _deepEquality.hash(landmarks),
    _deepEquality.hash(worldLandmarks),
    _deepEquality.hash(segmentationMasks),
  );
}

/// Category and confidence masks returned by a segmentation task.
@immutable
final class ImageSegmenterResult {
  /// Creates an immutable segmentation result.
  ImageSegmenterResult({
    this.categoryMask,
    Iterable<MpImage> confidenceMasks = const <MpImage>[],
    Float32List? qualityScores,
  }) : confidenceMasks = List<MpImage>.unmodifiable(confidenceMasks),
       qualityScores = qualityScores == null ? null : Float32List.fromList(qualityScores);

  /// Category index for each pixel, when requested.
  final MpImage? categoryMask;

  /// Confidence for each category and pixel, when requested.
  final List<MpImage> confidenceMasks;

  /// Quality score for each output head, ordered by head index.
  ///
  /// Index `i` scores the output of head `i`, so the list aligns positionally
  /// with the model's output heads rather than with `confidenceMasks` entries
  /// from other heads. `null` means the model reports no quality scores.
  final Float32List? qualityScores;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ImageSegmenterResult &&
          categoryMask == other.categoryMask &&
          const ListEquality<MpImage>().equals(confidenceMasks, other.confidenceMasks) &&
          const Float32ListEquality().equals(qualityScores, other.qualityScores);

  @override
  int get hashCode => Object.hash(
    categoryMask,
    const ListEquality<MpImage>().hash(confidenceMasks),
    const Float32ListEquality().hash(qualityScores),
  );
}

/// Compares the contents of two `Float32List` values, treating `null` as equal
/// only to `null`.
@immutable
final class Float32ListEquality implements Equality<Float32List?> {
  /// Creates the constant list equality.
  const Float32ListEquality();

  @override
  bool equals(Float32List? first, Float32List? second) {
    if (first == null || second == null) return identical(first, second);
    if (first.length != second.length) return false;
    for (var i = 0; i < first.length; i++) {
      if (first[i] != second[i]) return false;
    }
    return true;
  }

  @override
  int hash(Float32List? list) {
    if (list == null) return 0;
    int result = list.length;
    for (final double value in list.take(8)) {
      result = Object.hash(result, value);
    }
    return result;
  }

  @override
  bool isValidKey(Object? object) => object == null || object is Float32List;
}

/// Polarity of a user-drawn interactive-segmentation stroke.
enum BrushMode {
  /// Include the region touched by the stroke.
  positive,

  /// Exclude the region touched by the stroke.
  negative,

  /// Select the region enclosed by the stroke.
  lasso,
}

/// A normalized point used as an interactive segmentation prompt.
@immutable
final class PromptPoint {
  /// Creates a normalized point.
  PromptPoint(this.x, this.y) {
    if (x < 0 || x > 1) throw ArgumentError.value(x, 'x', 'must be between 0 and 1');
    if (y < 0 || y > 1) throw ArgumentError.value(y, 'y', 'must be between 0 and 1');
  }

  /// Horizontal coordinate in the range 0–1.
  final double x;

  /// Vertical coordinate in the range 0–1.
  final double y;

  @override
  bool operator ==(Object other) =>
      identical(this, other) || other is PromptPoint && x == other.x && y == other.y;

  @override
  int get hashCode => Object.hash(x, y);
}

/// A single interactive-segmentation brush stroke.
@immutable
final class PromptStroke {
  /// Creates an immutable brush stroke.
  PromptStroke({
    required this.brushMode,
    required Iterable<PromptPoint> points,
    this.isCompleted = true,
  }) : points = List<PromptPoint>.unmodifiable(points) {
    if (this.points.isEmpty) throw ArgumentError.value(points, 'points', 'must not be empty');
  }

  /// Whether the stroke includes, excludes, or encloses a region.
  final BrushMode brushMode;

  /// Normalized points forming the stroke.
  final List<PromptPoint> points;

  /// Whether the user has finished drawing the stroke.
  final bool isCompleted;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is PromptStroke &&
          brushMode == other.brushMode &&
          const ListEquality<PromptPoint>().equals(points, other.points) &&
          isCompleted == other.isCompleted;

  @override
  int get hashCode =>
      Object.hash(brushMode, const ListEquality<PromptPoint>().hash(points), isCompleted);
}

/// User guidance supplied to an interactive segmenter.
@immutable
sealed class InteractivePrompt {
  const InteractivePrompt._();

  /// Uses one positive point as the foreground prompt.
  factory InteractivePrompt.keypoint(PromptPoint point) = KeypointPrompt;

  /// Uses a legacy foreground scribble.
  factory InteractivePrompt.scribble(Iterable<PromptPoint> points) = ScribblePrompt;

  /// Uses signed brush strokes supported by the current web task.
  factory InteractivePrompt.strokes(Iterable<PromptStroke> strokes) = StrokePrompt;
}

/// A single-point interactive segmentation prompt.
final class KeypointPrompt extends InteractivePrompt {
  /// Creates a keypoint prompt.
  const KeypointPrompt(this.point) : super._();

  /// Foreground point.
  final PromptPoint point;
}

/// A legacy scribble interactive segmentation prompt.
final class ScribblePrompt extends InteractivePrompt {
  /// Creates an immutable scribble prompt.
  ScribblePrompt(Iterable<PromptPoint> points)
    : points = List<PromptPoint>.unmodifiable(points),
      super._() {
    if (this.points.isEmpty) throw ArgumentError.value(points, 'points', 'must not be empty');
  }

  /// Foreground scribble points.
  final List<PromptPoint> points;
}

/// A signed-stroke interactive segmentation prompt.
final class StrokePrompt extends InteractivePrompt {
  /// Creates an immutable stroke prompt.
  StrokePrompt(Iterable<PromptStroke> strokes)
    : strokes = List<PromptStroke>.unmodifiable(strokes),
      super._() {
    if (this.strokes.isEmpty) throw ArgumentError.value(strokes, 'strokes', 'must not be empty');
  }

  /// User-drawn signed strokes.
  final List<PromptStroke> strokes;
}
