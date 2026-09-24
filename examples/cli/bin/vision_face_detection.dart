// Run with: dart run examples/bin/vision_face_detection.dart
//
// Detects faces in a real photograph using the same BlazeFace model the
// upstream MediaPipe test suite uses. The model and image are downloaded once
// and cached, and the model digest is verified before inference runs.
//
// The native runtime is resolved from the MP SDK's native asset hook. When
// running outside a Flutter build, point the SDK at a locally built runtime:
//
//   MP_NATIVE_LIBRARY=.mp-sdk/macos-arm64 \
//     dart run examples/bin/vision_face_detection.dart

import 'dart:io';
import 'dart:typed_data';

import 'package:mp_core/mp_core.dart';
import 'package:mp_examples/mp_examples.dart';
import 'package:mp_vision/mp_vision.dart';

Future<void> main() async {
  final MpAssetCache cache = MpAssetCache.defaults();
  final FaceDetector detector = await FaceDetector.create(
    FaceDetectorOptions(
      baseOptions: BaseOptions(modelAsset: await cache.model(MpExampleModels.faceDetector)),
      minDetectionConfidence: 0.4,
    ),
  );

  try {
    final Uint8List imageBytes = await cache.bytes(MpExampleInputs.catsAndDogs);
    final MpImage image = mpImageFromBytes(imageBytes);
    stdout.writeln('Input: ${image.width}x${image.height} ${image.format.name}');

    final DetectionResult result = await detector.detect(image);
    stdout.writeln('Faces detected: ${result.detections.length}');
    for (final Detection detection in result.detections) {
      final Category? top = detection.categories.isEmpty ? null : detection.categories.first;
      final BoundingBox box = detection.boundingBox;
      stdout.writeln(
        '  ${top?.displayName ?? top?.categoryName ?? 'face'} '
        'score=${(top?.score ?? 0).toStringAsFixed(3)} '
        'box=(${box.left}, ${box.top}, ${box.width}x${box.height}) '
        'keypoints=${detection.keypoints.length}',
      );
    }
  } finally {
    await detector.close();
  }
}
