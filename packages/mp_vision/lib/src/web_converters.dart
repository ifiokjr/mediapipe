import 'dart:js_interop';
import 'dart:js_interop_unsafe';
import 'dart:typed_data';

import 'package:mp_core/mp_core.dart';
import 'package:mp_core/web.dart';

import 'results.dart';

/// Converts a web face or object detection result.
DetectionResult webDetectionResult(JSAny? value) {
  final Map<Object?, Object?> result = _map(value);
  final List<Object?> detections = result['detections']! as List<Object?>;
  return DetectionResult(
    detections: detections.map((Object? detectionValue) {
      final Map<Object?, Object?> detection = detectionValue! as Map<Object?, Object?>;
      final Map<Object?, Object?>? box = detection['boundingBox'] as Map<Object?, Object?>?;
      return Detection(
        categories: _categories(detection['categories']),
        boundingBox: BoundingBox(
          left: (box?['originX'] as num?)?.toInt() ?? 0,
          top: (box?['originY'] as num?)?.toInt() ?? 0,
          width: (box?['width'] as num?)?.toInt() ?? 0,
          height: (box?['height'] as num?)?.toInt() ?? 0,
        ),
        keypoints: _list(detection['keypoints']).map((Object? keypointValue) {
          final Map<Object?, Object?> keypoint = keypointValue! as Map<Object?, Object?>;
          return NormalizedKeypoint(
            x: (keypoint['x']! as num).toDouble(),
            y: (keypoint['y']! as num).toDouble(),
            label: webEmptyToNull(keypoint['label'] as String?),
            score: (keypoint['score'] as num?)?.toDouble(),
          );
        }),
      );
    }),
  );
}

/// Converts a web face-landmarker result.
FaceLandmarkerResult webFaceLandmarkerResult(JSAny? value) {
  final Map<Object?, Object?> result = _map(value);
  return FaceLandmarkerResult(
    faceLandmarks: _normalizedLandmarkGroups(result['faceLandmarks']),
    faceBlendshapes: _classifications(result['faceBlendshapes']),
    facialTransformationMatrixes: _list(result['facialTransformationMatrixes']).map((
      Object? matrixValue,
    ) {
      final Map<Object?, Object?> matrix = matrixValue! as Map<Object?, Object?>;
      return MpMatrix(
        rows: (matrix['rows']! as num).toInt(),
        columns: (matrix['columns']! as num).toInt(),
        values: Float32List.fromList(
          _list(matrix['data']).cast<num>().map((num item) => item.toDouble()).toList(),
        ),
      );
    }),
  );
}

/// Converts a web gesture-recognizer result.
GestureRecognizerResult webGestureRecognizerResult(JSAny? value) {
  final Map<Object?, Object?> result = _map(value);
  return GestureRecognizerResult(
    gestures: _categoryGroups(result['gestures']),
    handedness: _categoryGroups(result['handedness'] ?? result['handednesses']),
    landmarks: _normalizedLandmarkGroups(result['landmarks']),
    worldLandmarks: _landmarkGroups(result['worldLandmarks']),
  );
}

/// Converts a web hand-landmarker result.
HandLandmarkerResult webHandLandmarkerResult(JSAny? value) {
  final Map<Object?, Object?> result = _map(value);
  return HandLandmarkerResult(
    handedness: _categoryGroups(result['handedness'] ?? result['handednesses']),
    landmarks: _normalizedLandmarkGroups(result['landmarks']),
    worldLandmarks: _landmarkGroups(result['worldLandmarks']),
  );
}

