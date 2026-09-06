@TestOn('vm')
library;

import 'dart:typed_data';

import 'package:mp_core/mp_core.dart';
import 'package:mp_vision/mp_vision.dart';
import 'package:test/test.dart';

void main() {
  test('runs the official face detector through the C runtime', () async {
    final FaceDetector detector = await FaceDetector.create(
      FaceDetectorOptions(
        baseOptions: BaseOptions(
          modelAsset: ModelAsset.uri(
            Uri.parse(
              'https://storage.googleapis.com/mediapipe-assets/tasks/testdata/vision/'
              'face_detection_short_range.tflite',
            ),
            sha256: 'bbff11cebd1eb27a1e004cae0b0e63ec8c551cbf34a4451148b4908b8db3eca8',
          ),
        ),
      ),
    );
    addTearDown(detector.close);

    final DetectionResult result = await detector.detect(
      MpImage.uint8(
        width: 128,
        height: 128,
        format: MpImageFormat.srgb,
        data: Uint8List(128 * 128 * 3),
      ),
    );

    expect(result.detections, isEmpty);
  });
}
