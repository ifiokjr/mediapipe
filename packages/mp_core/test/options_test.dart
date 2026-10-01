import 'dart:typed_data';

import 'package:mp_core/mp_core.dart';
import 'package:test/test.dart';

void main() {
  group('ModelAsset', () {
    test('copies in-memory bytes', () {
      final Uint8List source = Uint8List.fromList(<int>[1, 2, 3]);
      final ModelAssetBytes asset =
          ModelAsset.bytes(source, name: 'model.tflite') as ModelAssetBytes;

      source[0] = 9;

      expect(asset.bytes, <int>[1, 2, 3]);
      expect(asset.name, 'model.tflite');
    });

    test('rejects empty sources and invalid digests', () {
      expect(() => ModelAsset.path('  '), throwsArgumentError);
      expect(() => ModelAsset.bytes(Uint8List(0)), throwsArgumentError);
      expect(() => ModelAsset.uri(Uri.parse('models/model.tflite')), throwsArgumentError);
      expect(
        () => ModelAsset.uri(Uri.https('example.com', '/model.tflite'), sha256: 'INVALID'),
        throwsArgumentError,
      );
    });
  });

  group('ClassifierOptions', () {
    test('copies category filters', () {
      final List<String> allowlist = <String>['cat'];
      final ClassifierOptions options = ClassifierOptions(categoryAllowlist: allowlist);

      allowlist.add('dog');

      expect(options.categoryAllowlist, <String>['cat']);
      expect(() => options.categoryAllowlist.add('bird'), throwsUnsupportedError);
    });

    test('validates filters and numeric bounds', () {
      expect(() => ClassifierOptions(maxResults: 0), throwsArgumentError);
      expect(() => ClassifierOptions(scoreThreshold: -0.1), throwsArgumentError);
      expect(() => ClassifierOptions(scoreThreshold: 1.1), throwsArgumentError);
      expect(
        () => ClassifierOptions(
          categoryAllowlist: <String>['cat'],
          categoryDenylist: <String>['dog'],
        ),
        throwsArgumentError,
      );
    });
  });

  test('delegate-specific options are validated in release builds', () {
    expect(
      () => LiteRtOptions(
        accelerator: LiteRtAccelerator.gpu,
        npuDispatchLibraryDirectory: '/tmp/dispatch',
      ),
      throwsArgumentError,
    );
    expect(
      () =>
          BaseOptions(modelAsset: ModelAsset.path('model.tflite'), liteRtOptions: LiteRtOptions()),
      throwsArgumentError,
    );
  });
}
