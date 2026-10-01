import 'dart:typed_data';

import 'package:mp_core/mp_core.dart';
import 'package:test/test.dart';

void main() {
  test('AudioData copies samples and calculates duration', () {
    final Float32List source = Float32List.fromList(<double>[0, 1, 2, 3]);
    final AudioData audio = AudioData(channelCount: 2, sampleRateHz: 2, samples: source);

    source[0] = 99;

    expect(audio.samples, <double>[0, 1, 2, 3]);
    expect(audio.frameCount, 2);
    expect(audio.duration, const Duration(seconds: 1));
  });

  test('MpImage enforces pixel format and exact buffer size', () {
    final MpImage image = MpImage.uint8(
      width: 2,
      height: 1,
      format: MpImageFormat.srgb,
      data: Uint8List.fromList(<int>[1, 2, 3, 4, 5, 6]),
    );

    expect(image.sampleCount, 6);
    expect(image.byteLength, 6);
    expect(
      () => MpImage.uint8(width: 1, height: 1, format: MpImageFormat.float32x1, data: Uint8List(1)),
      throwsArgumentError,
    );
  });

  test('cosineSimilarity supports float and quantized embeddings', () {
    final Embedding first = Embedding.float(Float32List.fromList(<double>[1, 2]), headIndex: 0);
    final Embedding second = Embedding.float(Float32List.fromList(<double>[2, 4]), headIndex: 0);

    expect(cosineSimilarity(first, second), closeTo(1, 1e-12));
    expect(
      cosineSimilarity(
        Embedding.quantized(Uint8List.fromList(<int>[1, 0]), headIndex: 0),
        Embedding.quantized(Uint8List.fromList(<int>[0, 1]), headIndex: 0),
      ),
      0,
    );
    expect(
      () => cosineSimilarity(
        first,
        Embedding.float(Float32List.fromList(<double>[0, 0]), headIndex: 0),
      ),
      throwsArgumentError,
    );
  });

  test('MpMatrix validates dimensions and indexes values', () {
    final MpMatrix matrix = MpMatrix(
      rows: 2,
      columns: 2,
      values: Float32List.fromList(<double>[1, 2, 3, 4]),
    );

    expect(matrix.at(1, 0), 3);
    expect(() => matrix.at(2, 0), throwsRangeError);
  });
}