/// Converts a web holistic-landmarker result and copies its masks immediately.
HolisticLandmarkerResult webHolisticLandmarkerResult(JSAny? value) {
  final JSObject result = value! as JSObject;
  final List<JSObject> masks = _objectArray(result['poseSegmentationMasks']);
  return HolisticLandmarkerResult(
    faceLandmarks: _normalizedLandmarkGroups(_property(result, 'faceLandmarks')),
    faceBlendshapes: _classifications(_property(result, 'faceBlendshapes')),
    poseLandmarks: _normalizedLandmarkGroups(_property(result, 'poseLandmarks')),
    poseWorldLandmarks: _landmarkGroups(_property(result, 'poseWorldLandmarks')),
    poseSegmentationMasks: masks.map(_copyFloatMask),
    leftHandLandmarks: _normalizedLandmarkGroups(_property(result, 'leftHandLandmarks')),
    leftHandWorldLandmarks: _landmarkGroups(_property(result, 'leftHandWorldLandmarks')),
    rightHandLandmarks: _normalizedLandmarkGroups(_property(result, 'rightHandLandmarks')),
    rightHandWorldLandmarks: _landmarkGroups(_property(result, 'rightHandWorldLandmarks')),
  );
}

/// Converts a web embedding result.
EmbeddingResult webEmbeddingResult(JSAny? value) {
  final Map<Object?, Object?> result = _map(value);
  return EmbeddingResult(
    timestampMs: webOptionalInt(result['timestampMs']),
    embeddings: _list(result['embeddings']).map((Object? embeddingValue) {
      final Map<Object?, Object?> embedding = embeddingValue! as Map<Object?, Object?>;
      final int headIndex = (embedding['headIndex']! as num).toInt();
      final String? headName = webEmptyToNull(embedding['headName'] as String?);
      if (embedding['floatEmbedding'] case final List<Object?> values when values.isNotEmpty) {
        return Embedding.float(
          Float32List.fromList(values.cast<num>().map((num item) => item.toDouble()).toList()),
          headIndex: headIndex,
          headName: headName,
        );
      }
      final Uint8List quantized = switch (embedding['quantizedEmbedding']) {
        final Uint8List bytes => bytes,
        final List<Object?> bytes => Uint8List.fromList(
          bytes.cast<num>().map((num item) => item.toInt()).toList(),
        ),
        _ => throw const MpException(MpStatus.internal, 'MediaPipe returned an empty embedding.'),
      };
      return Embedding.quantized(quantized, headIndex: headIndex, headName: headName);
    }),
  );
}

/// Converts a web image-segmentation result and releases its mask handles.
ImageSegmenterResult webImageSegmenterResult(JSAny? value) {
  final JSObject result = value! as JSObject;
  try {
    final List<JSObject> confidenceMasks = _objectArray(result['confidenceMasks']);
    final JSAny? categoryMask = result['categoryMask'];
    final Object? scores = _property(result, 'qualityScores');
    return ImageSegmenterResult(
      confidenceMasks: confidenceMasks.map(_copyFloatMask),
      categoryMask: categoryMask.isUndefinedOrNull
          ? null
          : _copyUint8Mask(categoryMask! as JSObject),
      qualityScores: scores == null
          ? null
          : Float32List.fromList(
              (scores as List<Object?>).cast<num>().map((num item) => item.toDouble()).toList(),
            ),
    );
  } finally {
    callWebMethod<JSAny?>(result, 'close');
  }
}

/// Converts the mask returned by the split interactive segmenter.
ImageSegmenterResult webSingleConfidenceMask(JSAny? value) {
  final JSObject mask = value! as JSObject;
  try {
    return ImageSegmenterResult(confidenceMasks: <MpImage>[_copyFloatMask(mask)]);
  } finally {
    callWebMethod<JSAny?>(mask, 'close');
  }
}

/// Converts a web pose-landmarker result and releases its mask handles.
PoseLandmarkerResult webPoseLandmarkerResult(JSAny? value) {
  final JSObject result = value! as JSObject;
  try {
    return PoseLandmarkerResult(
      landmarks: _normalizedLandmarkGroups(_property(result, 'landmarks')),
      worldLandmarks: _landmarkGroups(_property(result, 'worldLandmarks')),
      segmentationMasks: _objectArray(result['segmentationMasks']).map(_copyFloatMask),
    );
  } finally {
    callWebMethod<JSAny?>(result, 'close');
  }
}

