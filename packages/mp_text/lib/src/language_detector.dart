import 'package:collection/collection.dart';
import 'package:meta/meta.dart';
import 'package:mp_core/mp_core.dart';

import 'runtime.dart';

/// Configuration for a [LanguageDetector].
@immutable
final class LanguageDetectorOptions {
  /// Creates language detector options.
  const LanguageDetectorOptions({required this.baseOptions, this.classifierOptions});

  /// Model and hardware configuration.
  final BaseOptions baseOptions;

  /// Optional result filtering configuration.
  final ClassifierOptions? classifierOptions;
}

/// A detected BCP-47 language code and its probability.
@immutable
final class LanguagePrediction {
  /// Creates a language prediction.
  const LanguagePrediction({required this.languageCode, required this.probability});

  /// The predicted BCP-47 language code.
  final String languageCode;

  /// Probability assigned by the model.
  final double probability;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is LanguagePrediction &&
          languageCode == other.languageCode &&
          probability == other.probability;

  @override
  int get hashCode => Object.hash(languageCode, probability);
}

/// Language predictions ordered from most to least likely.
@immutable
final class LanguageDetectorResult {
  /// Creates an immutable language detector result.
  LanguageDetectorResult(Iterable<LanguagePrediction> predictions)
    : predictions = List<LanguagePrediction>.unmodifiable(predictions);

  /// Predictions ordered by descending probability.
  final List<LanguagePrediction> predictions;

  /// The most likely prediction, or `null` when the model returned no result.
  LanguagePrediction? get topPrediction => predictions.firstOrNull;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is LanguageDetectorResult &&
          const ListEquality<LanguagePrediction>().equals(predictions, other.predictions);

  @override
  int get hashCode => const ListEquality<LanguagePrediction>().hash(predictions);
}

/// Platform implementation used by [LanguageDetector].
abstract interface class LanguageDetectorBackend implements MpTask {
  /// Detects the languages present in [text].
  Future<LanguageDetectorResult> detect(String text);
}

/// Detects the language of input text.
final class LanguageDetector implements MpTask {
  LanguageDetector._(this._backend);

  final LanguageDetectorBackend _backend;
  final TaskLifecycle _lifecycle = TaskLifecycle('LanguageDetector');

  /// Creates a detector using [runtime], or the active platform adapter.
  static Future<LanguageDetector> create(
    LanguageDetectorOptions options, {
    TextRuntime? runtime,
  }) async =>
      LanguageDetector._(await (runtime ?? defaultTextRuntime).createLanguageDetector(options));

  @override
  bool get isClosed => _lifecycle.isClosed;

  /// Detects the languages present in [text].
  Future<LanguageDetectorResult> detect(String text) {
    _lifecycle.ensureOpen();
    return _backend.detect(text);
  }

  @override
  Future<void> close() async {
    if (!_lifecycle.markClosed()) return;
    await _backend.close();
  }
}
