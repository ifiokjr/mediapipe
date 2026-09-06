import 'package:meta/meta.dart';
import 'package:mp_core/mp_core.dart';

import 'json_value.dart';
import 'options.dart';
import 'runtime.dart';

/// Embedding task used to encode a RAG query.
enum RagRetrievalTask {
  /// Let the embedding model choose its default retrieval task.
  unspecified,

  /// General document retrieval.
  retrievalQuery,

  /// Question answering.
  questionAnswering,

  /// Fact verification.
  factVerification,

  /// Source-code retrieval.
  codeRetrieval,
}

/// On-device embedding model used by a RAG pipeline.
@immutable
sealed class RagEmbeddingModelOptions {
  const RagEmbeddingModelOptions();
}

/// Gecko embedding model configuration.
@immutable
final class GeckoEmbeddingModelOptions extends RagEmbeddingModelOptions {
  /// Creates Gecko embedding options.
  const GeckoEmbeddingModelOptions({required this.model, this.tokenizer, this.useGpu = false});

  /// Gecko embedding model.
  final ModelAsset model;

  /// Optional SentencePiece tokenizer.
  final ModelAsset? tokenizer;

  /// Whether to execute embedding on the GPU.
  final bool useGpu;
}

/// Gemma embedding model configuration.
@immutable
final class GemmaEmbeddingModelOptions extends RagEmbeddingModelOptions {
  /// Creates Gemma embedding options.
  const GemmaEmbeddingModelOptions({
    required this.model,
    required this.tokenizer,
    this.useGpu = false,
  });

  /// Gemma embedding model.
  final ModelAsset model;

  /// SentencePiece tokenizer.
  final ModelAsset tokenizer;

  /// Whether to execute embedding on the GPU.
  final bool useGpu;
}

/// Vector storage used by a RAG pipeline.
@immutable
sealed class RagVectorStoreOptions {
  const RagVectorStoreOptions();
}

/// Process-local in-memory vector storage.
@immutable
final class InMemoryVectorStoreOptions extends RagVectorStoreOptions {
  /// Creates in-memory store options.
  const InMemoryVectorStoreOptions();
}

/// Key configuration for a custom SQLite column.
enum RagSqliteKeyType {
  /// A normal non-key column.
  none,

  /// The table's primary key.
  primary,
}

/// One custom column in a SQLite vector store.
@immutable
final class RagSqliteColumn {
  /// Creates a SQLite column definition.
  RagSqliteColumn({
    required this.name,
    required this.sqlType,
    this.keyType = RagSqliteKeyType.none,
    this.autoIncrement = false,
    this.nullable = true,
  }) {
    if (name.trim().isEmpty) throw ArgumentError.value(name, 'name', 'must not be empty');
    if (sqlType.trim().isEmpty) {
      throw ArgumentError.value(sqlType, 'sqlType', 'must not be empty');
    }
    if (autoIncrement && keyType != RagSqliteKeyType.primary) {
      throw ArgumentError.value(autoIncrement, 'autoIncrement', 'requires a primary key');
    }
  }

  /// Column name.
  final String name;

  /// SQLite type expression.
  final String sqlType;

  /// Whether this column is the primary key.
  final RagSqliteKeyType keyType;

  /// Whether an integer primary key auto-increments.
  final bool autoIncrement;

  /// Whether the column accepts null values.
  final bool nullable;
}

