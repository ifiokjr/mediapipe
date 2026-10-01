import 'dart:math' as math;
import 'dart:typed_data';

import 'package:collection/collection.dart';
import 'package:meta/meta.dart';

const ListEquality<Object?> _objectListEquality = ListEquality<Object?>();
const ListEquality<double> _doubleListEquality = ListEquality<double>();

/// A scored label returned by a classifier or detector.
@immutable
final class Category {
  /// Creates a category.
  const Category({required this.index, required this.score, this.categoryName, this.displayName});

  /// The label index in the model metadata, or `-1` when unavailable.
  final int index;

  /// The model confidence score.
  final double score;

  /// The machine-readable category name.
  final String? categoryName;

  /// The localized category display name.
  final String? displayName;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Category &&
          index == other.index &&
          score == other.score &&
          categoryName == other.categoryName &&
          displayName == other.displayName;

  @override
  int get hashCode => Object.hash(index, score, categoryName, displayName);

  @override
  String toString() =>
      'Category(index: $index, score: $score, categoryName: $categoryName, displayName: $displayName)';
}

/// Categories emitted by one classifier head.
@immutable
final class Classifications {
  /// Creates an immutable classifier-head result.
  Classifications({required Iterable<Category> categories, required this.headIndex, this.headName})
    : categories = List<Category>.unmodifiable(categories);

  /// Categories ordered by descending score.
  final List<Category> categories;

  /// The classifier head index.
  final int headIndex;

  /// The optional tensor-metadata name for the classifier head.
  final String? headName;

  /// The highest-scored category, or `null` when this head has no result.
  Category? get topCategory => categories.firstOrNull;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Classifications &&
          _objectListEquality.equals(categories, other.categories) &&
          headIndex == other.headIndex &&
          headName == other.headName;

  @override
  int get hashCode => Object.hash(_objectListEquality.hash(categories), headIndex, headName);
}

/// A complete classification task result.
@immutable
final class ClassificationResult {
  /// Creates a classification result.
  ClassificationResult({required Iterable<Classifications> classifications, this.timestampMs})
    : classifications = List<Classifications>.unmodifiable(classifications);

  /// Results from every classifier head.
  final List<Classifications> classifications;

  /// Input timestamp for stream-based tasks, in milliseconds.
  final int? timestampMs;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ClassificationResult &&
          _objectListEquality.equals(classifications, other.classifications) &&
          timestampMs == other.timestampMs;

  @override
  int get hashCode => Object.hash(_objectListEquality.hash(classifications), timestampMs);
}

/// The storage representation of an embedding vector.
enum EmbeddingType {
  /// A floating-point vector.
  float,

  /// A scalar-quantized byte vector.
  quantized,
}

/// An embedding emitted by one model head.
@immutable
final class Embedding {
  Embedding._({
    required this.type,
    required this.headIndex,
    required this.headName,
    required this.floatValues,
    required this.quantizedValues,
  });

  /// Creates a floating-point embedding.
  factory Embedding.float(Float32List values, {required int headIndex, String? headName}) {
    if (values.isEmpty) throw ArgumentError.value(values, 'values', 'must not be empty');
    return Embedding._(
      type: EmbeddingType.float,
      headIndex: headIndex,
      headName: headName,
      floatValues: Float32List.fromList(values),
      quantizedValues: null,
    );
  }

  /// Creates a scalar-quantized embedding.
  factory Embedding.quantized(Uint8List values, {required int headIndex, String? headName}) {
    if (values.isEmpty) throw ArgumentError.value(values, 'values', 'must not be empty');
    return Embedding._(
      type: EmbeddingType.quantized,
      headIndex: headIndex,
      headName: headName,
      floatValues: null,
      quantizedValues: Uint8List.fromList(values),
    );
  }

  /// The vector storage representation.
  final EmbeddingType type;

  /// The model head index.
  final int headIndex;

  /// The optional tensor-metadata name for the model head.
  final String? headName;

  /// Floating-point values, present only when [type] is [EmbeddingType.float].
  final Float32List? floatValues;

  /// Quantized values, present only when [type] is [EmbeddingType.quantized].
  final Uint8List? quantizedValues;

