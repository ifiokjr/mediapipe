import 'dart:async';
import 'dart:typed_data';

import 'package:meta/meta.dart';
import 'package:mp_core/mp_core.dart';

import 'options.dart';
import 'runtime.dart';

/// One partial update from a streaming generation.
@immutable
final class LlmGenerationChunk {
  /// Creates a generation chunk.
  const LlmGenerationChunk({required this.text, required this.isDone});

  /// Newly decoded text since the preceding update.
  final String text;

  /// Whether this is the final update.
  final bool isDone;
}

/// A cancellable in-progress LLM generation.
final class LlmGeneration {
  /// Creates a generation from streaming [chunks], [response], and [cancel].
  const LlmGeneration({required this.chunks, required this.response, required this.cancel});

  /// Incremental response chunks.
  final Stream<LlmGenerationChunk> chunks;

  /// Complete response after generation finishes.
  final Future<String> response;

  /// Requests cancellation of this generation.
  final Future<void> Function() cancel;
}

/// An on-device LLM engine that owns model weights and creates sessions.
///
/// MediaPipe deprecated its Android LLM task in favor of LiteRT-LM. This API
/// preserves MediaPipe compatibility while keeping the backend boundary open
/// for a LiteRT-LM migration.
final class LlmInference implements MpTask {
  LlmInference._(this.options, this._backend);

  /// Options used to load this engine.
  final LlmInferenceOptions options;

  final LlmInferenceBackend _backend;
  final TaskLifecycle _lifecycle = TaskLifecycle('LlmInference');

  /// Loads an engine using [runtime], or the active platform adapter.
  static Future<LlmInference> create(LlmInferenceOptions options, {GenAiRuntime? runtime}) async =>
      LlmInference._(options, await (runtime ?? defaultGenAiRuntime).createLlmInference(options));

  @override
  bool get isClosed => _lifecycle.isClosed;

  /// Creates an empty stateful inference session.
  Future<LlmSession> createSession({LlmSessionOptions? options}) async {
    _lifecycle.ensureOpen();
    final LlmSessionOptions resolved = options ?? LlmSessionOptions();
    if (resolved.topK > this.options.maxTopK) {
      throw ArgumentError.value(
        resolved.topK,
        'options.topK',
        'must not exceed the engine maxTopK (${this.options.maxTopK})',
      );
    }
    return LlmSession._(resolved, await _backend.createSession(resolved));
  }

  /// Generates a response in a temporary, stateless session.
  Future<LlmGeneration> generateResponse(String prompt, {LlmSessionOptions? sessionOptions}) async {
    final LlmSession session = await createSession(options: sessionOptions);
    await session.addQueryChunk(prompt);
    final LlmGeneration generation = await session.generate();
    unawaited(generation.response.whenComplete(session.close));
    return generation;
  }

  /// Counts the model tokens in [text].
  Future<int> sizeInTokens(String text) {
    _lifecycle.ensureOpen();
    return _backend.sizeInTokens(text);
  }

  @override
  Future<void> close() async {
    if (!_lifecycle.markClosed()) return;
    await _backend.close();
  }
}

/// A stateful LLM conversation context.
final class LlmSession implements MpTask {
  LlmSession._(this._options, this._backend);

  /// Current session options.
  LlmSessionOptions get options => _options;

  LlmSessionOptions _options;
  final LlmSessionBackend _backend;
  final TaskLifecycle _lifecycle = TaskLifecycle('LlmSession');

  @override
  bool get isClosed => _lifecycle.isClosed;

  /// Adds a text [chunk] to the context.
  Future<void> addQueryChunk(String chunk) {
    _lifecycle.ensureOpen();
    return _backend.addQueryChunk(chunk);
  }

  /// Adds an [image] to the context.
  Future<void> addImage(MpImage image) {
    _lifecycle.ensureOpen();
    return _backend.addImage(image);
  }

  /// Adds mono WAV [bytes] to the context.
  Future<void> addAudio(Uint8List bytes) {
    _lifecycle.ensureOpen();
    if (bytes.isEmpty) throw ArgumentError.value(bytes, 'bytes', 'must not be empty');
    return _backend.addAudio(Uint8List.fromList(bytes));
  }

  /// Starts generating a response from the accumulated context.
  Future<LlmGeneration> generate() {
    _lifecycle.ensureOpen();
    return _backend.generate();
  }

  /// Counts the model tokens in [text].
  Future<int> sizeInTokens(String text) {
    _lifecycle.ensureOpen();
    return _backend.sizeInTokens(text);
  }

  /// Clones the current session context.
  Future<LlmSession> clone() async {
    _lifecycle.ensureOpen();
    return LlmSession._(_options, await _backend.clone());
  }

  /// Updates mutable sampling [options].
  Future<void> updateOptions(LlmSessionOptions options) async {
    _lifecycle.ensureOpen();
    if (_options.loraAsset != options.loraAsset) {
      throw ArgumentError('loraAsset cannot change after session creation.');
    }
    if (_options.graphOptions != options.graphOptions) {
      throw ArgumentError('graphOptions cannot change after session creation.');
    }
    await _backend.updateOptions(options);
    _options = options;
  }

  @override
  Future<void> close() async {
    if (!_lifecycle.markClosed()) return;
    await _backend.close();
  }
}
