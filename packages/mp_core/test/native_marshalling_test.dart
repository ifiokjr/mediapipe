import 'dart:ffi' as ffi;
import 'dart:typed_data';

import 'package:ffi/ffi.dart';
import 'package:mp_core/mp_core.dart';
import 'package:mp_core/native.dart' as native;
import 'package:test/test.dart';

void main() {
  test('maps every native status code without losing detail', () {
    expect(MpStatus.fromCode(0), MpStatus.ok);
    expect(MpStatus.fromCode(4), MpStatus.deadlineExceeded);
    expect(MpStatus.fromCode(6), MpStatus.alreadyExists);
    expect(MpStatus.fromCode(7), MpStatus.permissionDenied);
    expect(MpStatus.fromCode(8), MpStatus.resourceExhausted);
    expect(MpStatus.fromCode(11), MpStatus.outOfRange);
    expect(MpStatus.fromCode(16), MpStatus.unauthenticated);
    expect(MpStatus.fromCode(999), MpStatus.unknown);
  });

  test('converts column-major native matrices to row-major Dart values', () {
    using((Arena arena) {
      final ffi.Pointer<ffi.Float> values = arena<ffi.Float>(6);
      values.asTypedList(6).setAll(0, <double>[1, 4, 2, 5, 3, 6]);
      final native.MpMatrix matrix = native.MpMatrix.$allocate(
        arena,
        rows: 2,
        cols: 3,
        data: values,
      ).ref;

      expect(
        native.matrixFromNative(matrix),
        MpMatrix(rows: 2, columns: 3, values: Float32List.fromList(<double>[1, 2, 3, 4, 5, 6])),
      );
    });
  });

  test('packs native world landmarks into one buffer', () {
    using((Arena arena) {
      final ffi.Pointer<native.MpLandmark> landmarks = arena<native.MpLandmark>(2);
      landmarks[0]
        ..x = 1.5
        ..y = -2.5
        ..z = 0.5
        ..has_visibility = false
        ..has_presence = true
        ..presence = 0.75
        ..name = 'left_hip'.toNativeUtf8(allocator: arena).cast();
      landmarks[1]
        ..x = 3
        ..y = 4
        ..z = 5
        ..has_visibility = false
        ..has_presence = false
        ..name = ffi.nullptr;
      final native.MpLandmarks list = native.MpLandmarks.$allocate(
        arena,
        landmarks: landmarks,
        landmarks_count: 2,
      ).ref;

      final LandmarkList packed = native.landmarksFromNative(list);

      expect(packed.length, 2);
      expect(packed.names, <String?>['left_hip', null]);
      expect(packed[0], const Landmark(x: 1.5, y: -2.5, z: 0.5, presence: 0.75, name: 'left_hip'));
      expect(packed[1], const Landmark(x: 3, y: 4, z: 5));
    });
  });

  test('packs native normalized landmarks into one buffer', () {
    using((Arena arena) {
      final ffi.Pointer<native.MpNormalizedLandmark> landmarks = arena<native.MpNormalizedLandmark>(
        2,
      );
      landmarks[0]
        ..x = 0.25
        ..y = 0.5
        ..z = 0.75
        ..has_visibility = true
        ..visibility = 0.5
        ..has_presence = false
        ..name = 'nose'.toNativeUtf8(allocator: arena).cast();
      landmarks[1]
        ..x = 0.125
        ..y = 0.625
        ..z = -0.5
        ..has_visibility = false
        ..has_presence = false
        ..name = ffi.nullptr;
      final native.MpNormalizedLandmarks list = native.MpNormalizedLandmarks.$allocate(
        arena,
        landmarks: landmarks,
        landmarks_count: 2,
      ).ref;

      final NormalizedLandmarkList packed = native.normalizedLandmarksFromNative(list);

      expect(packed, isA<NormalizedLandmarkList>());
      expect(packed.length, 2);
      expect(packed.names, <String?>['nose', null]);
      expect(
        packed[0],
        const NormalizedLandmark(x: 0.25, y: 0.5, z: 0.75, visibility: 0.5, name: 'nose'),
      );
      expect(packed[1], const NormalizedLandmark(x: 0.125, y: 0.625, z: -0.5));
      expect(
        packed.values.sublist(0, NormalizedLandmarkList.stride),
        Float32List.fromList(<double>[0.25, 0.5, 0.75, 0.5, double.nan]),
      );
    });
  });

  test('copies nested classification data out of native memory', () {
    using((Arena arena) {
      final ffi.Pointer<native.MpCategory> categories = arena<native.MpCategory>();
      categories.ref
        ..index = 7
        ..score = 0.75
        ..category_name = 'running'.toNativeUtf8(allocator: arena).cast()
        ..display_name = 'Running'.toNativeUtf8(allocator: arena).cast();
      final ffi.Pointer<native.MpClassifications> heads = arena<native.MpClassifications>();
      heads.ref
        ..categories = categories
        ..categories_count = 1
        ..head_index = 2
        ..head_name = 'activity'.toNativeUtf8(allocator: arena).cast();
      final native.MpClassificationResult result = native.MpClassificationResult.$allocate(
        arena,
        classifications: heads,
        classifications_count: 1,
        timestamp_ms: 42,
        has_timestamp_ms: true,
      ).ref;

      expect(
        native.classificationResultFromNative(result),
        ClassificationResult(
          timestampMs: 42,
          classifications: <Classifications>[
            Classifications(
              headIndex: 2,
              headName: 'activity',
              categories: const <Category>[
                Category(index: 7, score: 0.75, categoryName: 'running', displayName: 'Running'),
              ],
            ),
          ],
        ),
      );
    });
  });

  test('builds native base and image-processing options with owned storage', () {
    final native.NativeScope scope = native.NativeScope(task: 'test');
    try {
      final native.MpBaseOptions base = scope
          .baseOptions(
            BaseOptions(modelAsset: ModelAsset.bytes(Uint8List.fromList(<int>[1, 2, 3]))),
          )
          .ref;
      expect(base.model_asset_buffer_count, 3);
      expect(base.model_asset_buffer.cast<ffi.Uint8>().asTypedList(3), <int>[1, 2, 3]);
      expect(base.file_descriptor, -1);
      expect(base.delegate, native.MpDelegate.MP_DELEGATE_CPU);

      final native.MpImageProcessingOptions processing = scope
          .imageProcessingOptions(
            ImageProcessingOptions(
              rotationDegrees: 90,
              regionOfInterest: NormalizedRect(left: 0.1, top: 0.2, right: 0.9, bottom: 0.8),
            ),
          )
          .ref;
      expect(processing.has_region_of_interest, 1);
      expect(processing.rotation_degrees, 90);
      expect(processing.region_of_interest.left, closeTo(0.1, 0.000001));
      expect(processing.region_of_interest.bottom, closeTo(0.8, 0.000001));
    } finally {
      scope.release();
    }
  });
}
