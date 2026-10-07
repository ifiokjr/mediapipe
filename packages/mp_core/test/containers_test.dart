import 'dart:typed_data';

import 'package:mp_core/mp_core.dart';
import 'package:test/test.dart';

void main() {
  test('Category implements value equality', () {
    const Category first = Category(index: 1, score: 0.5, categoryName: 'cat', displayName: 'Cat');
    const Category second = Category(index: 1, score: 0.5, categoryName: 'cat', displayName: 'Cat');
    const Category other = Category(index: 2, score: 0.5, categoryName: 'cat', displayName: 'Cat');

    expect(first, second);
    expect(first.hashCode, second.hashCode);
    expect(first, isNot(other));
    expect(first.toString(), contains('cat'));
  });

  test('Classifications exposes the top category and compares by value', () {
    final Classifications first = Classifications(
      categories: <Category>[
        const Category(index: 0, score: 0.9),
        const Category(index: 1, score: 0.1),
      ],
      headIndex: 0,
      headName: 'head',
    );
    final Classifications second = Classifications(
      categories: <Category>[
        const Category(index: 0, score: 0.9),
        const Category(index: 1, score: 0.1),
      ],
      headIndex: 0,
      headName: 'head',
    );

    expect(first.topCategory?.index, 0);
    expect(Classifications(categories: const <Category>[], headIndex: 0).topCategory, isNull);
    expect(first, second);
    expect(first.hashCode, second.hashCode);
  });

  test('ClassificationResult compares by value including the timestamp', () {
    ClassificationResult result({required int timestampMs, double score = 0.5}) =>
        ClassificationResult(
          classifications: <Classifications>[
            Classifications(categories: <Category>[Category(index: 0, score: score)], headIndex: 0),
          ],
          timestampMs: timestampMs,
        );

    expect(result(timestampMs: 1), result(timestampMs: 1));
    expect(result(timestampMs: 1).hashCode, result(timestampMs: 1).hashCode);
    expect(result(timestampMs: 1), isNot(result(timestampMs: 2)));
    expect(result(timestampMs: 1, score: 0.6), isNot(result(timestampMs: 1)));
  });

  test('Embedding rejects empty vectors and reports dimensions', () {
    expect(() => Embedding.float(Float32List(0), headIndex: 0), throwsArgumentError);
    expect(() => Embedding.quantized(Uint8List(0), headIndex: 0), throwsArgumentError);

    final Embedding embedding = Embedding.float(
      Float32List.fromList(<double>[1, 2, 3]),
      headIndex: 1,
      headName: 'head',
    );
    expect(embedding.length, 3);
  });

  test('Embedding compares by value across both representations', () {
    final Embedding floatA = Embedding.float(Float32List.fromList(<double>[1, 2]), headIndex: 0);
    final Embedding floatB = Embedding.float(Float32List.fromList(<double>[1, 2]), headIndex: 0);
    final Embedding floatDifferent = Embedding.float(
      Float32List.fromList(<double>[1, 3]),
      headIndex: 0,
    );
    final Embedding quantizedA = Embedding.quantized(Uint8List.fromList(<int>[1, 2]), headIndex: 0);
    final Embedding quantizedB = Embedding.quantized(Uint8List.fromList(<int>[1, 2]), headIndex: 0);
    final Embedding quantizedDifferent = Embedding.quantized(
      Uint8List.fromList(<int>[1, 3]),
      headIndex: 0,
    );

    expect(floatA, floatB);
    expect(floatA.hashCode, floatB.hashCode);
    expect(floatA, isNot(floatDifferent));
    expect(quantizedA, quantizedB);
    expect(quantizedA.hashCode, quantizedB.hashCode);
    expect(quantizedA, isNot(quantizedDifferent));
    expect(floatA, isNot(quantizedA));
  });

  test('EmbeddingResult compares by value', () {
    EmbeddingResult result({double value = 1}) => EmbeddingResult(
      embeddings: <Embedding>[
        Embedding.float(Float32List.fromList(<double>[value]), headIndex: 0),
      ],
      timestampMs: 7,
    );

    expect(result(), result());
    expect(result().hashCode, result().hashCode);
    expect(result(), isNot(result(value: 2)));
  });

  test('BoundingBox derives edges and rejects negative extents', () {
    final BoundingBox box = BoundingBox(left: 2, top: 3, width: 5, height: 7);

    expect(box.right, 7);
    expect(box.bottom, 10);
    expect(box, BoundingBox(left: 2, top: 3, width: 5, height: 7));
    expect(() => BoundingBox(left: 0, top: 0, width: -1, height: 1), throwsArgumentError);
    expect(() => BoundingBox(left: 0, top: 0, width: 1, height: -1), throwsArgumentError);
  });

  test('Detection compares categories, boxes, and keypoints by value', () {
    Detection detection({int keypointY = 1}) => Detection(
      categories: <Category>[const Category(index: 0, score: 0.9)],
      boundingBox: BoundingBox(left: 0, top: 0, width: 4, height: 4),
      keypoints: <NormalizedKeypoint>[NormalizedKeypoint(x: 0.5, y: keypointY / 10)],
    );

    expect(detection(), detection());
    expect(detection().hashCode, detection().hashCode);
    expect(detection(), isNot(detection(keypointY: 2)));

    final DetectionResult result = DetectionResult(
      detections: <Detection>[detection()],
      timestampMs: 3,
    );
    final DetectionResult same = DetectionResult(
      detections: <Detection>[detection()],
      timestampMs: 3,
    );
    expect(result, same);
    expect(result.hashCode, same.hashCode);
  });

  test('Landmark types compare by value', () {
    const Landmark world = Landmark(x: 1, y: 2, z: 3, visibility: 0.5, presence: 0.5, name: 'nose');
    const Landmark same = Landmark(x: 1, y: 2, z: 3, visibility: 0.5, presence: 0.5, name: 'nose');
    const Landmark other = Landmark(x: 1, y: 2, z: 3, visibility: 0.6, presence: 0.5, name: 'nose');

    expect(world, same);
    expect(world.hashCode, same.hashCode);
    expect(world, isNot(other));

    const NormalizedLandmark normalized = NormalizedLandmark(x: 0.1, y: 0.2, z: 0.3);
    const NormalizedLandmark normalizedSame = NormalizedLandmark(x: 0.1, y: 0.2, z: 0.3);
    const NormalizedLandmark normalizedOther = NormalizedLandmark(x: 0.2, y: 0.2, z: 0.3);

    expect(normalized, normalizedSame);
    expect(normalized, isNot(normalizedOther));
  });

  test('MpMatrix compares by value', () {
    MpMatrix matrix() =>
        MpMatrix(rows: 1, columns: 2, values: Float32List.fromList(<double>[1, 2]));

    expect(matrix(), matrix());
    expect(matrix().hashCode, matrix().hashCode);
    expect(() => MpMatrix(rows: 0, columns: 1, values: Float32List(1)), throwsArgumentError);
    expect(() => MpMatrix(rows: 1, columns: 0, values: Float32List(1)), throwsArgumentError);
    expect(() => MpMatrix(rows: 1, columns: 2, values: Float32List(1)), throwsArgumentError);
  });

  test('cosineSimilarity rejects mismatched representations and dimensions', () {
    final Embedding float = Embedding.float(Float32List.fromList(<double>[1]), headIndex: 0);
    final Embedding quantized = Embedding.quantized(Uint8List.fromList(<int>[1]), headIndex: 0);
    final Embedding longer = Embedding.float(Float32List.fromList(<double>[1, 2]), headIndex: 0);

    expect(() => cosineSimilarity(float, quantized), throwsArgumentError);
    expect(() => cosineSimilarity(float, longer), throwsArgumentError);
  });
}
