// Run with: dart run examples/bin/audio_classification.dart
//
// Classifies a real 16 kHz speech clip with YAMNet, then replays the same clip
// as timestamped chunks through streaming mode to show how a microphone
// pipeline is structured.

import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:mp_audio/mp_audio.dart';
import 'package:mp_core/mp_core.dart';
import 'package:mp_examples/mp_examples.dart';

/// Samples per streamed chunk. YAMNet scores on ~0.975 s windows, so sending
/// roughly 100 ms chunks keeps the timestamp arithmetic readable.
const int _chunkSamples = 1600;

Future<void> main() async {
  final MpAssetCache cache = MpAssetCache.defaults();
  final Uint8List wav = await cache.bytes(MpExampleInputs.speech16k);
  final AudioData audio = mpAudioFromWav(wav);
  stdout.writeln(
    'Clip: ${audio.samples.length} samples at ${audio.sampleRateHz} Hz '
    '(${audio.duration.inMilliseconds} ms)',
  );

  await _classifyClip(cache, audio);
  await _classifyStream(cache, audio);
}

Future<void> _classifyClip(MpAssetCache cache, AudioData audio) async {
  stdout.writeln('\n== Clip classification ==');
  final AudioClassifier classifier = await AudioClassifier.create(
    AudioClassifierOptions(
      baseOptions: BaseOptions(modelAsset: await cache.model(MpExampleModels.audioClassifier)),
      classifierOptions: ClassifierOptions(maxResults: 5, scoreThreshold: 0.05),
    ),
  );
  try {
    final AudioClassifierResult result = await classifier.classify(audio);
    stdout.writeln('Windows classified: ${result.classifications.length}');
    for (final ClassificationResult window in result.classifications) {
      for (final Classifications head in window.classifications) {
        for (final Category category in head.categories) {
          stdout.writeln(
            '  ${category.displayName ?? category.categoryName ?? '#${category.index}'} '
            '${category.score.toStringAsFixed(3)}',
          );
        }
      }
    }
  } finally {
    await classifier.close();
  }
}

Future<void> _classifyStream(MpAssetCache cache, AudioData audio) async {
  stdout.writeln('\n== Stream classification ==');

  // Native audio is clip-only today: MediaPipe's C audio task exposes an async
  // callback that the SDK does not yet bridge, because copying callback-owned
  // memory safely from a native worker thread is not implemented. The task
  // reports that as `MpStatus.unimplemented` instead of silently running in
  // clips mode, so an application can fall back deterministically.
  final AudioClassifier classifier;
  try {
    classifier = await AudioClassifier.create(
      AudioClassifierOptions(
        baseOptions: BaseOptions(modelAsset: await cache.model(MpExampleModels.audioClassifier)),
        runningMode: AudioRunningMode.audioStream,
      ),
    );
  } on MpException catch (error) {
    stdout.writeln('  ${error.status.name}: ${error.message}');
    stdout.writeln('  Fall back to clip mode, or run the browser adapter for streaming.');
    return;
  }

  final StreamSubscription<AudioClassifierResult> subscription = classifier.results.listen((
    AudioClassifierResult result,
  ) {
    final Classifications? head = result.classifications.isEmpty
        ? null
        : result.classifications.first.classifications.firstOrNull;
    final Category? top = head?.categories.firstOrNull;
    stdout.writeln(
      '  t=${result.classifications.firstOrNull?.timestampMs}ms '
      '${top?.displayName ?? top?.categoryName ?? '-'} '
      '${(top?.score ?? 0).toStringAsFixed(3)}',
    );
  }, onError: (Object error) => stderr.writeln('  stream error: $error'));

  try {
    // Timestamps must strictly increase across the whole stream, so the clock
    // advances by the duration of each chunk rather than by wall time.
    var timestampMs = 0;
    for (var offset = 0; offset < audio.samples.length; offset += _chunkSamples) {
      final int end = (offset + _chunkSamples).clamp(0, audio.samples.length);
      await classifier.classifyAsync(
        AudioData(
          samples: Float32List.sublistView(audio.samples, offset, end),
          sampleRateHz: audio.sampleRateHz,
          channelCount: audio.channelCount,
        ),
        timestampMs,
      );
      timestampMs += ((end - offset) * 1000) ~/ audio.sampleRateHz;
    }
    // Give the runtime a moment to publish the last windowed result.
    await Future<void>.delayed(const Duration(milliseconds: 200));
  } finally {
    await subscription.cancel();
    await classifier.close();
  }
}
