import 'package:mp_core/mp_core.dart';
import 'package:mp_genai/mp_genai.dart';
import 'package:test/test.dart';

void main() {
  test('records, retrieves, and generates through the backend', () async {
    final _FakeRagRuntime runtime = _FakeRagRuntime();
    final RagPipeline pipeline = await RagPipeline.create(_options(), runtime: runtime);
    final RagDocument document = RagDocument(
      text: 'A local action signal.',
      metadata: <String, Object?>{'source': 'camera'},
      embeddingText: 'action signal',
    );

    expect(await pipeline.record(document), isTrue);
    expect(await pipeline.recordAll(<RagDocument>[document]), isTrue);
    final List<RagRetrievalEntity> retrieved = await pipeline.retrieve(
      'Was the action observed?',
      options: RagRetrievalOptions(topK: 2, minSimilarityScore: 0.5),
    );
    expect(await pipeline.generate('Was the action observed?'), 'Observed locally.');
    expect(
      await pipeline
          .generateStreaming('Was the action observed?')
          .map((RagGenerationChunk chunk) => chunk.text)
          .join(),
      'Observed locally.',
    );

    expect(retrieved.single.text, document.text);
    expect(retrieved.single.embedding, <double>[0.2, 0.8]);
    expect(runtime.backend.lastOptions?.topK, 5);
    expect(runtime.backend.documents, hasLength(2));
  });

  test('validates storage and retrieval options', () {
    expect(
      () => SqliteVectorStoreOptions(embeddingDimensions: 0, databasePath: 'memory.db'),
      throwsArgumentError,
    );
    expect(
      () => RagSqliteColumn(name: 'id', sqlType: 'INTEGER', autoIncrement: true),
      throwsArgumentError,
    );
    expect(() => RagRetrievalOptions(topK: 0), throwsArgumentError);
    expect(() => RagRetrievalOptions(minSimilarityScore: 2), throwsArgumentError);
  });

  test('copies metadata and guards a closed pipeline', () async {
    final List<Object?> tags = <Object?>['local'];
    final RagDocument document = RagDocument(
      text: 'Evidence',
      metadata: <String, Object?>{'tags': tags},
    );
    tags.add('mutated');
    expect(document.metadata['tags'], <Object?>['local']);

    final _FakeRagRuntime runtime = _FakeRagRuntime();
    final RagPipeline pipeline = await RagPipeline.create(_options(), runtime: runtime);
    await pipeline.close();
    await pipeline.close();

    expect(runtime.backend.closeCount, 1);
    expect(() => pipeline.retrieve('query'), throwsA(isA<MpTaskClosedError>()));
  });
}

RagPipelineOptions _options() => RagPipelineOptions(
  embeddingModel: GeckoEmbeddingModelOptions(model: ModelAsset.path('/models/embedder.tflite')),
  vectorStore: const InMemoryVectorStoreOptions(),
  inferenceOptions: LlmInferenceOptions(
    baseOptions: BaseOptions(modelAsset: ModelAsset.path('/models/model.task')),
  ),
  promptTemplate: 'Context: %s\nQuestion: %s',
);

final class _FakeRagRuntime implements GenAiRuntime {
  final _FakeRagBackend backend = _FakeRagBackend();

  @override
  Future<RagPipelineBackend> createRagPipeline(RagPipelineOptions options) async => backend;

  @override
  Future<FunctionCallingBackend> createGenerativeModel(GenerativeModelOptions options) =>
      throw UnimplementedError();

  @override
  Future<ImageGeneratorBackend> createImageGenerator(ImageGeneratorOptions options) =>
      throw UnimplementedError();

  @override
  Future<LlmInferenceBackend> createLlmInference(LlmInferenceOptions options) =>
      throw UnimplementedError();
}

final class _FakeRagBackend implements RagPipelineBackend {
  final List<RagDocument> documents = <RagDocument>[];
  RagRetrievalOptions? lastOptions;
  int closeCount = 0;

  @override
  bool get isClosed => closeCount > 0;

  @override
  Future<bool> record(RagDocument document) async {
    documents.add(document);
    return true;
  }

  @override
  Future<bool> recordAll(List<RagDocument> documents) async {
    this.documents.addAll(documents);
    return true;
  }

  @override
  Future<List<RagRetrievalEntity>> retrieve(String query, RagRetrievalOptions options) async {
    lastOptions = options;
    return <RagRetrievalEntity>[
      RagRetrievalEntity(
        text: documents.first.text,
        embedding: const <double>[0.2, 0.8],
        metadata: documents.first.metadata,
      ),
    ];
  }

  @override
  Future<String> generate(String query, RagRetrievalOptions options) async {
    lastOptions = options;
    return 'Observed locally.';
  }

  @override
  Stream<RagGenerationChunk> generateStreaming(String query, RagRetrievalOptions options) {
    lastOptions = options;
    return Stream<RagGenerationChunk>.fromIterable(const <RagGenerationChunk>[
      RagGenerationChunk(text: 'Observed ', isDone: false),
      RagGenerationChunk(text: 'locally.', isDone: true),
    ]);
  }

  @override
  Future<void> close() async => closeCount++;
}
