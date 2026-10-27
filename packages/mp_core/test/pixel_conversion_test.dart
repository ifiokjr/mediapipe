import 'dart:typed_data';

import 'package:mp_core/mp_core.dart';
import 'package:test/test.dart';

void main() {
  group('PixelPlane', () {
    test('defaults to a packed pixel stride', () {
      final PixelPlane plane = PixelPlane(bytes: Uint8List(4), rowStride: 4);

      expect(plane.pixelStride, 1);
      expect(plane.rowStride, 4);
      expect(plane.bytes, hasLength(4));
    });
  });

  group('PixelConverter.forceDartKernels', () {
    tearDown(() => PixelConverter.forceDartKernels = false);

    test('yields the same output from every kernel as the default dispatch', () {
      final PixelPlane bgra = _plane(<int>[1, 2, 3, 4, 5, 6, 7, 8], rowStride: 8, pixelStride: 4);
      final PixelPlane nv21 = _plane(<int>[16, 235, 81, 145, 128, 128], rowStride: 2);
      final PixelPlane y = _plane(<int>[82, 82, 82, 82], rowStride: 2);
      final PixelPlane u = _plane(<int>[90], rowStride: 1);
      final PixelPlane v = _plane(<int>[240], rowStride: 1);

      final MpImageUint8 defaultBgra = PixelConverter.bgra8888ToSrgba(
        width: 2,
        height: 1,
        plane: bgra,
      );
      final MpImageUint8 defaultNv21 = PixelConverter.nv21ToSrgb(width: 2, height: 2, plane: nv21);
      final MpImageUint8 defaultYuv = PixelConverter.yuv420ToSrgb(
        width: 2,
        height: 2,
        y: y,
        u: u,
        v: v,
      );

      PixelConverter.forceDartKernels = true;

      expect(
        PixelConverter.bgra8888ToSrgba(width: 2, height: 1, plane: bgra).data,
        defaultBgra.data,
      );
      expect(PixelConverter.nv21ToSrgb(width: 2, height: 2, plane: nv21).data, defaultNv21.data);
      expect(
        PixelConverter.yuv420ToSrgb(width: 2, height: 2, y: y, u: u, v: v).data,
        defaultYuv.data,
      );
    });
  });

  group('PixelConverter.bgra8888ToSrgba', () {
    test('swizzles channels and drops row padding', () {
      final MpImageUint8 image = PixelConverter.bgra8888ToSrgba(
        width: 2,
        height: 1,
        plane: _plane(
          <int>[30, 20, 10, 255, 60, 50, 40, 128, 99, 99, 99, 99],
          rowStride: 12,
          pixelStride: 4,
        ),
      );

      expect(image.format, MpImageFormat.srgba);
      expect(image.width, 2);
      expect(image.height, 1);
      expect(image.data, <int>[10, 20, 30, 255, 40, 50, 60, 128]);
    });

    test('handles multiple rows with padding on each', () {
      final MpImageUint8 image = PixelConverter.bgra8888ToSrgba(
        width: 1,
        height: 2,
        plane: _plane(<int>[1, 2, 3, 4, 0, 0, 5, 6, 7, 8, 0, 0], rowStride: 6, pixelStride: 4),
      );

      expect(image.data, <int>[3, 2, 1, 4, 7, 6, 5, 8]);
    });

    test('rejects a pixel stride other than four', () {
      expect(
        () => PixelConverter.bgra8888ToSrgba(
          width: 1,
          height: 1,
          plane: _plane(<int>[0, 0, 0, 0], rowStride: 4),
        ),
        throwsA(
          isA<StateError>().having(
            (StateError e) => e.message,
            'message',
            contains('pixel stride'),
          ),
        ),
      );
    });

    test('rejects a row stride narrower than the packed row', () {
      expect(
        () => PixelConverter.bgra8888ToSrgba(
          width: 2,
          height: 1,
          plane: _plane(<int>[0, 0, 0, 0, 0, 0, 0, 0], rowStride: 4, pixelStride: 4),
        ),
        throwsA(
          isA<StateError>().having((StateError e) => e.message, 'message', contains('row stride')),
        ),
      );
    });

    test('rejects a buffer shorter than the strided image', () {
      expect(
        () => PixelConverter.bgra8888ToSrgba(
          width: 1,
          height: 2,
          plane: _plane(<int>[0, 0, 0, 0], rowStride: 4, pixelStride: 4),
        ),
        throwsA(
          isA<StateError>().having(
            (StateError e) => e.message,
            'message',
            contains('expected at least 8'),
          ),
        ),
      );
    });

    test('rejects non-positive dimensions', () {
      expect(
        () => PixelConverter.bgra8888ToSrgba(
          width: 0,
          height: 1,
          plane: _plane(<int>[], rowStride: 0, pixelStride: 4),
        ),
        throwsArgumentError,
      );
      expect(
        () => PixelConverter.bgra8888ToSrgba(
          width: 1,
          height: 0,
          plane: _plane(<int>[], rowStride: 4, pixelStride: 4),
        ),
        throwsArgumentError,
      );
    });
  });

  group('PixelConverter.nv21ToSrgb', () {
    test('converts neutral chroma using the row stride', () {
      final MpImageUint8 image = PixelConverter.nv21ToSrgb(
        width: 2,
        height: 2,
        plane: _plane(<int>[16, 235, 99, 99, 81, 145, 99, 99, 128, 128, 99, 99], rowStride: 4),
      );

      expect(image.format, MpImageFormat.srgb);
      expect(_pixels(image), <List<int>>[
        <int>[0, 0, 0],
        <int>[255, 255, 255],
        <int>[76, 76, 76],
        <int>[150, 150, 150],
      ]);
    });

    test('reads interleaved V then U and clamps saturated channels', () {
      // Y rows: 128 everywhere. Chroma row 0 (pixels x=0,1): V=255, U=128.
      // Chroma row 0 (pixels x=2,3): V=128, U=255. Chroma row 1 swaps them.
      final MpImageUint8 image = PixelConverter.nv21ToSrgb(
        width: 4,
        height: 4,
        plane: _plane(<int>[
          ...List<int>.filled(16, 128),
          255,
          128,
          128,
          255,
          128,
          255,
          255,
          128,
        ], rowStride: 4),
      );

      const List<int> red = <int>[255, 27, 130];
      const List<int> blue = <int>[130, 81, 255];
      final List<List<int>> pixels = _pixels(image);

      expect(pixels.sublist(0, 4), <List<int>>[red, red, blue, blue]);
      expect(pixels.sublist(4, 8), <List<int>>[red, red, blue, blue]);
      expect(pixels.sublist(8, 12), <List<int>>[blue, blue, red, red]);
      expect(pixels.sublist(12, 16), <List<int>>[blue, blue, red, red]);
    });

    test('clamps negative blue to zero', () {
      final MpImageUint8 image = PixelConverter.nv21ToSrgb(
        width: 2,
        height: 2,
        plane: _plane(<int>[128, 128, 128, 128, 128, 0], rowStride: 2),
      );

      expect(_pixels(image).first, <int>[130, 180, 0]);
    });

    test('rejects odd dimensions', () {
      expect(
        () => PixelConverter.nv21ToSrgb(
          width: 3,
          height: 2,
          plane: _plane(List<int>.filled(9, 0), rowStride: 3),
        ),
        throwsA(isA<StateError>().having((StateError e) => e.message, 'message', contains('even'))),
      );
    });

    test('rejects a non-unit pixel stride', () {
      expect(
        () => PixelConverter.nv21ToSrgb(
          width: 2,
          height: 2,
          plane: _plane(List<int>.filled(6, 0), rowStride: 2, pixelStride: 2),
        ),
        throwsA(
          isA<StateError>().having(
            (StateError e) => e.message,
            'message',
            contains('pixel stride'),
          ),
        ),
      );
    });

    test('rejects a row stride narrower than the width', () {
      expect(
        () => PixelConverter.nv21ToSrgb(
          width: 4,
          height: 2,
          plane: _plane(List<int>.filled(12, 0), rowStride: 3),
        ),
        throwsA(
          isA<StateError>().having((StateError e) => e.message, 'message', contains('row stride')),
        ),
      );
    });

    test('rejects a buffer without the chroma rows', () {
      expect(
        () => PixelConverter.nv21ToSrgb(
          width: 2,
          height: 2,
          plane: _plane(List<int>.filled(4, 0), rowStride: 2),
        ),
        throwsA(
          isA<StateError>().having(
            (StateError e) => e.message,
            'message',
            contains('expected at least 6'),
          ),
        ),
      );
    });

    test('rejects non-positive dimensions before layout checks', () {
      expect(
        () => PixelConverter.nv21ToSrgb(width: -2, height: 2, plane: _plane(<int>[], rowStride: 2)),
        throwsArgumentError,
      );
    });
  });

  group('PixelConverter.yuv420ToSrgb', () {
    test('converts with independent row and pixel strides', () {
      final MpImageUint8 image = PixelConverter.yuv420ToSrgb(
        width: 2,
        height: 2,
        y: _plane(<int>[82, 82, 0, 82, 82, 0], rowStride: 3),
        u: _plane(<int>[90, 0], rowStride: 2, pixelStride: 2),
        v: _plane(<int>[240, 0], rowStride: 2, pixelStride: 2),
      );

      expect(image.format, MpImageFormat.srgb);
      expect(_pixels(image), everyElement(<int>[255, 1, 0]));
    });

    test('samples each chroma value for a pair of luma samples per row', () {
      // Planar 4x2: chroma row 0 has two pairs, U differs per pair.
      final MpImageUint8 image = PixelConverter.yuv420ToSrgb(
        width: 4,
        height: 2,
        y: _plane(List<int>.filled(8, 128), rowStride: 4),
        u: _plane(<int>[128, 255], rowStride: 2),
        v: _plane(<int>[255, 128], rowStride: 2),
      );

      const List<int> red = <int>[255, 27, 130];
      const List<int> blue = <int>[130, 81, 255];

      expect(_pixels(image), <List<int>>[red, red, blue, blue, red, red, blue, blue]);
    });

    test('rejects odd dimensions', () {
      expect(
        () => PixelConverter.yuv420ToSrgb(
          width: 2,
          height: 3,
          y: _plane(List<int>.filled(6, 0), rowStride: 2),
          u: _plane(<int>[0], rowStride: 1),
          v: _plane(<int>[0], rowStride: 1),
        ),
        throwsA(isA<StateError>().having((StateError e) => e.message, 'message', contains('even'))),
      );
    });

    test('rejects a non-positive pixel stride on any plane', () {
      expect(
        () => PixelConverter.yuv420ToSrgb(
          width: 2,
          height: 2,
          y: _plane(<int>[0, 0, 0, 0], rowStride: 2),
          u: _plane(<int>[0], rowStride: 1, pixelStride: 0),
          v: _plane(<int>[0], rowStride: 1),
        ),
        throwsA(
          isA<StateError>().having(
            (StateError e) => e.message,
            'message',
            startsWith('U plane pixel stride'),
          ),
        ),
      );
    });

    test('rejects a row stride that cannot hold the strided row', () {
      expect(
        () => PixelConverter.yuv420ToSrgb(
          width: 4,
          height: 2,
          y: _plane(List<int>.filled(8, 0), rowStride: 4),
          u: _plane(<int>[0, 0], rowStride: 2, pixelStride: 2),
          v: _plane(<int>[0, 0, 0], rowStride: 2, pixelStride: 2),
        ),
        throwsA(
          isA<StateError>().having(
            (StateError e) => e.message,
            'message',
            startsWith('U plane row stride'),
          ),
        ),
      );
    });

    test('rejects a plane buffer shorter than its last row', () {
      expect(
        () => PixelConverter.yuv420ToSrgb(
          width: 2,
          height: 2,
          y: _plane(<int>[0, 0, 0], rowStride: 2),
          u: _plane(<int>[0], rowStride: 1),
          v: _plane(<int>[0], rowStride: 1),
        ),
        throwsA(
          isA<StateError>().having(
            (StateError e) => e.message,
            'message',
            contains('Y YUV420 plane'),
          ),
        ),
      );
    });

    test('rejects non-positive dimensions before layout checks', () {
      expect(
        () => PixelConverter.yuv420ToSrgb(
          width: 2,
          height: 0,
          y: _plane(<int>[], rowStride: 2),
          u: _plane(<int>[], rowStride: 1),
          v: _plane(<int>[], rowStride: 1),
        ),
        throwsArgumentError,
      );
    });
  });
}

PixelPlane _plane(List<int> bytes, {required int rowStride, int pixelStride = 1}) =>
    PixelPlane(bytes: Uint8List.fromList(bytes), rowStride: rowStride, pixelStride: pixelStride);

List<List<int>> _pixels(MpImageUint8 image) => List<List<int>>.generate(
  image.width * image.height,
  (int index) => image.data.sublist(index * 3, index * 3 + 3),
);
