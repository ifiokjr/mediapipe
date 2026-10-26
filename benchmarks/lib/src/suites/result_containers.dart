import 'dart:typed_data';

import 'package:mp_core/mp_core.dart';

import '../harness.dart';

/// Number of landmarks the face landmarker reports per face.
const int faceLandmarkCount = 478;

/// Number of landmarks the pose landmarker reports per body.
const int poseLandmarkCount = 33;

/// Dimensions of the MediaPipe image and text embedders' float vectors.
const int embeddingDimensions = 1024;

/// Result containers built once per frame and embedding comparisons.
///
/// The landmark cases mirror how native result conversion materializes
/// landmark lists, so they track the allocation cost a frame pays before an
/// application can read a single coordinate.
BenchmarkSuite resultContainersSuite() {
  late Embedding floatA;
  late Embedding floatB;
  late Embedding quantizedA;
  late Embedding quantizedB;

  return BenchmarkSuite(
    name: 'result_containers',
    benchmarks: <Benchmark>[
      Benchmark(
        name: 'result_containers/normalized_landmarks/face_$faceLandmarkCount',
        run: () => _normalizedLandmarks(faceLandmarkCount),
      ),
      Benchmark(
        name: 'result_containers/world_landmarks/pose_$poseLandmarkCount',
        run: () => _worldLandmarks(poseLandmarkCount),
      ),
      Benchmark(
        name: 'result_containers/cosine_similarity/float_$embeddingDimensions',
        setUp: () {
          floatA = _floatEmbedding(seed: 1);
          floatB = _floatEmbedding(seed: 2);
        },
        run: () => cosineSimilarity(floatA, floatB),
      ),
      Benchmark(
        name: 'result_containers/cosine_similarity/quantized_$embeddingDimensions',
        setUp: () {
          quantizedA = _quantizedEmbedding(seed: 3);
          quantizedB = _quantizedEmbedding(seed: 4);
        },
        run: () => cosineSimilarity(quantizedA, quantizedB),
      ),
    ],
  );
}

List<List<NormalizedLandmark>> _normalizedLandmarks(int count) => <List<NormalizedLandmark>>[
  List<NormalizedLandmark>.generate(
    count,
    (int index) => NormalizedLandmark(
      x: index / count,
      y: 1 - index / count,
      z: index * 0.001,
      visibility: 0.9,
      presence: 0.95,
    ),
    growable: false,
  ),
];

List<List<Landmark>> _worldLandmarks(int count) => <List<Landmark>>[
  List<Landmark>.generate(
    count,
    (int index) => Landmark(
      x: index * 0.01,
      y: index * 0.02,
      z: index * 0.03,
      visibility: 0.9,
      presence: 0.95,
    ),
    growable: false,
  ),
];

Embedding _floatEmbedding({required int seed}) {
  final Float32List values = Float32List(embeddingDimensions);

  for (int index = 0; index < values.length; index += 1) {
    values[index] = ((index * seed) % 97) / 97 - 0.5;
  }

  return Embedding.float(values, headIndex: 0);
}

Embedding _quantizedEmbedding({required int seed}) {
  final Uint8List values = Uint8List(embeddingDimensions);

  for (int index = 0; index < values.length; index += 1) {
    values[index] = (index * seed) % 251;
  }

  return Embedding.quantized(values, headIndex: 0);
}
