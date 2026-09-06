import 'package:meta/meta.dart';
import 'package:mp_core/mp_core.dart';

import 'runtime.dart';

/// Model-specific intent used to format text before embedding.
enum TextEmbeddingType {
  /// Retrieval query.
  retrievalQuery,

  /// Retrieval document.
  retrievalDocument,

  /// Semantic similarity.
  semanticSimilarity,

  /// Classification.
  classification,

  /// Clustering.
  clustering,

  /// Question answering.
  questionAnswering,

  /// Fact verification.
  factChecking,

  /// Code retrieval.
  codeRetrieval,
}

/// The input's role in a retrieval task.
enum TextEmbeddingRole {
  /// Query input.
  query,

  /// Document input.
  document,
}

/// Optional formatting context for models such as Gecko.
@immutable
final class TextEmbedderFormatContext {
  /// Creates a text formatting context.
  const TextEmbedderFormatContext({required this.taskType, required this.role, this.title});

  /// The embedding task intent.
  final TextEmbeddingType taskType;

  /// The input's role.
  final TextEmbeddingRole role;

  /// Optional document title.
  final String? title;
}

/// Configuration for a [TextEmbedder].
@immutable
final class TextEmbedderOptions {
  /// Creates text embedder options.
  const TextEmbedderOptions({
    required this.baseOptions,
    this.embedderOptions = const EmbedderOptions(),
  });

  /// Model and hardware configuration.
  final BaseOptions baseOptions;

  /// Embedding output configuration.
  final EmbedderOptions embedderOptions;
}

/// Platform implementation used by [TextEmbedder].
abstract interface class TextEmbedderBackend implements MpTask {
  /// Extracts embeddings from [text].
  Future<EmbeddingResult> embed(String text, {TextEmbedderFormatContext? formatContext});
}

/// Extracts vector embeddings from input text.
final class TextEmbedder implements MpTask {
  TextEmbedder._(this._backend);

  final TextEmbedderBackend _backend;
  final TaskLifecycle _lifecycle = TaskLifecycle('TextEmbedder');

  /// Creates an embedder using [runtime], or the active platform adapter.
  static Future<TextEmbedder> create(TextEmbedderOptions options, {TextRuntime? runtime}) async =>
      TextEmbedder._(await (runtime ?? defaultTextRuntime).createTextEmbedder(options));

  @override
  bool get isClosed => _lifecycle.isClosed;

  /// Extracts embeddings from [text].
  Future<EmbeddingResult> embed(String text, {TextEmbedderFormatContext? formatContext}) {
    _lifecycle.ensureOpen();
    return _backend.embed(text, formatContext: formatContext);
  }

  @override
  Future<void> close() async {
    if (!_lifecycle.markClosed()) return;
    await _backend.close();
  }
}
