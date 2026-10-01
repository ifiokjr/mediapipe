import 'package:mp_core/mp_core.dart';

import 'text_proofreader.dart';
import 'text_summarizer.dart';

/// Reports that proofreading needs the Android or iOS Flutter plugin.
Future<TextProofreaderBackend> createPlatformTextProofreader(
  TextProofreaderOptions options,
) async => throw const MpException(
  MpStatus.unimplemented,
  'TextProofreader requires the mp_text Android or iOS Flutter plugin.',
  task: 'TextProofreader',
);

/// Reports that summarization needs the Android or iOS Flutter plugin.
Future<TextSummarizerBackend> createPlatformTextSummarizer(TextSummarizerOptions options) async =>
    throw const MpException(
      MpStatus.unimplemented,
      'TextSummarizer requires the mp_text Android or iOS Flutter plugin.',
      task: 'TextSummarizer',
    );
