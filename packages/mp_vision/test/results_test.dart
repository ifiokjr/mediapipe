import 'dart:typed_data';

import 'package:mp_core/mp_core.dart';
import 'package:mp_vision/mp_vision.dart';
import 'package:test/test.dart';

MpImage _mask(int shade) => MpImage.uint8(
  width: 2,
  height: 2,
  format: MpImageFormat.gray8,
  data: Uint8List.fromList(<int>[shade, shade, shade, shade]),
);

void main() {
  group('ImageSegmenterResult equality', () {
    test('equal masks and scores compare equal', () {
      final ImageSegmenterResult first = ImageSegmenterResult(
        categoryMask: _mask(1),
        confidenceMasks: <MpImage>[_mask(2), _mask(3)],
        qualityScores: Float32List.fromList(<double>[0.5, 0.25]),
      );
      final ImageSegmenterResult second = ImageSegmenterResult(
        categoryMask: _mask(1),
        confidenceMasks: <MpImage>[_mask(2), _mask(3)],
        qualityScores: Float32List.fromList(<double>[0.5, 0.25]),
      );

      expect(first, equals(second));
      expect(first.hashCode, second.hashCode);
    });

    test('a different pixel or score breaks equality', () {
      final ImageSegmenterResult base = ImageSegmenterResult(
        categoryMask: _mask(1),
        confidenceMasks: <MpImage>[_mask(2)],
        qualityScores: Float32List.fromList(<double>[0.5]),
      );

      expect(
        base,
        isNot(
          equals(
            ImageSegmenterResult(
              categoryMask: _mask(9),
              confidenceMasks: <MpImage>[_mask(2)],
              qualityScores: Float32List.fromList(<double>[0.5]),
            ),
          ),
        ),
      );
      expect(
        base,
        isNot(
          equals(
            ImageSegmenterResult(
              categoryMask: _mask(1),
              confidenceMasks: <MpImage>[_mask(2)],
              qualityScores: Float32List.fromList(<double>[0.9]),
            ),
          ),
        ),
      );
      // Null scores only equal null scores.
      // The default result (no mask, no scores) equals itself.
      final ImageSegmenterResult empty = ImageSegmenterResult();
      expect(empty, equals(ImageSegmenterResult()));
      expect(empty.qualityScores, isNull);
      expect(empty.categoryMask, isNull);
      // But it differs from a result that carries scores.
      expect(
        empty,
        isNot(equals(ImageSegmenterResult(qualityScores: Float32List.fromList(<double>[0.5])))),
      );
    });
  });

  group('PoseLandmarkerResult equality', () {
    NormalizedLandmark landmark(double x) => NormalizedLandmark(x: x, y: 0, z: 0);

    test('compares nested landmarks and masks', () {
      final PoseLandmarkerResult first = PoseLandmarkerResult(
        landmarks: <List<NormalizedLandmark>>[
          <NormalizedLandmark>[landmark(0.1), landmark(0.2)],
        ],
        worldLandmarks: const <List<Landmark>>[],
        segmentationMasks: <MpImage>[_mask(4)],
      );
      final PoseLandmarkerResult second = PoseLandmarkerResult(
        landmarks: <List<NormalizedLandmark>>[
          <NormalizedLandmark>[landmark(0.1), landmark(0.2)],
        ],
        worldLandmarks: const <List<Landmark>>[],
        segmentationMasks: <MpImage>[_mask(4)],
      );

      expect(first, equals(second));
      expect(first.hashCode, second.hashCode);

      final PoseLandmarkerResult different = PoseLandmarkerResult(
        landmarks: <List<NormalizedLandmark>>[
          <NormalizedLandmark>[landmark(0.1), landmark(0.9)],
        ],
        worldLandmarks: const <List<Landmark>>[],
        segmentationMasks: <MpImage>[_mask(4)],
      );
      expect(first, isNot(equals(different)));
    });
  });

  group('interactive segmentation prompts', () {
    test('PromptPoint compares by coordinates', () {
      expect(PromptPoint(0.25, 0.75), equals(PromptPoint(0.25, 0.75)));
      expect(PromptPoint(0.25, 0.75), isNot(equals(PromptPoint(0.75, 0.25))));
      expect(PromptPoint(0.25, 0.75).hashCode, equals(PromptPoint(0.25, 0.75).hashCode));
    });

    test('PromptStroke compares mode, points, and completion', () {
      final PromptStroke first = PromptStroke(
        brushMode: BrushMode.positive,
        points: <PromptPoint>[PromptPoint(0.1, 0.2)],
      );
      final PromptStroke second = PromptStroke(
        brushMode: BrushMode.positive,
        points: <PromptPoint>[PromptPoint(0.1, 0.2)],
      );

      expect(first, equals(second));
      expect(first.hashCode, second.hashCode);

      expect(
        first,
        isNot(
          equals(
            PromptStroke(
              brushMode: BrushMode.negative,
              points: <PromptPoint>[PromptPoint(0.1, 0.2)],
            ),
          ),
        ),
      );
      expect(
        first,
        isNot(
          equals(
            PromptStroke(
              brushMode: BrushMode.positive,
              points: <PromptPoint>[PromptPoint(0.9, 0.2)],
            ),
          ),
        ),
      );
    });

    test('rejects out-of-range coordinates and empty strokes', () {
      expect(() => PromptPoint(1.5, 0), throwsArgumentError);
      expect(
        () => PromptStroke(brushMode: BrushMode.positive, points: const <PromptPoint>[]),
        throwsArgumentError,
      );
    });
  });
}
