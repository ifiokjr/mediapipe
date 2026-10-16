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
  Future<void>? _closeFuture;

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
  Future<void> close() {
    if (!_lifecycle.markClosed()) return _closeFuture ?? Future<void>.value();

    return _closeFuture = _backend.close().catchError((Object error, StackTrace stackTrace) {
      // Reopen the facade so the failed cleanup can be retried instead of
      // leaking the backend's isolate and native handles forever.
      _closeFuture = null;
      _lifecycle.reopen();
      Error.throwWithStackTrace(error, stackTrace);
    });
  }
}