  /// The number of dimensions in this embedding.
  int get length => floatValues?.length ?? quantizedValues!.length;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Embedding &&
          type == other.type &&
          headIndex == other.headIndex &&
          headName == other.headName &&
          const DeepCollectionEquality().equals(floatValues, other.floatValues) &&
          const DeepCollectionEquality().equals(quantizedValues, other.quantizedValues);

  @override
  int get hashCode => Object.hash(
    type,
    headIndex,
    headName,
    const DeepCollectionEquality().hash(floatValues),
    const DeepCollectionEquality().hash(quantizedValues),
  );
}

/// A complete embedding task result.
@immutable
final class EmbeddingResult {
  /// Creates an embedding result.
  EmbeddingResult({required Iterable<Embedding> embeddings, this.timestampMs})
    : embeddings = List<Embedding>.unmodifiable(embeddings);

  /// Results from every embedding head.
  final List<Embedding> embeddings;

  /// Input timestamp for stream-based tasks, in milliseconds.
  final int? timestampMs;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is EmbeddingResult &&
          _objectListEquality.equals(embeddings, other.embeddings) &&
          timestampMs == other.timestampMs;

  @override
  int get hashCode => Object.hash(_objectListEquality.hash(embeddings), timestampMs);
}

/// Computes cosine similarity for embeddings with the same representation.
double cosineSimilarity(Embedding first, Embedding second) {
  if (first.type != second.type) {
    throw ArgumentError('Embeddings must have the same representation.');
  }
  if (first.length != second.length) {
    throw ArgumentError('Embeddings must have the same number of dimensions.');
  }

  final Iterable<num> firstValues = first.floatValues ?? first.quantizedValues!;
  final Iterable<num> secondValues = second.floatValues ?? second.quantizedValues!;
  double dot = 0;
  double firstMagnitude = 0;
  double secondMagnitude = 0;
  final Iterator<num> firstIterator = firstValues.iterator;
  final Iterator<num> secondIterator = secondValues.iterator;
  while (firstIterator.moveNext() && secondIterator.moveNext()) {
    final double firstValue = firstIterator.current.toDouble();
    final double secondValue = secondIterator.current.toDouble();
    dot += firstValue * secondValue;
    firstMagnitude += firstValue * firstValue;
    secondMagnitude += secondValue * secondValue;
  }
  if (firstMagnitude == 0 || secondMagnitude == 0) {
    throw ArgumentError('Cosine similarity is undefined for a zero vector.');
  }
  return dot / (math.sqrt(firstMagnitude) * math.sqrt(secondMagnitude));
}

/// An integer pixel-space rectangle.
@immutable
final class BoundingBox {
  /// Creates a bounding box.
  BoundingBox({required this.left, required this.top, required this.width, required this.height}) {
    if (width < 0) throw ArgumentError.value(width, 'width', 'must not be negative');
    if (height < 0) throw ArgumentError.value(height, 'height', 'must not be negative');
  }

  /// Horizontal origin in pixels.
  final int left;

  /// Vertical origin in pixels.
  final int top;

  /// Width in pixels.
  final int width;

  /// Height in pixels.
  final int height;

  /// Exclusive right edge in pixels.
  int get right => left + width;

  /// Exclusive bottom edge in pixels.
  int get bottom => top + height;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is BoundingBox &&
          left == other.left &&
          top == other.top &&
          width == other.width &&
          height == other.height;

  @override
  int get hashCode => Object.hash(left, top, width, height);
}

/// A keypoint with coordinates normalized to the input dimensions.
@immutable
final class NormalizedKeypoint {
  /// Creates a normalized keypoint.
  const NormalizedKeypoint({required this.x, required this.y, this.label, this.score});

  /// Horizontal coordinate, normally in the range 0–1.
  final double x;

  /// Vertical coordinate, normally in the range 0–1.
  final double y;

  /// Optional keypoint label.
  final String? label;

  /// Optional confidence score.
  final double? score;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is NormalizedKeypoint &&
          x == other.x &&
          y == other.y &&
          label == other.label &&
          score == other.score;

  @override
  int get hashCode => Object.hash(x, y, label, score);
}

/// One detected object or region.
@immutable
final class Detection {
  /// Creates a detection.
  Detection({
    required Iterable<Category> categories,
    required this.boundingBox,
    Iterable<NormalizedKeypoint> keypoints = const <NormalizedKeypoint>[],
  }) : categories = List<Category>.unmodifiable(categories),
       keypoints = List<NormalizedKeypoint>.unmodifiable(keypoints);

