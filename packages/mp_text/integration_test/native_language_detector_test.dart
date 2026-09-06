@TestOn('vm')
library;

import 'package:mp_core/mp_core.dart';
import 'package:mp_text/mp_text.dart';
import 'package:test/test.dart';

void main() {
  test('runs the official language detector through the C runtime', () async {
    final LanguageDetector detector = await LanguageDetector.create(
      LanguageDetectorOptions(
        baseOptions: BaseOptions(
          modelAsset: ModelAsset.uri(
            Uri.parse(
              'https://storage.googleapis.com/mediapipe-assets/tasks/testdata/text/'
              'language_detector.tflite?generation=1782184334735649',
            ),
            sha256: '5f64d821110dd2a3280546e8cd59dff09547e25d5f5c9711ec3f03416414dbb2',
          ),
        ),
      ),
    );
    addTearDown(detector.close);

    final LanguageDetectorResult result = await detector.detect(
      'This sentence is written in English.',
    );

    expect(result.topPrediction?.languageCode, startsWith('en'));
    expect(result.topPrediction?.probability, greaterThan(0.8));
  });
}
