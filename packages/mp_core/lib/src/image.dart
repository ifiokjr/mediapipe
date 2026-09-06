import 'dart:typed_data';

import 'package:collection/collection.dart';
import 'package:meta/meta.dart';

/// Pixel formats supported by MediaPipe's C image API.
enum MpImageFormat {
  /// Three 8-bit sRGB channels.
  srgb(channels: 3, bytesPerChannel: 1, storage: MpImageStorage.uint8),

  /// Four 8-bit sRGBA channels.
  srgba(channels: 4, bytesPerChannel: 1, storage: MpImageStorage.uint8),

  /// One 8-bit grayscale channel.
  gray8(channels: 1, bytesPerChannel: 1, storage: MpImageStorage.uint8),

  /// One 16-bit grayscale channel.
  gray16(channels: 1, bytesPerChannel: 2, storage: MpImageStorage.uint16),

  /// Three 16-bit sRGB channels.
  srgb48(channels: 3, bytesPerChannel: 2, storage: MpImageStorage.uint16),

  /// Four 16-bit sRGBA channels.
  srgba64(channels: 4, bytesPerChannel: 2, storage: MpImageStorage.uint16),

  /// One 32-bit floating-point channel.
  float32x1(channels: 1, bytesPerChannel: 4, storage: MpImageStorage.float32),

  /// Two 32-bit floating-point channels.
  float32x2(channels: 2, bytesPerChannel: 4, storage: MpImageStorage.float32),

  /// Four 32-bit floating-point channels.
  float32x4(channels: 4, bytesPerChannel: 4, storage: MpImageStorage.float32);

  const MpImageFormat({
    required this.channels,
    required this.bytesPerChannel,
    required this.storage,
  });

  /// Number of channels per pixel.
  final int channels;

  /// Number of bytes per channel.
  final int bytesPerChannel;

  /// Typed-data representation accepted for this format.
  final MpImageStorage storage;
}

/// Typed-data storage families supported by [MpImage].
enum MpImageStorage {
  /// Unsigned 8-bit samples.
  uint8,

  /// Unsigned 16-bit samples.
  uint16,

  /// 32-bit floating-point samples.
  float32,
}

/// An immutable, tightly packed image passed to a vision task.
@immutable
sealed class MpImage {
  const MpImage._({required this.width, required this.height, required this.format});

  /// Creates an image backed by 8-bit [data].
  factory MpImage.uint8({
    required int width,
    required int height,
    required MpImageFormat format,
    required Uint8List data,
  }) = MpImageUint8;

  /// Creates an image backed by 16-bit [data].
  factory MpImage.uint16({
    required int width,
    required int height,
    required MpImageFormat format,
    required Uint16List data,
  }) = MpImageUint16;

  /// Creates an image backed by floating-point [data].
  factory MpImage.float32({
    required int width,
    required int height,
    required MpImageFormat format,
    required Float32List data,
  }) = MpImageFloat32;

  /// Image width in pixels.
  final int width;

  /// Image height in pixels.
  final int height;

  /// Pixel format.
  final MpImageFormat format;

  /// Number of stored samples.
  int get sampleCount;

  /// Number of bytes in the tightly packed pixel buffer.
  int get byteLength => sampleCount * format.bytesPerChannel;

  /// Required number of samples for this image's dimensions and format.
  int get expectedSampleCount => width * height * format.channels;

  static void _validate({
    required int width,
    required int height,
    required MpImageFormat format,
    required MpImageStorage storage,
    required int sampleCount,
  }) {
    if (width <= 0) throw ArgumentError.value(width, 'width', 'must be greater than zero');
    if (height <= 0) throw ArgumentError.value(height, 'height', 'must be greater than zero');
    if (format.storage != storage) {
      throw ArgumentError.value(format, 'format', 'requires ${format.storage.name} storage');
    }
    final int expected = width * height * format.channels;
    if (sampleCount != expected) {
      throw ArgumentError.value(sampleCount, 'data.length', 'must equal $expected');
    }
  }
}

/// An image backed by unsigned 8-bit samples.
@immutable
final class MpImageUint8 extends MpImage {
  /// Creates an immutable copy of [data].
  MpImageUint8({
    required super.width,
    required super.height,
    required super.format,
    required Uint8List data,
  }) : data = Uint8List.fromList(data),
       super._() {
    MpImage._validate(
      width: width,
      height: height,
      format: format,
      storage: MpImageStorage.uint8,
      sampleCount: data.length,
    );
  }

