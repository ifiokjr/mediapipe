import 'dart:ffi';
import 'dart:typed_data';

import 'package:mp_core/mp_core.dart';
import 'package:mp_core/native.dart' as native;

import 'results.dart';

/// Copies a native face-landmarker result into immutable Dart values.
FaceLandmarkerResult faceLandmarkerResultFromNative(native.MpFaceLandmarkerResult value) =>
    FaceLandmarkerResult(
      faceLandmarks: List<List<NormalizedLandmark>>.generate(
        value.face_landmarks_count,
        (int index) => native.normalizedLandmarksFromNative(value.face_landmarks[index]),
        growable: false,
      ),
      faceBlendshapes: List<Classifications>.generate(
        value.face_blendshapes_count,
        (int index) => _classifications(value.face_blendshapes[index], index),
        growable: false,
      ),
      facialTransformationMatrixes: List<MpMatrix>.generate(
        value.facial_transformation_matrixes_count,
        (int index) => native.matrixFromNative(value.facial_transformation_matrixes[index]),
        growable: false,
      ),
    );

/// Copies a native gesture-recognizer result into immutable Dart values.
GestureRecognizerResult gestureRecognizerResultFromNative(native.MpGestureRecognizerResult value) =>
    GestureRecognizerResult(
      gestures: List<List<Category>>.generate(
        value.gestures_count,
        (int index) => native.categoriesFromNative(value.gestures[index]),
        growable: false,
      ),
      handedness: List<List<Category>>.generate(
        value.handedness_count,
        (int index) => native.categoriesFromNative(value.handedness[index]),
        growable: false,
      ),
      landmarks: List<List<NormalizedLandmark>>.generate(
        value.hand_landmarks_count,
        (int index) => native.normalizedLandmarksFromNative(value.hand_landmarks[index]),
        growable: false,
      ),
      worldLandmarks: List<List<Landmark>>.generate(
        value.hand_world_landmarks_count,
        (int index) => native.landmarksFromNative(value.hand_world_landmarks[index]),
        growable: false,
      ),
    );

/// Copies a native hand-landmarker result into immutable Dart values.
HandLandmarkerResult handLandmarkerResultFromNative(native.MpHandLandmarkerResult value) =>
    HandLandmarkerResult(
      handedness: List<List<Category>>.generate(
        value.handedness_count,
        (int index) => native.categoriesFromNative(value.handedness[index]),
        growable: false,
      ),
      landmarks: List<List<NormalizedLandmark>>.generate(
        value.hand_landmarks_count,
        (int index) => native.normalizedLandmarksFromNative(value.hand_landmarks[index]),
        growable: false,
      ),
      worldLandmarks: List<List<Landmark>>.generate(
        value.hand_world_landmarks_count,
        (int index) => native.landmarksFromNative(value.hand_world_landmarks[index]),
        growable: false,
      ),
    );

/// Copies a native holistic-landmarker result into immutable Dart values.
HolisticLandmarkerResult holisticLandmarkerResultFromNative(
  native.MpHolisticLandmarkerResult value,
) => HolisticLandmarkerResult(
  faceLandmarks: _normalizedGroup(value.face_landmarks),
  poseLandmarks: _normalizedGroup(value.pose_landmarks),
  poseWorldLandmarks: _worldGroup(value.pose_world_landmarks),
  leftHandLandmarks: _normalizedGroup(value.left_hand_landmarks),
  leftHandWorldLandmarks: _worldGroup(value.left_hand_world_landmarks),
  rightHandLandmarks: _normalizedGroup(value.right_hand_landmarks),
  rightHandWorldLandmarks: _worldGroup(value.right_hand_world_landmarks),
  faceBlendshapes: value.face_blendshapes.categories_count == 0
      ? const <Classifications>[]
      : <Classifications>[_classifications(value.face_blendshapes, 0)],
  poseSegmentationMasks: value.pose_segmentation_mask.address == 0
      ? const <MpImage>[]
      : <MpImage>[native.imageFromNative(value.pose_segmentation_mask, task: 'HolisticLandmarker')],
);

/// Copies a native pose-landmarker result into immutable Dart values.
PoseLandmarkerResult poseLandmarkerResultFromNative(native.MpPoseLandmarkerResult value) =>
    PoseLandmarkerResult(
      landmarks: List<List<NormalizedLandmark>>.generate(
        value.pose_landmarks_count,
        (int index) => native.normalizedLandmarksFromNative(value.pose_landmarks[index]),
        growable: false,
      ),
      worldLandmarks: List<List<Landmark>>.generate(
        value.pose_world_landmarks_count,
        (int index) => native.landmarksFromNative(value.pose_world_landmarks[index]),
        growable: false,
      ),
      segmentationMasks: List<MpImage>.generate(
        value.segmentation_masks_count,
        (int index) =>
            native.imageFromNative(value.segmentation_masks[index], task: 'PoseLandmarker'),
        growable: false,
      ),
    );

/// Copies a native image-segmenter result into immutable Dart values.
ImageSegmenterResult imageSegmenterResultFromNative(native.MpImageSegmenterResult value) =>
    ImageSegmenterResult(
      categoryMask: value.has_category_mask == 0
          ? null
          : native.imageFromNative(value.category_mask, task: 'ImageSegmenter'),
      confidenceMasks: List<MpImage>.generate(
        value.confidence_masks_count,
        (int index) =>
            native.imageFromNative(value.confidence_masks[index], task: 'ImageSegmenter'),
        growable: false,
      ),
      qualityScores: value.quality_scores_count == 0
          ? null
          : Float32List.fromList(value.quality_scores.asTypedList(value.quality_scores_count)),
    );

Classifications _classifications(native.MpCategories value, int headIndex) =>
    Classifications(categories: native.categoriesFromNative(value), headIndex: headIndex);

List<List<NormalizedLandmark>> _normalizedGroup(native.MpNormalizedLandmarks value) =>
    value.landmarks_count == 0
    ? const <List<NormalizedLandmark>>[]
    : <List<NormalizedLandmark>>[native.normalizedLandmarksFromNative(value)];

List<List<Landmark>> _worldGroup(native.MpLandmarks value) => value.landmarks_count == 0
    ? const <List<Landmark>>[]
    : <List<Landmark>>[native.landmarksFromNative(value)];
