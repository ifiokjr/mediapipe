// Run with: dart run examples/cli/bin/text_language_detection.dart
//
// Detects the language of several strings with the MediaPipe language detector.
// The model is downloaded once, cached, and verified against its pinned
// SHA-256 digest before inference.

import 'dart:io';

import 'package:mp_core/mp_core.dart';
import 'package:mp_examples/mp_examples.dart';
import 'package:mp_text/mp_text.dart';

Future<void> main() => runExample('text_language_detection', () async {
  final MpAssetCache cache = MpAssetCache.defaults();

  final LanguageDetector detector = await LanguageDetector.create(
    LanguageDetectorOptions(
      baseOptions: BaseOptions(modelAsset: await cache.model(MpExampleModels.languageDetector)),
    ),
  );

  try {
    for (final String sample in sampleSentences) {
      final LanguageDetectorResult result = await detector.detect(sample);
      final LanguagePrediction? top = result.topPrediction;
      stdout.writeln(
        '${top?.languageCode ?? '??'} '
        '(${(top?.probability ?? 0).toStringAsFixed(3)})  $sample',
      );
    }
  } finally {
    await detector.close();
  }
});
