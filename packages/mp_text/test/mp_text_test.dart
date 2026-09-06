import 'dart:typed_data';

import 'package:mp_core/mp_core.dart';
import 'package:mp_text/mp_text.dart';
import 'package:test/test.dart';

void main() {
  late _FakeTextRuntime runtime;

  setUp(() => runtime = _FakeTextRuntime());

  test('language detector delegates and closes exactly once', () async {
    final LanguageDetector detector = await LanguageDetector.create(
      LanguageDetectorOptions(baseOptions: _baseOptions()),
      runtime: runtime,
    );

    final LanguageDetectorResult result = await detector.detect('Hello');
    await detector.close();
    await detector.close();

    expect(result.topPrediction?.languageCode, 'en');
    expect(runtime.languageDetector.inputs, <String>['Hello']);
    expect(runtime.languageDetector.closeCount, 1);
    expect(() => detector.detect('again'), throwsA(isA<MpTaskClosedError>()));
  });

  test('text classifier preserves typed results', () async {
    final TextClassifier classifier = await TextClassifier.create(
      TextClassifierOptions(baseOptions: _baseOptions()),
      runtime: runtime,
    );

    final ClassificationResult result = await classifier.classify('Useful');

    expect(result.classifications.single.topCategory?.categoryName, 'positive');
    expect(runtime.classifier.inputs, <String>['Useful']);
  });

  test('text embedder forwards optional format context', () async {
    final TextEmbedder embedder = await TextEmbedder.create(
      TextEmbedderOptions(baseOptions: _baseOptions()),
      runtime: runtime,
    );
    const TextEmbedderFormatContext context = TextEmbedderFormatContext(
      taskType: TextEmbeddingType.retrievalDocument,
      role: TextEmbeddingRole.document,
      title: 'Readme',
    );

    final EmbeddingResult result = await embedder.embed('document', formatContext: context);

    expect(result.embeddings.single.floatValues, <double>[1, 2]);
    expect(runtime.embedder.formatContext, same(context));
  });

  test('text proofreader preserves corrections and streams chunks', () async {
    final TextProofreader proofreader = await TextProofreader.create(
      TextProofreaderOptions(baseOptions: _baseOptions(), maxTokens: 256),
      runtime: runtime,
    );

    final TextProofreaderResult result = await proofreader.proofread('A sentence');
    final List<TextProofreaderChunk> chunks = await proofreader
        .proofreadStreaming('A sentence')
        .toList();
    await proofreader.close();
    await proofreader.close();

    expect(result.text, 'A corrected sentence.');
    expect(result.corrections[1].type, TextCorrectionType.insertion);
    expect(chunks.map((TextProofreaderChunk chunk) => chunk.text), <String>[
      'A corrected ',
      'sentence.',
    ]);
    expect(chunks.last.isDone, isTrue);
    expect(runtime.proofreader.closeCount, 1);
    expect(() => proofreader.proofread('again'), throwsA(isA<MpTaskClosedError>()));
  });

  test('text summarizer delegates mode and streams chunks', () async {
    final TextSummarizerOptions options = TextSummarizerOptions(
      baseOptions: _baseOptions(),
      mode: TextSummarizerMode.tldr,
      maxTokens: 128,
    );
    final TextSummarizer summarizer = await TextSummarizer.create(options, runtime: runtime);

    final TextSummarizerResult result = await summarizer.summarize('Long text');
    final List<TextSummarizerChunk> chunks = await summarizer
        .summarizeStreaming('Long text')
        .toList();

    expect(result.summary, 'Short text.');
    expect(chunks.last, isA<TextSummarizerChunk>().having((chunk) => chunk.isDone, 'isDone', true));
    expect(runtime.summarizerOptions, same(options));
  });

  test('generation task options reject non-positive token limits', () {
    expect(
      () => TextProofreaderOptions(baseOptions: _baseOptions(), maxTokens: 0),
      throwsArgumentError,
    );
    expect(
      () => TextSummarizerOptions(baseOptions: _baseOptions(), maxTokens: -1),
      throwsArgumentError,
    );
  });

  test('proofreader results own an immutable correction list', () {
    final List<TextCorrection> source = <TextCorrection>[
      const TextCorrection(type: TextCorrectionType.same, text: 'kept'),
    ];
    final TextProofreaderResult result = TextProofreaderResult(text: 'kept', corrections: source);

    source.clear();

    expect(result.corrections, hasLength(1));
    expect(result.corrections.clear, throwsUnsupportedError);
  });

  test('unsupported runtimes fail honestly', () async {
    await expectLater(
      LanguageDetector.create(
        LanguageDetectorOptions(baseOptions: _baseOptions()),
        runtime: const UnsupportedTextRuntime(MpPlatform.unknown),
      ),
      throwsA(
        isA<MpException>().having(
          (MpException error) => error.status,
          'status',
          MpStatus.unimplemented,
        ),
      ),
    );
  });
}

