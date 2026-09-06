import 'dart:async';
import 'dart:typed_data';

import 'package:mp_core/mp_core.dart';
import 'package:mp_genai/mp_genai.dart';
import 'package:test/test.dart';

void main() {
  late _FakeGenAiRuntime runtime;

  setUp(() => runtime = _FakeGenAiRuntime());

  test('stateless generation streams chunks and cleans up its session', () async {
    final LlmInference inference = await LlmInference.create(
      LlmInferenceOptions(baseOptions: _baseOptions()),
      runtime: runtime,
    );

    final LlmGeneration generation = await inference.generateResponse('Hello');

    expect(await generation.chunks.map((LlmGenerationChunk chunk) => chunk.text).toList(), <String>[
      'Hi',
      ' there',
    ]);
    expect(await generation.response, 'Hi there');
    await Future<void>.delayed(Duration.zero);
    expect(runtime.engine.lastSession?.queries, <String>['Hello']);
    expect(runtime.engine.lastSession?.closeCount, 1);
  });

  test('stateful sessions forward multimodal inputs and clone context', () async {
    final LlmInference inference = await LlmInference.create(
      LlmInferenceOptions(
        baseOptions: _baseOptions(),
        maxNumImages: 1,
        visionModelOptions: const VisionModelOptions(),
      ),
      runtime: runtime,
    );
    final LlmSession session = await inference.createSession();
    final Uint8List audio = Uint8List.fromList(<int>[82, 73, 70, 70]);

    await session.addImage(_image());
    await session.addAudio(audio);
    audio[0] = 0;
    final LlmSession cloned = await session.clone();

    expect(runtime.engine.lastSession?.images, hasLength(1));
    expect(runtime.engine.lastSession?.audio.single.first, 82);
    expect(cloned.options.topK, 40);
  });

  test('engine and session options are validated', () async {
    expect(
      () => LlmInferenceOptions(baseOptions: _baseOptions(), maxTokens: 0),
      throwsArgumentError,
    );
    expect(
      () => LlmInferenceOptions(baseOptions: _baseOptions(), maxNumImages: 1),
      throwsArgumentError,
    );
    expect(() => LlmSessionOptions(topP: 0), throwsArgumentError);

    final LlmInference inference = await LlmInference.create(
      LlmInferenceOptions(baseOptions: _baseOptions(), maxTopK: 4),
      runtime: runtime,
    );
    await expectLater(
      inference.createSession(options: LlmSessionOptions(topK: 5)),
      throwsArgumentError,
    );
  });

  test('close is idempotent', () async {
    final LlmInference inference = await LlmInference.create(
      LlmInferenceOptions(baseOptions: _baseOptions()),
      runtime: runtime,
    );
    await inference.close();
    await inference.close();

    expect(runtime.engine.closeCount, 1);
    expect(() => inference.sizeInTokens('closed'), throwsA(isA<MpTaskClosedError>()));
  });
}

BaseOptions _baseOptions() => BaseOptions(modelAsset: ModelAsset.path('model.task'));

MpImage _image() => MpImage.uint8(
  width: 1,
  height: 1,
  format: MpImageFormat.srgb,
  data: Uint8List.fromList(<int>[0, 0, 0]),
);

final class _FakeGenAiRuntime implements GenAiRuntime {
  final _FakeInferenceBackend engine = _FakeInferenceBackend();

  @override
  Future<LlmInferenceBackend> createLlmInference(LlmInferenceOptions options) async => engine;
}

final class _FakeInferenceBackend implements LlmInferenceBackend {
  _FakeSessionBackend? lastSession;
  int closeCount = 0;

  @override
  bool get isClosed => closeCount > 0;

  @override
  Future<LlmSessionBackend> createSession(LlmSessionOptions options) async =>
      lastSession = _FakeSessionBackend();

  @override
  Future<int> sizeInTokens(String text) async => text.split(' ').length;

  @override
  Future<void> close() async => closeCount++;
}

final class _FakeSessionBackend implements LlmSessionBackend {
  final List<String> queries = <String>[];
  final List<MpImage> images = <MpImage>[];
  final List<Uint8List> audio = <Uint8List>[];
  int closeCount = 0;

  @override
  bool get isClosed => closeCount > 0;

  @override
  Future<void> addQueryChunk(String text) async => queries.add(text);

  @override
  Future<void> addImage(MpImage image) async => images.add(image);

  @override
  Future<void> addAudio(Uint8List wavBytes) async => audio.add(Uint8List.fromList(wavBytes));

  @override
  Future<LlmGeneration> generate() async {
    final Stream<LlmGenerationChunk> chunks = Stream<LlmGenerationChunk>.fromIterable(
      const <LlmGenerationChunk>[
        LlmGenerationChunk(text: 'Hi', isDone: false),
        LlmGenerationChunk(text: ' there', isDone: true),
      ],
    );
    return LlmGeneration(
      chunks: chunks,
      response: Future<String>.value('Hi there'),
      cancel: _cancel,
    );
  }

  Future<void> _cancel() async {}

  @override
  Future<int> sizeInTokens(String text) async => text.split(' ').length;

  @override
  Future<LlmSessionBackend> clone() async {
    final _FakeSessionBackend clone = _FakeSessionBackend();
    clone.queries.addAll(queries);
    clone.images.addAll(images);
    clone.audio.addAll(audio.map(Uint8List.fromList));
    return clone;
  }

  @override
  Future<void> updateOptions(LlmSessionOptions options) async {}

  @override
  Future<void> close() async => closeCount++;
}
