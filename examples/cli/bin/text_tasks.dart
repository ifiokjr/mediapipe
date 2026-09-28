// Run with: dart run examples/bin/text_tasks.dart
//
// Runs all three text tasks that have a C and browser backend: language
// detection, text classification via embeddings, and text embedding. The
// example also shows how to compare embeddings with `cosineSimilarity` instead
// of reimplementing the metric.

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

  await _detectLanguages(cache);
  await _embed(cache);
}

Future<void> _detectLanguages(MpAssetCache cache) async {
  stdout.writeln('== Language detection ==');
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
        '  ${top?.languageCode ?? '??'} '
        'p=${(top?.probability ?? 0).toStringAsFixed(3)}  $sample',
      );
    }
  } finally {
    await detector.close();
  }
}

Future<void> _embed(MpAssetCache cache) async {
  stdout.writeln('\n== Text embedding ==');
  final TextEmbedder embedder = await TextEmbedder.create(
    TextEmbedderOptions(
      baseOptions: BaseOptions(modelAsset: await cache.model(MpExampleModels.textEmbedderQa)),
      embedderOptions: const EmbedderOptions(l2Normalize: true),
    ),
  );
  try {
    final List<String> sentences = <String>[
      'A person is riding a bicycle.',
      'Someone is cycling down the street.',
      'The stock market fell sharply today.',
    ];
    final List<Embedding> embeddings = <Embedding>[];
    for (final String sentence in sentences) {
      final EmbeddingResult result = await embedder.embed(sentence);
      embeddings.add(result.embeddings.first);
      stdout.writeln('  ${result.embeddings.first.length} dimensions  "$sentence"');
    }

    // The first two sentences are paraphrases, so they should score higher than
    // either does against the unrelated financial sentence.
    stdout.writeln(
      '  similarity(0, 1) = ${cosineSimilarity(embeddings[0], embeddings[1]).toStringAsFixed(4)}',
    );
    stdout.writeln(
      '  similarity(0, 2) = ${cosineSimilarity(embeddings[0], embeddings[2]).toStringAsFixed(4)}',
    );
  } finally {
    await embedder.close();
  }
}
