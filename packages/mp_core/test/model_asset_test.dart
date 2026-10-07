import 'dart:typed_data';

import 'package:mp_core/mp_core.dart';
import 'package:mp_core/native.dart' as native;
import 'package:test/test.dart';

void main() {
  test('resolveNativeModelAsset converts file URIs into path assets', () async {
    final ModelAsset resolved = await native.resolveNativeModelAsset(
      ModelAsset.uri(Uri.file('/tmp/models/lang.tflite')),
    );

    expect(resolved, isA<ModelAssetPath>().having((path) => path.path, 'path', contains('lang')));
  });

  test('resolveNativeModelAsset rejects models served over plain HTTP', () async {
    await expectLater(
      native.resolveNativeModelAsset(ModelAsset.uri(Uri.parse('http://example.com/model.tflite'))),
      throwsA(
        isA<MpException>().having((error) => error.status, 'status', MpStatus.invalidArgument),
      ),
    );
  });

  test('resolveNativeModelAsset passes resolved assets through unchanged', () async {
    final ModelAsset path = ModelAsset.path('/tmp/model.tflite');
    final ModelAsset bytes = ModelAsset.bytes(Uint8List.fromList(<int>[1, 2, 3]));

    expect(await native.resolveNativeModelAsset(path), same(path));
    expect(await native.resolveNativeModelAsset(bytes), same(bytes));
  });

  test('ModelAssetBytes rejects empty buffers before copying', () {
    expect(() => ModelAsset.bytes(Uint8List(0)), throwsArgumentError);
  });

  test('AudioData validates channels, rate, and sample counts', () {
    expect(
      () => AudioData(channelCount: 0, sampleRateHz: 1, samples: Float32List(2)),
      throwsArgumentError,
    );
    expect(
      () => AudioData(channelCount: 1, sampleRateHz: 0, samples: Float32List(2)),
      throwsArgumentError,
    );
    expect(
      () => AudioData(channelCount: 1, sampleRateHz: double.nan, samples: Float32List(2)),
      throwsArgumentError,
    );
    expect(
      () => AudioData(channelCount: 2, sampleRateHz: 1, samples: Float32List(3)),
      throwsArgumentError,
    );
    expect(
      () => AudioData(channelCount: 2, sampleRateHz: 1, samples: Float32List(0)),
      throwsArgumentError,
    );
  });

  test('MpImage validates dimensions, storage, and sample counts', () {
    expect(
      () => MpImage.uint8(width: 0, height: 1, format: MpImageFormat.srgb, data: Uint8List(3)),
      throwsArgumentError,
    );
    expect(
      () => MpImage.uint8(width: 1, height: 0, format: MpImageFormat.srgb, data: Uint8List(3)),
      throwsArgumentError,
    );
    expect(
      () => MpImage.uint8(width: 1, height: 1, format: MpImageFormat.srgb, data: Uint8List(2)),
      throwsArgumentError,
    );
    expect(
      () => MpImage.uint16(width: 1, height: 1, format: MpImageFormat.srgb, data: Uint16List(3)),
      throwsArgumentError,
    );
    expect(
      () => MpImage.float32(width: 1, height: 1, format: MpImageFormat.gray8, data: Float32List(1)),
      throwsArgumentError,
    );

    final MpImage uint16 = MpImage.uint16(
      width: 1,
      height: 1,
      format: MpImageFormat.gray16,
      data: Uint16List.fromList(<int>[65535]),
    );
    final MpImage float32 = MpImage.float32(
      width: 1,
      height: 1,
      format: MpImageFormat.float32x1,
      data: Float32List.fromList(<double>[0.5]),
    );

    expect(uint16.sampleCount, 1);
    expect(uint16.byteLength, 2);
    expect(float32.sampleCount, 1);
    expect(float32.byteLength, 4);
  });

  test('MpImage compares pixel buffers by value', () {
    MpImage image() => MpImage.uint8(
      width: 1,
      height: 1,
      format: MpImageFormat.srgb,
      data: Uint8List.fromList(<int>[1, 2, 3]),
    );

    expect(image(), image());
    expect(image().hashCode, image().hashCode);
    expect(
      image(),
      isNot(
        MpImage.uint8(
          width: 1,
          height: 1,
          format: MpImageFormat.srgb,
          data: Uint8List.fromList(<int>[1, 2, 4]),
        ),
      ),
    );
  });

  test('ImageProcessingOptions rejects rotations that are not multiples of 90', () {
    expect(() => ImageProcessingOptions(rotationDegrees: 45), throwsArgumentError);
    expect(ImageProcessingOptions(rotationDegrees: 180).rotationDegrees, 180);
  });

  test('NormalizedRect rejects out-of-range and non-finite edges', () {
    expect(() => NormalizedRect(left: -0.1, top: 0, right: 1, bottom: 1), throwsArgumentError);
    expect(() => NormalizedRect(left: 0, top: 0, right: 1.1, bottom: 1), throwsArgumentError);
    expect(
      () => NormalizedRect(left: 0, top: 0, right: 1, bottom: double.nan),
      throwsArgumentError,
    );
    expect(
      () => NormalizedRect(left: 0, top: 0, right: 1, bottom: double.infinity),
      throwsArgumentError,
    );
    expect(() => NormalizedRect(left: 0.5, top: 0, right: 0.5, bottom: 1), throwsArgumentError);
    expect(() => NormalizedRect(left: 0, top: 0.5, right: 1, bottom: 0.5), throwsArgumentError);

    expect(
      NormalizedRect(left: 0, top: 0, right: 1, bottom: 1),
      NormalizedRect(left: 0, top: 0, right: 1, bottom: 1),
    );
  });

  test('ClassifierOptions rejects a non-finite score threshold', () {
    expect(() => ClassifierOptions(scoreThreshold: double.nan), throwsArgumentError);
    expect(() => ClassifierOptions(scoreThreshold: double.infinity), throwsArgumentError);
    expect(() => ClassifierOptions(scoreThreshold: -0.1), throwsArgumentError);
    expect(() => ClassifierOptions(scoreThreshold: 1.1), throwsArgumentError);
    expect(ClassifierOptions(scoreThreshold: 0.5).scoreThreshold, 0.5);
  });
}
