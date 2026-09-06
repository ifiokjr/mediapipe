import 'dart:typed_data';

import 'package:mp_core/mp_core.dart';
import 'package:mp_genai/mp_genai.dart';
import 'package:test/test.dart';

void main() {
  test('forwards one-shot and incremental generation', () async {
    final _FakeImageRuntime runtime = _FakeImageRuntime();
    final ImageGenerator generator = await ImageGenerator.create(
      ImageGeneratorOptions(modelDirectory: '/models/diffusion'),
      runtime: runtime,
    );
    final ImageGeneratorCondition condition = ImageGeneratorCondition(
      image: _image(),
      type: ImageGeneratorConditionType.edge,
    );

    final ImageGeneratorResult generated = await generator.generate(
      'a line drawing',
      iterations: 20,
      seed: 4,
      condition: condition,
    );
    await generator.setInputs('a second drawing', iterations: 10, seed: 8);
    final ImageGeneratorResult? executed = await generator.execute(showResult: false);
    final MpImage processed = await generator.createConditionImage(
      _image(),
      ImageGeneratorConditionType.depth,
    );

    expect(generated.timestamp, const Duration(milliseconds: 7));
    expect(executed?.generatedImage, _image());
    expect(processed, _image());
    expect(runtime.backend.lastPrompt, 'a second drawing');
    expect(runtime.backend.lastIterations, 10);
    expect(runtime.backend.lastSeed, 8);
    expect(runtime.backend.lastCondition?.type, ImageGeneratorConditionType.edge);
    expect(runtime.backend.showResult, isFalse);
    expect(runtime.backend.conditionType, ImageGeneratorConditionType.depth);
  });

  test('validates options and generation inputs', () async {
    expect(() => ImageGeneratorOptions(modelDirectory: ' '), throwsArgumentError);
    expect(ImageGeneratorConditionOptions.new, throwsArgumentError);
    expect(
      () => EdgeConditionOptions(pluginModel: _baseOptions(), threshold1: 2, threshold2: 1),
      throwsArgumentError,
    );
    expect(
      () => FaceConditionOptions(
        pluginModel: _baseOptions(),
        faceModel: _baseOptions(),
        minFaceDetectionConfidence: 2,
      ),
      throwsArgumentError,
    );

    final ImageGenerator generator = await ImageGenerator.create(
      ImageGeneratorOptions(modelDirectory: '/models/diffusion'),
      runtime: _FakeImageRuntime(),
    );
    expect(() => generator.generate('', iterations: 1, seed: 0), throwsArgumentError);
    expect(() => generator.generate('valid', iterations: 0, seed: 0), throwsArgumentError);
  });

  test('close is idempotent and guards later work', () async {
    final _FakeImageRuntime runtime = _FakeImageRuntime();
    final ImageGenerator generator = await ImageGenerator.create(
      ImageGeneratorOptions(modelDirectory: '/models/diffusion'),
      runtime: runtime,
    );

    await generator.close();
    await generator.close();

    expect(runtime.backend.closeCount, 1);
    expect(generator.execute, throwsA(isA<MpTaskClosedError>()));
  });
}

BaseOptions _baseOptions() => BaseOptions(modelAsset: ModelAsset.path('/models/control.task'));

MpImage _image() => MpImage.uint8(
  width: 1,
  height: 1,
  format: MpImageFormat.srgba,
  data: Uint8List.fromList(<int>[1, 2, 3, 255]),
);

final class _FakeImageRuntime implements GenAiRuntime {
  final _FakeImageBackend backend = _FakeImageBackend();

  @override
  Future<FunctionCallingBackend> createGenerativeModel(GenerativeModelOptions options) =>
      throw UnimplementedError();

  @override
  Future<ImageGeneratorBackend> createImageGenerator(ImageGeneratorOptions options) async =>
      backend;

  @override
  Future<LlmInferenceBackend> createLlmInference(LlmInferenceOptions options) =>
      throw UnimplementedError();

  @override
  Future<RagPipelineBackend> createRagPipeline(RagPipelineOptions options) =>
      throw UnimplementedError();
}

final class _FakeImageBackend implements ImageGeneratorBackend {
  String? lastPrompt;
  int? lastIterations;
  int? lastSeed;
  ImageGeneratorCondition? lastCondition;
  bool? showResult;
  ImageGeneratorConditionType? conditionType;
  int closeCount = 0;

  @override
  bool get isClosed => closeCount > 0;

  @override
  Future<ImageGeneratorResult> generate(
    String prompt, {
    required int iterations,
    required int seed,
    ImageGeneratorCondition? condition,
  }) async {
    lastPrompt = prompt;
    lastIterations = iterations;
    lastSeed = seed;
    lastCondition = condition;
    return _result();
  }

  @override
  Future<void> setInputs(
    String prompt, {
    required int iterations,
    required int seed,
    ImageGeneratorCondition? condition,
  }) async {
    lastPrompt = prompt;
    lastIterations = iterations;
    lastSeed = seed;
  }

  @override
  Future<ImageGeneratorResult?> execute({required bool showResult}) async {
    this.showResult = showResult;
    return _result();
  }

  @override
  Future<MpImage> createConditionImage(MpImage image, ImageGeneratorConditionType type) async {
    conditionType = type;
    return image;
  }

  @override
  Future<void> close() async => closeCount++;
}

ImageGeneratorResult _result() =>
    ImageGeneratorResult(generatedImage: _image(), timestamp: const Duration(milliseconds: 7));
