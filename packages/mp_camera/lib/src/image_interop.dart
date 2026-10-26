import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:mp_core/mp_core.dart';

/// Decodes an [MpImage] into a [ui.Image] for drawing with a [ui.Canvas].
extension MpImageToUiImage on MpImage {
  /// Uploads this image's pixels as a [ui.Image].
  ///
  /// Supports 8-bit sRGB, sRGBA, and gray images, and single-channel float
  /// masks such as segmentation confidences, which are rendered as opaque
  /// grayscale with 1.0 mapped to white. Other formats throw an
  /// [UnsupportedError]; convert them to one of those first.
  Future<ui.Image> toUiImage() {
    final Uint8List rgba = switch (this) {
      MpImageUint8(:final data, format: MpImageFormat.srgba) => data,
      MpImageUint8(:final data, format: MpImageFormat.srgb) => _expand(data, 3, width * height),
      MpImageUint8(:final data, format: MpImageFormat.gray8) => _expand(data, 1, width * height),
      MpImageFloat32(:final data, format: MpImageFormat.float32x1) => _fromMask(data),
      _ => throw UnsupportedError('Cannot render an MpImage with format ${format.name}.'),
    };
    final Completer<ui.Image> completer = Completer<ui.Image>();

    ui.decodeImageFromPixels(rgba, width, height, ui.PixelFormat.rgba8888, completer.complete);

    return completer.future;
  }
}

/// Converts a [ui.Image] into an [MpImage] for still-image inference.
extension UiImageToMpImage on ui.Image {
  /// Reads this image's pixels into an [MpImageFormat.srgba] image.
  ///
  /// Fails when the image's bytes cannot be read, which happens once the
  /// image has been disposed: debug builds assert inside Flutter, release
  /// builds surface an [ArgumentError].
  Future<MpImage> toMpImage() async {
    final ByteData data = ArgumentError.checkNotNull(
      await toByteData(format: ui.ImageByteFormat.rawStraightRgba),
      'pixels',
    );

    return MpImageUint8.adopt(
      width: width,
      height: height,
      format: MpImageFormat.srgba,
      data: data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
    );
  }
}

Uint8List _expand(Uint8List samples, int channels, int pixels) {
  final Uint8List rgba = Uint8List(pixels * 4);
  int source = 0;
  int destination = 0;

  for (int pixel = 0; pixel < pixels; pixel += 1) {
    if (channels == 3) {
      rgba[destination] = samples[source];
      rgba[destination + 1] = samples[source + 1];
      rgba[destination + 2] = samples[source + 2];
    } else {
      final int gray = samples[source];
      rgba[destination] = gray;
      rgba[destination + 1] = gray;
      rgba[destination + 2] = gray;
    }

    rgba[destination + 3] = 0xFF;
    source += channels;
    destination += 4;
  }

  return rgba;
}

Uint8List _fromMask(Float32List mask) {
  final Uint8List rgba = Uint8List(mask.length * 4);
  int destination = 0;

  for (int pixel = 0; pixel < mask.length; pixel += 1) {
    final double value = mask[pixel];
    final int gray = value <= 0 ? 0 : (value >= 1 ? 255 : (value * 255).round());
    rgba[destination] = gray;
    rgba[destination + 1] = gray;
    rgba[destination + 2] = gray;
    rgba[destination + 3] = 0xFF;
    destination += 4;
  }

  return rgba;
}
