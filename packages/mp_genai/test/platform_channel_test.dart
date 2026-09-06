import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mp_core/mp_core.dart';
import 'package:mp_genai/mp_genai.dart';
import 'package:mp_genai/src/platform_channel_flutter.dart';

const MethodChannel _methods = MethodChannel('dev.ifiokjr.mp_genai/methods');
const MethodChannel _events = MethodChannel('dev.ifiokjr.mp_genai/events');

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final TestDefaultBinaryMessenger messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  final List<MethodCall> calls = <MethodCall>[];
  String? materializedModelPath;

  setUp(() {
    calls.clear();
    materializedModelPath = null;
    messenger.setMockMethodCallHandler(_events, (MethodCall call) async => null);
    messenger.setMockMethodCallHandler(_methods, (MethodCall call) async {
      calls.add(call);
      final Map<Object?, Object?> arguments = call.arguments! as Map<Object?, Object?>;
      switch (call.method) {
        case 'llm.create':
          materializedModelPath = arguments['modelPath']! as String;
          expect(File(materializedModelPath!).existsSync(), isTrue);
          return 1;
        case 'llm.createSession':
          return 2;
        case 'llm.addQuery':
          return null;
        case 'llm.generate':
          final String requestId = arguments['requestId']! as String;
          unawaited(
            Future<void>(() async {
              await _sendEvent(messenger, <String, Object?>{
                'kind': 'data',
                'requestId': requestId,
                'text': 'local ',
                'isDone': false,
              });
              await _sendEvent(messenger, <String, Object?>{
                'kind': 'data',
                'requestId': requestId,
                'text': 'response',
                'isDone': true,
              });
              await _sendEvent(messenger, <String, Object?>{
                'kind': 'done',
                'requestId': requestId,
              });
            }),
          );
          return null;
        case 'llm.closeSession':
        case 'llm.close':
          return null;
        case 'functionCalling.create':
          return 10;
        case 'functionCalling.generateContent':
          return <String, Object?>{
            'candidates': <Object?>[
              <String, Object?>{
                'role': 'model',
                'parts': <Object?>[
                  <String, Object?>{
                    'kind': 'functionCall',
                    'name': 'verify_action',
                    'value': <String, Object?>{
                      'confidence': 0.8,
                      'labels': <Object?>['person', 'door'],
                    },
                  },
                ],
              },
            ],
          };
        case 'functionCalling.close':
          return null;
        case 'imageGenerator.create':
          return 20;
        case 'imageGenerator.generate':
          return <String, Object?>{
            'generatedImage': <String, Object?>{
              'width': 1,
              'height': 1,
              'data': Uint8List.fromList(<int>[1, 2, 3, 255]),
            },
            'timestampMs': 17,
          };
        case 'imageGenerator.close':
          return null;
        case 'rag.create':
          return 30;
        case 'rag.record':
          return true;
        case 'rag.retrieve':
          return <Object?>[
            <String, Object?>{
              'text': 'Recorded evidence',
              'embedding': <Object?>[0.25, 0.75],
              'metadata': <String, Object?>{'frame': 42},
            },
          ];
        case 'rag.close':
          return null;
      }
      throw PlatformException(code: 'unimplemented', message: call.method);
    });
  });

  tearDown(() {
    messenger.setMockMethodCallHandler(_methods, null);
    messenger.setMockMethodCallHandler(_events, null);
  });

  test('LLM bridge materializes bytes, streams chunks, and releases the model', () async {
    final LlmInference inference = await LlmInference.create(
      LlmInferenceOptions(
        baseOptions: BaseOptions(
          modelAsset: ModelAsset.bytes(Uint8List.fromList(<int>[1, 2, 3]), name: '../model.task'),
        ),
        maxTokens: 256,
        maxTopK: 16,
        supportedLoraRanks: const <int>[4, 8],
        preferredBackend: LlmBackend.gpu,
      ),
      runtime: const MobileGenAiRuntime(),
    );
    final LlmSession session = await inference.createSession(
      options: LlmSessionOptions(topK: 8, temperature: 0.5),
    );
    await session.addQueryChunk('Describe the frame.');

    final LlmGeneration generation = await session.generate();
    final List<LlmGenerationChunk> chunks = await generation.chunks.toList();

    expect(chunks.map((LlmGenerationChunk chunk) => chunk.text), <String>['local ', 'response']);
    expect(await generation.response, 'local response');
    await session.close();
    await inference.close();

    final Map<Object?, Object?> createArguments = _argumentsFor(calls, 'llm.create');
    expect(createArguments['maxTokens'], 256);
    expect(createArguments['supportedLoraRanks'], <int>[4, 8]);
    expect(createArguments['preferredBackend'], 'gpu');
    expect(File(materializedModelPath!).existsSync(), isFalse);
    expect(
      calls.map((MethodCall call) => call.method),
      containsAllInOrder(<String>[
        'llm.create',
        'llm.createSession',
        'llm.addQuery',
        'llm.generate',
        'llm.closeSession',
        'llm.close',
      ]),
    );
  });

  test('function-calling bridge maps tools and structured responses', () async {
    final File model = _temporaryFile('mp_genai_function_', 'model.task');
    final GenerativeModel generativeModel = await GenerativeModel.create(
      GenerativeModelOptions(
        inferenceOptions: _inferenceOptions(model),
        formatter: FunctionCallingFormatter.hammer,
        tools: <FunctionTool>[
          FunctionTool(<FunctionDeclaration>[
            FunctionDeclaration(
              name: 'verify_action',
              description: 'Classify local evidence.',
              parameters: FunctionSchema(
                type: FunctionSchemaType.object,
                properties: <String, FunctionSchema>{
                  'frame': FunctionSchema(type: FunctionSchemaType.integer),
                },
                requiredProperties: const <String>['frame'],
              ),
            ),
          ]),
        ],
      ),
      runtime: const MobileGenAiRuntime(),
    );

    final GenerateContentResponse response = await generativeModel.generateContent(<GenAiContent>[
      GenAiContent.text(role: 'user', text: 'Check this action.'),
    ]);
    await generativeModel.close();

    final GenAiFunctionCallPart part =
        response.candidates.single.content.parts.single as GenAiFunctionCallPart;
    expect(part.call.name, 'verify_action');
    expect(part.call.arguments['confidence'], 0.8);
    expect(part.call.arguments['labels'], <Object?>['person', 'door']);
    final Map<Object?, Object?> createArguments = _argumentsFor(calls, 'functionCalling.create');
    expect(createArguments['formatter'], 'hammer');
    final List<Object?> tools = createArguments['tools']! as List<Object?>;
    final Map<Object?, Object?> tool = tools.single as Map<Object?, Object?>;
    final List<Object?> declarations = tool['declarations']! as List<Object?>;
    expect((declarations.single as Map<Object?, Object?>)['name'], 'verify_action');
  });

  test('image bridge converts generated pixels and timestamps', () async {
    final Directory modelDirectory = Directory.systemTemp.createTempSync('mp_genai_image_');
    addTearDown(() => modelDirectory.deleteSync(recursive: true));
    final ImageGenerator generator = await ImageGenerator.create(
      ImageGeneratorOptions(modelDirectory: modelDirectory.path),
      runtime: const MobileGenAiRuntime(),
    );

    final ImageGeneratorResult result = await generator.generate(
      'A test image',
      iterations: 2,
      seed: 7,
    );
    await generator.close();

    expect(result.generatedImage, isA<MpImageUint8>());
    expect((result.generatedImage as MpImageUint8).data, <int>[1, 2, 3, 255]);
    expect(result.timestamp, const Duration(milliseconds: 17));
    final Map<Object?, Object?> arguments = _argumentsFor(calls, 'imageGenerator.generate');
    expect(arguments['iterations'], 2);
    expect(arguments['seed'], 7);
  });

  test('RAG bridge maps records, retrieval options, and entities', () async {
    final File llmModel = _temporaryFile('mp_genai_rag_llm_', 'model.task');
    final File embeddingModel = _temporaryFile('mp_genai_rag_embedding_', 'embed.tflite');
    final RagPipeline pipeline = await RagPipeline.create(
      RagPipelineOptions(
        embeddingModel: GeckoEmbeddingModelOptions(model: ModelAsset.path(embeddingModel.path)),
        vectorStore: const InMemoryVectorStoreOptions(),
        inferenceOptions: _inferenceOptions(llmModel),
        promptTemplate: 'Context: {0}\nQuery: {1}',
      ),
      runtime: const MobileGenAiRuntime(),
    );

    expect(
      await pipeline.record(
        RagDocument(text: 'Recorded evidence', metadata: <String, Object?>{'frame': 42}),
      ),
      isTrue,
    );
    final List<RagRetrievalEntity> results = await pipeline.retrieve(
      'What happened?',
      options: RagRetrievalOptions(
        topK: 3,
        minSimilarityScore: 0.4,
        task: RagRetrievalTask.factVerification,
      ),
    );
    await pipeline.close();

    expect(results.single.text, 'Recorded evidence');
    expect(results.single.embedding, <double>[0.25, 0.75]);
    expect(results.single.metadata['frame'], 42);
    final Map<Object?, Object?> retrieveArguments = _argumentsFor(calls, 'rag.retrieve');
    expect(retrieveArguments['topK'], 3);
    expect(retrieveArguments['minSimilarityScore'], 0.4);
    expect(retrieveArguments['task'], 'factVerification');
  });
}

LlmInferenceOptions _inferenceOptions(File model) =>
    LlmInferenceOptions(baseOptions: BaseOptions(modelAsset: ModelAsset.path(model.path)));

File _temporaryFile(String prefix, String name) {
  final Directory directory = Directory.systemTemp.createTempSync(prefix);
  addTearDown(() => directory.deleteSync(recursive: true));
  return File('${directory.path}${Platform.pathSeparator}$name')..writeAsBytesSync(<int>[1]);
}

Map<Object?, Object?> _argumentsFor(List<MethodCall> calls, String method) =>
    calls.singleWhere((MethodCall call) => call.method == method).arguments!
        as Map<Object?, Object?>;

Future<void> _sendEvent(TestDefaultBinaryMessenger messenger, Map<String, Object?> event) async {
  await messenger.handlePlatformMessage(
    _events.name,
    const StandardMethodCodec().encodeSuccessEnvelope(event),
    null,
  );
}
