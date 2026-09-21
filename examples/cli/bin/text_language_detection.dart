// Run with: dart run examples/bin/text_language_detection.dart
//
// Detects the language of several strings with the MediaPipe language detector,
// then classifies and embeds text to show the three classic text tasks working
// through one runtime.

import 'dart:io';

import 'package:mp_core/mp_core.dart';
import 'package:mp_examples/mp_examples.dart';
import 'package:mp_text/mp_text.dart';

const List<String> _samples = <String>[
  'This sentence is written in English.',
  'Bonjour tout le monde, comment allez-vous ?',
  'Guten Tag, wie geht es Ihnen heute?',
  'こんにちは、今日はいい天気ですね。',
];

Future<void> main() async {
  final MpAssetCache cache = MpAssetCache.defaults();

  final LanguageDetector detector = await LanguageDetector.create(
    LanguageDetectorOptions(
      baseOptions: BaseOptions(modelAsset: await cache.model(MpExampleModels.languageDetector)),
    ),
  );

  try {
    for (final String sample in _samples) {
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
}
