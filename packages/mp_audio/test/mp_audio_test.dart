import 'dart:async';
import 'dart:typed_data';

import 'package:mp_audio/mp_audio.dart';
import 'package:mp_core/mp_core.dart';
import 'package:test/test.dart';

void main() {
  late _FakeAudioRuntime runtime;

  setUp(() => runtime = _FakeAudioRuntime());

  test('classifies independent clips', () async {
    final AudioClassifier classifier = await AudioClassifier.create(
      AudioClassifierOptions(baseOptions: _baseOptions()),
      runtime: runtime,
    );

    final AudioClassifierResult result = await classifier.classify(_audio());

    expect(result.classifications.single.timestampMs, 12);
    expect(runtime.backend.classifyCount, 1);
    expect(() => classifier.classifyAsync(_audio(), 0), throwsStateError);
    await classifier.close();
  });

  test('validates and forwards streaming timestamps', () async {
    final AudioClassifier classifier = await AudioClassifier.create(
      AudioClassifierOptions(
        baseOptions: _baseOptions(),
        runningMode: AudioRunningMode.audioStream,
      ),
      runtime: runtime,
    );

    final Future<AudioClassifierResult> nextResult = classifier.results.first;
    await classifier.classifyAsync(_audio(), 5);
    runtime.backend.controller.add(AudioClassifierResult(const <ClassificationResult>[]));

    expect(await nextResult, AudioClassifierResult(const <ClassificationResult>[]));
    expect(runtime.backend.timestamps, <int>[5]);
    expect(() => classifier.classifyAsync(_audio(), 5), throwsArgumentError);
    expect(() => classifier.classify(_audio()), throwsStateError);
    await classifier.close();
  });

  test('close is idempotent and seals the public task', () async {
    final AudioClassifier classifier = await AudioClassifier.create(
      AudioClassifierOptions(baseOptions: _baseOptions()),
      runtime: runtime,
    );

    await classifier.close();
    await classifier.close();

    expect(runtime.backend.closeCount, 1);
    expect(() => classifier.classify(_audio()), throwsA(isA<MpTaskClosedError>()));
  });
}

BaseOptions _baseOptions() => BaseOptions(modelAsset: ModelAsset.path('model.tflite'));

AudioData _audio() => AudioData(
  channelCount: 1,
  sampleRateHz: 16_000,
  samples: Float32List.fromList(<double>[0, 0.1]),
);

final class _FakeAudioRuntime implements AudioRuntime {
  final _FakeAudioClassifier backend = _FakeAudioClassifier();

  @override
  Future<AudioClassifierBackend> createAudioClassifier(AudioClassifierOptions options) async =>
      backend;
}

final class _FakeAudioClassifier implements AudioClassifierBackend {
  final StreamController<AudioClassifierResult> controller =
      StreamController<AudioClassifierResult>.broadcast();
  final List<int> timestamps = <int>[];
  int classifyCount = 0;
  int closeCount = 0;

  @override
  bool get isClosed => closeCount > 0;

  @override
  Stream<AudioClassifierResult> get results => controller.stream;

  @override
  Future<AudioClassifierResult> classify(AudioData audio) async {
    classifyCount++;
    return AudioClassifierResult(<ClassificationResult>[
      ClassificationResult(classifications: const <Classifications>[], timestampMs: 12),
    ]);
  }

  @override
  Future<void> classifyAsync(AudioData audio, int timestampMs) async => timestamps.add(timestampMs);

  @override
  Future<void> close() async {
    closeCount++;
    await controller.close();
  }
}