BaseOptions _baseOptions() => BaseOptions(modelAsset: ModelAsset.path('model.tflite'));

final class _FakeTextRuntime implements TextRuntime {
  final _FakeLanguageDetector languageDetector = _FakeLanguageDetector();
  final _FakeTextClassifier classifier = _FakeTextClassifier();
  final _FakeTextEmbedder embedder = _FakeTextEmbedder();
  final _FakeTextProofreader proofreader = _FakeTextProofreader();
  final _FakeTextSummarizer summarizer = _FakeTextSummarizer();
  TextSummarizerOptions? summarizerOptions;

  @override
  Future<LanguageDetectorBackend> createLanguageDetector(LanguageDetectorOptions options) async =>
      languageDetector;

  @override
  Future<TextClassifierBackend> createTextClassifier(TextClassifierOptions options) async =>
      classifier;

  @override
  Future<TextEmbedderBackend> createTextEmbedder(TextEmbedderOptions options) async => embedder;

  @override
  Future<TextProofreaderBackend> createTextProofreader(TextProofreaderOptions options) async =>
      proofreader;

  @override
  Future<TextSummarizerBackend> createTextSummarizer(TextSummarizerOptions options) async {
    summarizerOptions = options;
    return summarizer;
  }
}

base class _FakeTask implements MpTask {
  int closeCount = 0;

  @override
  bool get isClosed => closeCount > 0;

  @override
  Future<void> close() async => closeCount++;
}

final class _FakeLanguageDetector extends _FakeTask implements LanguageDetectorBackend {
  final List<String> inputs = <String>[];

  @override
  Future<LanguageDetectorResult> detect(String text) async {
    inputs.add(text);
    return LanguageDetectorResult(const <LanguagePrediction>[
      LanguagePrediction(languageCode: 'en', probability: 0.9),
    ]);
  }
}

final class _FakeTextClassifier extends _FakeTask implements TextClassifierBackend {
  final List<String> inputs = <String>[];

  @override
  Future<ClassificationResult> classify(String text) async {
    inputs.add(text);
    return ClassificationResult(
      classifications: <Classifications>[
        Classifications(
          categories: const <Category>[Category(index: 0, score: 0.8, categoryName: 'positive')],
          headIndex: 0,
        ),
      ],
    );
  }
}

final class _FakeTextEmbedder extends _FakeTask implements TextEmbedderBackend {
  TextEmbedderFormatContext? formatContext;

  @override
  Future<EmbeddingResult> embed(String text, {TextEmbedderFormatContext? formatContext}) async {
    this.formatContext = formatContext;
    return EmbeddingResult(
      embeddings: <Embedding>[
        Embedding.float(Float32List.fromList(<double>[1, 2]), headIndex: 0),
      ],
    );
  }
}

final class _FakeTextProofreader extends _FakeTask implements TextProofreaderBackend {
  @override
  Future<TextProofreaderResult> proofread(String text) async => TextProofreaderResult(
    text: 'A corrected sentence.',
    corrections: const <TextCorrection>[
      TextCorrection(type: TextCorrectionType.same, text: 'A '),
      TextCorrection(type: TextCorrectionType.insertion, text: 'corrected '),
      TextCorrection(type: TextCorrectionType.same, text: 'sentence'),
      TextCorrection(type: TextCorrectionType.insertion, text: '.'),
    ],
  );

  @override
  Stream<TextProofreaderChunk> proofreadStreaming(String text) =>
      Stream.fromIterable(<TextProofreaderChunk>[
        TextProofreaderChunk(text: 'A corrected ', isDone: false),
        TextProofreaderChunk(
          text: 'sentence.',
          isDone: true,
          corrections: const <TextCorrection>[
            TextCorrection(type: TextCorrectionType.same, text: 'A sentence'),
          ],
        ),
      ]);
}

final class _FakeTextSummarizer extends _FakeTask implements TextSummarizerBackend {
  @override
  Future<TextSummarizerResult> summarize(String text) async =>
      const TextSummarizerResult('Short text.');

  @override
  Stream<TextSummarizerChunk> summarizeStreaming(String text) =>
      Stream.fromIterable(const <TextSummarizerChunk>[
        TextSummarizerChunk(text: 'Short ', isDone: false),
        TextSummarizerChunk(text: 'text.', isDone: true),
      ]);
}
