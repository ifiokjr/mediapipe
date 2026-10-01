import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:mp_core/mp_core.dart';
import 'package:mp_genai/mp_genai.dart';
import 'package:mp_text/mp_text.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  group('mobile plugin contract', () {
    testWidgets('text plugins reject malformed model bytes through the native SDK', (
      WidgetTester tester,
    ) async {
      final ModelAsset invalidModel = ModelAsset.bytes(
        Uint8List.fromList(<int>[0x4d, 0x50, 0x00, 0x01]),
        name: 'invalid.litertlm',
      );

      await expectLater(
        TextProofreader.create(
          TextProofreaderOptions(baseOptions: BaseOptions(modelAsset: invalidModel)),
        ),
        throwsA(_nativeFailure('TextProofreader')),
      );
      await expectLater(
        TextSummarizer.create(
          TextSummarizerOptions(baseOptions: BaseOptions(modelAsset: invalidModel)),
        ),
        throwsA(_nativeFailure('TextSummarizer')),
      );
    });

    testWidgets('Android GenAI rejects malformed model bytes through the native SDK', (
      WidgetTester tester,
    ) async {
      if (defaultTargetPlatform != TargetPlatform.android) return;

      final ModelAsset invalidModel = ModelAsset.bytes(
        Uint8List.fromList(<int>[0x4d, 0x50, 0x00, 0x01]),
        name: 'invalid.task',
      );
      await expectLater(
        LlmInference.create(
          LlmInferenceOptions(baseOptions: BaseOptions(modelAsset: invalidModel)),
        ),
        throwsA(_nativeFailure('LlmInference')),
      );
    });

    testWidgets('Android runs a classic text task through the C runtime', (
      WidgetTester tester,
    ) async {
      if (defaultTargetPlatform != TargetPlatform.android) return;

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
  });
}

Matcher _nativeFailure(String task) => isA<MpException>()
    .having((MpException error) => error.status, 'status', isNot(MpStatus.unimplemented))
    .having((MpException error) => error.task, 'task', task);
