import 'package:mp_core/mp_core.dart';
import 'package:mp_genai/mp_genai.dart';
import 'package:test/test.dart';

void main() {
  test('forwards structured requests and chat operations', () async {
    final _FakeFunctionRuntime runtime = _FakeFunctionRuntime();
    final GenerativeModel model = await GenerativeModel.create(
      GenerativeModelOptions(
        inferenceOptions: LlmInferenceOptions(baseOptions: _baseOptions()),
        tools: <FunctionTool>[
          FunctionTool(<FunctionDeclaration>[
            FunctionDeclaration(
              name: 'verify_action',
              description: 'Records an on-device verification signal.',
              parameters: FunctionSchema(
                type: FunctionSchemaType.object,
                properties: <String, FunctionSchema>{
                  'confidence': FunctionSchema(type: FunctionSchemaType.number),
                },
                requiredProperties: const <String>['confidence'],
              ),
            ),
          ]),
        ],
      ),
      runtime: runtime,
    );

    final GenerateContentResponse response = await model.generateContent(<GenAiContent>[
      GenAiContent.text(role: 'user', text: 'Check this action'),
    ]);
    final FunctionCallingChat chat = await model.startChat();
    await chat.sendText('Check another action');
    final List<GenAiContent> history = await chat.history();
    final GenAiContent last = await chat.last();
    final ChatRewindResult rewind = await chat.rewind();
    final FunctionCallingChat clone = await chat.clone();
    await chat.enableConstraint(const ToolCallOnlyConstraint(prefix: '<tool>'));
    await chat.disableConstraint();

    final GenAiFunctionCallPart call =
        response.candidates.single.content.parts.single as GenAiFunctionCallPart;
    expect(call.call.name, 'verify_action');
    expect(call.call.arguments, <String, Object?>{'confidence': 0.8});
    expect(history, hasLength(2));
    expect(last.role, 'model');
    expect(rewind.lastSent.role, 'user');
    expect(clone.isClosed, isFalse);
    expect(runtime.backend.chat.constraint, isNull);
  });

  test('validates schemas, tools, and JSON function data', () {
    expect(() => FunctionSchema(type: FunctionSchemaType.array), throwsArgumentError);
    expect(
      () => FunctionSchema(
        type: FunctionSchemaType.object,
        requiredProperties: const <String>['missing'],
      ),
      throwsArgumentError,
    );
    final FunctionDeclaration declaration = FunctionDeclaration(
      name: 'lookup',
      description: 'Looks up a value.',
    );
    expect(
      () => FunctionTool(<FunctionDeclaration>[declaration, declaration]),
      throwsArgumentError,
    );
    expect(
      () => FunctionCall(name: 'lookup', arguments: <String, Object?>{'bad': Object()}),
      throwsArgumentError,
    );
  });

  test('copies JSON function data and guards closed models', () async {
    final List<Object?> values = <Object?>[1];
    final FunctionCall call = FunctionCall(
      name: 'lookup',
      arguments: <String, Object?>{'values': values},
    );
    values.add(2);
    expect(call.arguments['values'], <Object?>[1]);

    final _FakeFunctionRuntime runtime = _FakeFunctionRuntime();
    final GenerativeModel model = await GenerativeModel.create(
      GenerativeModelOptions(inferenceOptions: LlmInferenceOptions(baseOptions: _baseOptions())),
      runtime: runtime,
    );
    await model.close();
    await model.close();

    expect(runtime.backend.closeCount, 1);
    expect(model.startChat, throwsA(isA<MpTaskClosedError>()));
  });
}

BaseOptions _baseOptions() => BaseOptions(modelAsset: ModelAsset.path('/models/model.task'));

GenerateContentResponse _response() => GenerateContentResponse(<GenAiCandidate>[
  GenAiCandidate(
    GenAiContent(
      role: 'model',
      parts: <GenAiPart>[
        GenAiFunctionCallPart(
          FunctionCall(name: 'verify_action', arguments: <String, Object?>{'confidence': 0.8}),
        ),
      ],
    ),
  ),
]);

final class _FakeFunctionRuntime implements GenAiRuntime {
  final _FakeFunctionBackend backend = _FakeFunctionBackend();

  @override
  Future<FunctionCallingBackend> createGenerativeModel(GenerativeModelOptions options) async =>
      backend;

  @override
  Future<ImageGeneratorBackend> createImageGenerator(ImageGeneratorOptions options) =>
      throw UnimplementedError();

  @override
  Future<LlmInferenceBackend> createLlmInference(LlmInferenceOptions options) =>
      throw UnimplementedError();

  @override
  Future<RagPipelineBackend> createRagPipeline(RagPipelineOptions options) =>
      throw UnimplementedError();
}

final class _FakeFunctionBackend implements FunctionCallingBackend {
  final _FakeChatBackend chat = _FakeChatBackend();
  int closeCount = 0;

  @override
  bool get isClosed => closeCount > 0;

  @override
  Future<GenerateContentResponse> generateContent(List<GenAiContent> contents) async => _response();

  @override
  Future<FunctionCallingChatBackend> startChat() async => chat;

  @override
  Future<void> close() async => closeCount++;
}

final class _FakeChatBackend implements FunctionCallingChatBackend {
  final List<GenAiContent> entries = <GenAiContent>[
    GenAiContent.text(role: 'user', text: 'first'),
    GenAiContent.text(role: 'model', text: 'second'),
  ];
  FunctionCallingConstraint? constraint;
  bool closed = false;

  @override
  bool get isClosed => closed;

  @override
  Future<GenerateContentResponse> sendMessage(GenAiContent content) async => _response();

  @override
  Future<ChatRewindResult> rewind() async =>
      ChatRewindResult(lastSent: entries.first, lastReceived: entries.last);

  @override
  Future<List<GenAiContent>> history() async => List<GenAiContent>.unmodifiable(entries);

  @override
  Future<GenAiContent> last() async => entries.last;

  @override
  Future<FunctionCallingChatBackend> clone() async => _FakeChatBackend();

  @override
  Future<void> enableConstraint(FunctionCallingConstraint constraint) async {
    this.constraint = constraint;
  }

  @override
  Future<void> disableConstraint() async => constraint = null;

  @override
  Future<void> close() async => closed = true;
}