/// Persistent SQLite vector storage.
@immutable
final class SqliteVectorStoreOptions extends RagVectorStoreOptions {
  /// Creates SQLite vector-store options.
  SqliteVectorStoreOptions({
    required this.embeddingDimensions,
    required this.databasePath,
    this.tableName,
    this.textColumnName,
    this.embeddingsColumnName,
    Iterable<RagSqliteColumn> columns = const <RagSqliteColumn>[],
  }) : columns = List<RagSqliteColumn>.unmodifiable(columns) {
    if (embeddingDimensions <= 0) {
      throw ArgumentError.value(embeddingDimensions, 'embeddingDimensions', 'must be positive');
    }
    if (databasePath.trim().isEmpty) {
      throw ArgumentError.value(databasePath, 'databasePath', 'must not be empty');
    }
    final List<String?> names = <String?>[tableName, textColumnName, embeddingsColumnName];
    if (names.any((String? value) => value != null && value.trim().isEmpty)) {
      throw ArgumentError('SQLite table and column names must not be empty.');
    }
    final bool hasCustomSchema = names.any((String? value) => value != null) || columns.isNotEmpty;
    if (hasCustomSchema &&
        (tableName == null ||
            textColumnName == null ||
            embeddingsColumnName == null ||
            this.columns.isEmpty)) {
      throw ArgumentError(
        'A custom SQLite schema requires tableName, textColumnName, '
        'embeddingsColumnName, and columns.',
      );
    }
    final Set<String> columnNames = <String>{};
    for (final RagSqliteColumn column in this.columns) {
      if (!columnNames.add(column.name)) {
        throw ArgumentError.value(column.name, 'columns', 'contains a duplicate name');
      }
    }
    if (hasCustomSchema &&
        (!columnNames.contains(textColumnName) || !columnNames.contains(embeddingsColumnName))) {
      throw ArgumentError('The text and embeddings columns must be declared in columns.');
    }
  }

  /// Number of floating-point values in each embedding.
  final int embeddingDimensions;

  /// Database file path.
  final String databasePath;

  /// Custom table name.
  final String? tableName;

  /// Custom text column name.
  final String? textColumnName;

  /// Custom embedding column name.
  final String? embeddingsColumnName;

  /// Complete custom table column configuration.
  final List<RagSqliteColumn> columns;
}

/// RAG pipeline configuration for Android.
@immutable
final class RagPipelineOptions {
  /// Creates RAG pipeline options.
  RagPipelineOptions({
    required this.embeddingModel,
    required this.vectorStore,
    required this.inferenceOptions,
    required this.promptTemplate,
    this.sessionOptions,
  }) {
    if (promptTemplate.trim().isEmpty) {
      throw ArgumentError.value(promptTemplate, 'promptTemplate', 'must not be empty');
    }
  }

  /// Model used to embed records and queries.
  final RagEmbeddingModelOptions embeddingModel;

  /// Vector storage implementation.
  final RagVectorStoreOptions vectorStore;

  /// LLM used to generate a response from retrieved context.
  final LlmInferenceOptions inferenceOptions;

  /// Java-format prompt template consumed by MediaPipe's `PromptBuilder`.
  final String promptTemplate;

  /// LLM sampling options.
  final LlmSessionOptions? sessionOptions;
}

/// Text and metadata recorded in semantic memory.
@immutable
final class RagDocument {
  /// Creates a RAG document.
  RagDocument({
    required this.text,
    Map<String, Object?> metadata = const <String, Object?>{},
    this.embeddingText,
  }) : metadata = copyJsonObject(metadata) {
    if (text.trim().isEmpty) throw ArgumentError.value(text, 'text', 'must not be empty');
    if (embeddingText != null && embeddingText!.trim().isEmpty) {
      throw ArgumentError.value(embeddingText, 'embeddingText', 'must not be empty');
    }
  }

  /// Text returned when this document is retrieved.
  final String text;

  /// JSON-compatible metadata stored with this document.
  final Map<String, Object?> metadata;

  /// Optional alternative text used only to compute the embedding.
  final String? embeddingText;
}

/// Retrieval options for one query.
@immutable
final class RagRetrievalOptions {
  /// Creates retrieval options.
  RagRetrievalOptions({
    this.topK = 5,
    this.minSimilarityScore = 0,
    this.task = RagRetrievalTask.retrievalQuery,
  }) {
    if (topK <= 0) throw ArgumentError.value(topK, 'topK', 'must be positive');
    if (!minSimilarityScore.isFinite || minSimilarityScore < -1 || minSimilarityScore > 1) {
      throw ArgumentError.value(
        minSimilarityScore,
        'minSimilarityScore',
        'must be finite and between -1 and 1',
      );
    }
  }