Map<Object?, Object?> _map(JSAny? value) => webDartify(value)! as Map<Object?, Object?>;

Object? _property(JSObject object, String property) => webDartify(object[property]);

List<Object?> _list(Object? value) => value == null ? const <Object?>[] : value as List<Object?>;

Category _category(Object? value) {
  final Map<Object?, Object?> category = value! as Map<Object?, Object?>;
  return Category(
    index: (category['index']! as num).toInt(),
    score: (category['score']! as num).toDouble(),
    categoryName: webEmptyToNull(category['categoryName'] as String?),
    displayName: webEmptyToNull(category['displayName'] as String?),
  );
}

List<Category> _categories(Object? value) => _list(value).map(_category).toList();

List<List<Category>> _categoryGroups(Object? value) => _list(value).map(_categories).toList();

Classifications _classification(Object? value) {
  final Map<Object?, Object?> classification = value! as Map<Object?, Object?>;
  return Classifications(
    categories: _categories(classification['categories']),
    headIndex: (classification['headIndex']! as num).toInt(),
    headName: webEmptyToNull(classification['headName'] as String?),
  );
}

List<Classifications> _classifications(Object? value) => _list(value).map(_classification).toList();

NormalizedLandmark _normalizedLandmark(Object? value) {
  final Map<Object?, Object?> landmark = value! as Map<Object?, Object?>;
  return NormalizedLandmark(
    x: (landmark['x']! as num).toDouble(),
    y: (landmark['y']! as num).toDouble(),
    z: (landmark['z']! as num).toDouble(),
    visibility: (landmark['visibility'] as num?)?.toDouble(),
    presence: (landmark['presence'] as num?)?.toDouble(),
    name: webEmptyToNull(landmark['name'] as String?),
  );
}

List<List<NormalizedLandmark>> _normalizedLandmarkGroups(Object? value) =>
    _list(value).map((Object? group) => _list(group).map(_normalizedLandmark).toList()).toList();

Landmark _landmark(Object? value) {
  final Map<Object?, Object?> landmark = value! as Map<Object?, Object?>;
  return Landmark(
    x: (landmark['x']! as num).toDouble(),
    y: (landmark['y']! as num).toDouble(),
    z: (landmark['z']! as num).toDouble(),
    visibility: (landmark['visibility'] as num?)?.toDouble(),
    presence: (landmark['presence'] as num?)?.toDouble(),
    name: webEmptyToNull(landmark['name'] as String?),
  );
}

List<List<Landmark>> _landmarkGroups(Object? value) =>
    _list(value).map((Object? group) => _list(group).map(_landmark).toList()).toList();

List<JSObject> _objectArray(JSAny? value) {
  if (value.isUndefinedOrNull) return const <JSObject>[];
  final List<JSAny?> values = (value! as JSArray<JSAny?>).toDart;
  return values.map((JSAny? item) => item! as JSObject).toList();
}

int _objectInt(JSObject object, String property) => (webDartify(object[property])! as num).toInt();

MpImage _copyFloatMask(JSObject mask) {
  final JSFloat32Array values = callWebMethod<JSFloat32Array>(mask, 'getAsFloat32Array');
  return MpImage.float32(
    width: _objectInt(mask, 'width'),
    height: _objectInt(mask, 'height'),
    format: MpImageFormat.float32x1,
    data: Float32List.fromList(values.toDart),
  );
}

MpImage _copyUint8Mask(JSObject mask) {
  final JSUint8Array values = callWebMethod<JSUint8Array>(mask, 'getAsUint8Array');
  return MpImage.uint8(
    width: _objectInt(mask, 'width'),
    height: _objectInt(mask, 'height'),
    format: MpImageFormat.gray8,
    data: Uint8List.fromList(values.toDart),
  );
}