  /// Tightly packed pixel samples.
  final Uint8List data;

  @override
  int get sampleCount => data.length;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is MpImageUint8 &&
          width == other.width &&
          height == other.height &&
          format == other.format &&
          const ListEquality<int>().equals(data, other.data);

  @override
  int get hashCode => Object.hash(width, height, format, const ListEquality<int>().hash(data));
}

/// An image backed by unsigned 16-bit samples.
@immutable
final class MpImageUint16 extends MpImage {
  /// Creates an immutable copy of [data].
  MpImageUint16({
    required super.width,
    required super.height,
    required super.format,
    required Uint16List data,
  }) : data = Uint16List.fromList(data),
       super._() {
    MpImage._validate(
      width: width,
      height: height,
      format: format,
      storage: MpImageStorage.uint16,
      sampleCount: data.length,
    );
  }

  /// Tightly packed pixel samples.
  final Uint16List data;

  @override
  int get sampleCount => data.length;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is MpImageUint16 &&
          width == other.width &&
          height == other.height &&
          format == other.format &&
          const ListEquality<int>().equals(data, other.data);

  @override
  int get hashCode => Object.hash(width, height, format, const ListEquality<int>().hash(data));
}

/// An image backed by 32-bit floating-point samples.
@immutable
final class MpImageFloat32 extends MpImage {
  /// Creates an immutable copy of [data].
  MpImageFloat32({
    required super.width,
    required super.height,
    required super.format,
    required Float32List data,
  }) : data = Float32List.fromList(data),
       super._() {
    MpImage._validate(
      width: width,
      height: height,
      format: format,
      storage: MpImageStorage.float32,
      sampleCount: data.length,
    );
  }

  /// Tightly packed pixel samples.
  final Float32List data;

  @override
  int get sampleCount => data.length;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is MpImageFloat32 &&
          width == other.width &&
          height == other.height &&
          format == other.format &&
          const ListEquality<double>().equals(data, other.data);

  @override
  int get hashCode => Object.hash(width, height, format, const ListEquality<double>().hash(data));
}

/// Input transforms applied before a vision task runs.
@immutable
final class ImageProcessingOptions {
  /// Creates image-processing options.
  ImageProcessingOptions({this.regionOfInterest, this.rotationDegrees = 0}) {
    if (rotationDegrees % 90 != 0) {
      throw ArgumentError.value(rotationDegrees, 'rotationDegrees', 'must be a multiple of 90');
    }
  }

  /// Optional normalized crop rectangle.
  final NormalizedRect? regionOfInterest;

  /// Clockwise input rotation in degrees.
  final int rotationDegrees;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ImageProcessingOptions &&
          regionOfInterest == other.regionOfInterest &&
          rotationDegrees == other.rotationDegrees;

  @override
  int get hashCode => Object.hash(regionOfInterest, rotationDegrees);
}

/// A rectangle with values normalized to the input dimensions.
@immutable
final class NormalizedRect {
  /// Creates a normalized rectangle.
  NormalizedRect({
    required this.left,
    required this.top,
    required this.right,
    required this.bottom,
  }) {
    for (final MapEntry<String, double> entry in <String, double>{
      'left': left,
      'top': top,
      'right': right,
      'bottom': bottom,
    }.entries) {
      if (entry.value < 0 || entry.value > 1) {
        throw ArgumentError.value(entry.value, entry.key, 'must be between 0 and 1');
      }
    }
    if (left >= right) throw ArgumentError.value(left, 'left', 'must be less than right');
    if (top >= bottom) throw ArgumentError.value(top, 'top', 'must be less than bottom');
  }

  /// Left edge in the range 0–1.
  final double left;

  /// Top edge in the range 0–1.
  final double top;

  /// Right edge in the range 0–1.
  final double right;

  /// Bottom edge in the range 0–1.
  final double bottom;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is NormalizedRect &&
          left == other.left &&
          top == other.top &&
          right == other.right &&
          bottom == other.bottom;

  @override
  int get hashCode => Object.hash(left, top, right, bottom);
}

/// Vision task execution modes.
enum VisionRunningMode {
  /// Process unrelated still images.
  image,

  /// Process ordered frames from a decoded video.
  video,

  /// Process ordered camera frames and emit asynchronous results.
  liveStream,
}