  /// Maximum number of retrieved documents.
  final int topK;

  /// Minimum cosine similarity accepted by the vector store.
  final double minSimilarityScore;

  /// Query embedding task.
  final RagRetrievalTask task;
}

/// One retrieved document and its embedding.
@immutable
final class RagRetrievalEntity {
  /// Creates a retrieval entity.
  RagRetrievalEntity({
    required this.text,
    required Iterable<double> embedding,
    Map<String, Object?> metadata = const <String, Object?>{},
  }) : embedding = List<double>.unmodifiable(embedding),
       metadata = copyJsonObject(metadata);

  /// Retrieved document text.
  final String text;

  /// Stored embedding vector.
  final List<double> embedding;

  /// JSON-compatible document metadata.
  final Map<String, Object?> metadata;
}

/// One partial RAG generation update.
@immutable
final class RagGenerationChunk {
  /// Creates a generation chunk.
  const RagGenerationChunk({required this.text, required this.isDone});

  /// Partial response text reported by the MediaPipe progress callback.
  ///
  /// Consumers must not assume that this value is either a delta or the full
  /// response; that behavior is defined by the selected upstream model backend.
  final String text;

  /// Whether generation is complete.
  final bool isDone;
}

/// Retrieval-augmented generation backed by MediaPipe's Android RAG SDK.
final class RagPipeline implements MpTask {
  RagPipeline._(this.options, this._backend);

  /// Options used to create this pipeline.
  final RagPipelineOptions options;

  final RagPipelineBackend _backend;
  final TaskLifecycle _lifecycle = TaskLifecycle('RagPipeline');

  /// Loads a RAG pipeline using [runtime], or the Android adapter.
  static Future<RagPipeline> create(RagPipelineOptions options, {GenAiRuntime? runtime}) async =>
      RagPipeline._(options, await (runtime ?? defaultGenAiRuntime).createRagPipeline(options));

  @override
  bool get isClosed => _lifecycle.isClosed;

  /// Embeds and records one document.
  Future<bool> record(RagDocument document) {
    _lifecycle.ensureOpen();
    return _backend.record(document);
  }

  /// Embeds and records a document batch.
  Future<bool> recordAll(Iterable<RagDocument> documents) {
    _lifecycle.ensureOpen();
    final List<RagDocument> batch = List<RagDocument>.unmodifiable(documents);
    if (batch.isEmpty) throw ArgumentError.value(batch, 'documents', 'must not be empty');
    return _backend.recordAll(batch);
  }

  /// Retrieves semantically similar documents without running the LLM.
  Future<List<RagRetrievalEntity>> retrieve(String query, {RagRetrievalOptions? options}) {
    _lifecycle.ensureOpen();
    _checkQuery(query);
    return _backend.retrieve(query, options ?? RagRetrievalOptions());
  }

  /// Retrieves context and generates a complete response.
  Future<String> generate(String query, {RagRetrievalOptions? options}) {
    _lifecycle.ensureOpen();
    _checkQuery(query);
    return _backend.generate(query, options ?? RagRetrievalOptions());
  }

  /// Retrieves context and streams response chunks.
  Stream<RagGenerationChunk> generateStreaming(String query, {RagRetrievalOptions? options}) {
    _lifecycle.ensureOpen();
    _checkQuery(query);
    return _backend.generateStreaming(query, options ?? RagRetrievalOptions());
  }

  @override
  Future<void> close() async {
    if (!_lifecycle.markClosed()) return;
    await _backend.close();
  }
}

void _checkQuery(String query) {
  if (query.trim().isEmpty) throw ArgumentError.value(query, 'query', 'must not be empty');
}
