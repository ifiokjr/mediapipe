import 'package:meta/meta.dart';
import 'package:mp_core/mp_core.dart';

import 'runtime.dart';

/// Configuration for a [TextClassifier].
@immutable
final class TextClassifierOptions {
  /// Creates text classifier options.
  const TextClassifierOptions({required this.baseOptions, this.classifierOptions});

  /// Model and hardware configuration.
  final BaseOptions baseOptions;

  /// Optional result filtering configuration.
  final ClassifierOptions? classifierOptions;
}

/// Platform implementation used by [TextClassifier].
abstract interface class TextClassifierBackend implements MpTask {
  /// Classifies [text].
  Future<ClassificationResult> classify(String text);
}

/// Classifies input text with a task-compatible model.
final class TextClassifier implements MpTask {
  TextClassifier._(this._backend);

  final TextClassifierBackend _backend;
  final TaskLifecycle _lifecycle = TaskLifecycle('TextClassifier');

  /// Creates a classifier using [runtime], or the active platform adapter.
  static Future<TextClassifier> create(
    TextClassifierOptions options, {
    TextRuntime? runtime,
  }) async => TextClassifier._(await (runtime ?? defaultTextRuntime).createTextClassifier(options));

  @override
  bool get isClosed => _lifecycle.isClosed;

  /// Classifies [text].
  Future<ClassificationResult> classify(String text) {
    _lifecycle.ensureOpen();
    return _backend.classify(text);
  }

  @override
  Future<void> close() async {
    if (!_lifecycle.markClosed()) return;
    await _backend.close();
  }
}
