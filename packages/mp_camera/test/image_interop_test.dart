import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:mp_camera/mp_camera.dart';
import 'package:mp_core/mp_core.dart';

void main() {
  Future<Uint8List> pixelsOf(ui.Image image) async {
    final ByteData bytes = (await image.toByteData(format: ui.ImageByteFormat.rawStraightRgba))!;

    return bytes.buffer.asUint8List(bytes.offsetInBytes, bytes.lengthInBytes);
  }

  group('MpImage.toUiImage', () {
    test('uploads sRGBA pixels unchanged', () async {
      final Uint8List rgba = Uint8List.fromList(<int>[255, 0, 0, 255, 0, 255, 0, 128]);
      final ui.Image image = await MpImageUint8.adopt(
        width: 2,
        height: 1,
        format: MpImageFormat.srgba,
        data: rgba,
      ).toUiImage();

      expect(image.width, 2);
      expect(image.height, 1);
      expect(await pixelsOf(image), rgba);
      image.dispose();
    });

    test('expands sRGB and gray samples to opaque RGBA', () async {
      final ui.Image rgb = await MpImageUint8.adopt(
        width: 1,
        height: 2,
        format: MpImageFormat.srgb,
        data: Uint8List.fromList(<int>[1, 2, 3, 4, 5, 6]),
      ).toUiImage();
      final ui.Image gray = await MpImageUint8.adopt(
        width: 2,
        height: 1,
        format: MpImageFormat.gray8,
        data: Uint8List.fromList(<int>[7, 9]),
      ).toUiImage();

      expect(await pixelsOf(rgb), <int>[1, 2, 3, 255, 4, 5, 6, 255]);
      expect(await pixelsOf(gray), <int>[7, 7, 7, 255, 9, 9, 9, 255]);
      rgb.dispose();
      gray.dispose();
    });

    test('renders a float confidence mask as clamped grayscale', () async {
      final ui.Image mask = await MpImageFloat32.adopt(
        width: 4,
        height: 1,
        format: MpImageFormat.float32x1,
        data: Float32List.fromList(<double>[-0.5, 0, 0.5, 1.5]),
      ).toUiImage();

      expect(await pixelsOf(mask), <int>[
        0, 0, 0, 255, //
        0, 0, 0, 255,
        128, 128, 128, 255,
        255, 255, 255, 255,
      ]);
      mask.dispose();
    });

    test('rejects formats it cannot render', () {
      expect(
        () => MpImageUint16.adopt(
          width: 1,
          height: 1,
          format: MpImageFormat.gray16,
          data: Uint16List(1),
        ).toUiImage(),
        throwsUnsupportedError,
      );
    });
  });

  group('ui.Image.toMpImage', () {
    test('round-trips pixels into an sRGBA image', () async {
      final Uint8List rgba = Uint8List.fromList(<int>[10, 20, 30, 255, 40, 50, 60, 255]);
      final ui.Image image = await MpImageUint8.adopt(
        width: 2,
        height: 1,
        format: MpImageFormat.srgba,
        data: rgba,
      ).toUiImage();

      final MpImage converted = await image.toMpImage();

      expect(converted.width, 2);
      expect(converted.height, 1);
      expect(converted.format, MpImageFormat.srgba);
      expect((converted as MpImageUint8).data, rgba);
      image.dispose();
    });

    test('fails once the image has been disposed', () async {
      final ui.Image image = await MpImageUint8.adopt(
        width: 1,
        height: 1,
        format: MpImageFormat.srgba,
        data: Uint8List(4),
      ).toUiImage();
      image.dispose();

      // Debug builds assert inside Flutter before the bytes can be read.
      await expectLater(image.toMpImage(), throwsA(isA<Error>()));
    });
  });
}