  /// Category scores for this detection.
  final List<Category> categories;

  /// The detected region in input pixels.
  final BoundingBox boundingBox;

  /// Optional feature points associated with the detection.
  final List<NormalizedKeypoint> keypoints;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Detection &&
          _objectListEquality.equals(categories, other.categories) &&
          boundingBox == other.boundingBox &&
          _objectListEquality.equals(keypoints, other.keypoints);

  @override
  int get hashCode => Object.hash(
    _objectListEquality.hash(categories),
    boundingBox,
    _objectListEquality.hash(keypoints),
  );
}

/// A complete object or face detection result.
@immutable
final class DetectionResult {
  /// Creates a detection result.
  DetectionResult({required Iterable<Detection> detections, this.timestampMs})
    : detections = List<Detection>.unmodifiable(detections);

  /// All detected objects or regions.
  final List<Detection> detections;

  /// Input timestamp for video or live-stream tasks.
  final int? timestampMs;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is DetectionResult &&
          _objectListEquality.equals(detections, other.detections) &&
          timestampMs == other.timestampMs;

  @override
  int get hashCode => Object.hash(_objectListEquality.hash(detections), timestampMs);
}

/// A point in world coordinates, measured in metres.
@immutable
final class Landmark {
  /// Creates a world landmark.
  const Landmark({
    required this.x,
    required this.y,
    required this.z,
    this.visibility,
    this.presence,
    this.name,
  });

  /// Horizontal world coordinate in metres.
  final double x;

  /// Vertical world coordinate in metres.
  final double y;

  /// Depth in metres; smaller values are closer to the camera.
  final double z;

  /// Optional visibility confidence.
  final double? visibility;

  /// Optional presence confidence.
  final double? presence;

  /// Optional landmark name.
  final String? name;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Landmark &&
          x == other.x &&
          y == other.y &&
          z == other.z &&
          visibility == other.visibility &&
          presence == other.presence &&
          name == other.name;

  @override
  int get hashCode => Object.hash(x, y, z, visibility, presence, name);
}

/// A landmark whose coordinates are normalized to the input dimensions.
@immutable
final class NormalizedLandmark {
  /// Creates a normalized landmark.
  const NormalizedLandmark({
    required this.x,
    required this.y,
    required this.z,
    this.visibility,
    this.presence,
    this.name,
  });

  /// Horizontal coordinate, normally in the range 0–1.
  final double x;

  /// Vertical coordinate, normally in the range 0–1.
  final double y;

  /// Relative depth; smaller values are closer to the camera.
  final double z;

  /// Optional visibility confidence.
  final double? visibility;

  /// Optional presence confidence.
  final double? presence;

  /// Optional landmark name.
  final String? name;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is NormalizedLandmark &&
          x == other.x &&
          y == other.y &&
          z == other.z &&
          visibility == other.visibility &&
          presence == other.presence &&
          name == other.name;

  @override
  int get hashCode => Object.hash(x, y, z, visibility, presence, name);
}

/// A row-major floating-point matrix.
@immutable
final class MpMatrix {
  /// Creates a matrix and copies [values].
  MpMatrix({required this.rows, required this.columns, required Float32List values})
    : values = Float32List.fromList(values) {
    if (rows <= 0) throw ArgumentError.value(rows, 'rows', 'must be greater than zero');
    if (columns <= 0) {
      throw ArgumentError.value(columns, 'columns', 'must be greater than zero');
    }
    if (values.length != rows * columns) {
      throw ArgumentError.value(values.length, 'values.length', 'must equal rows * columns');
    }
  }

  /// The number of rows.
  final int rows;

  /// The number of columns.
  final int columns;

  /// Row-major matrix values.
  final Float32List values;

  /// Returns the value at [row], [column].
  double at(int row, int column) {
    RangeError.checkValueInInterval(row, 0, rows - 1, 'row');
    RangeError.checkValueInInterval(column, 0, columns - 1, 'column');
    return values[row * columns + column];
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is MpMatrix &&
          rows == other.rows &&
          columns == other.columns &&
          _doubleListEquality.equals(values, other.values);

  @override
  int get hashCode => Object.hash(rows, columns, _doubleListEquality.hash(values));
}
