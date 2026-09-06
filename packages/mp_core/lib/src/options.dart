import 'dart:typed_data';

import 'package:collection/collection.dart';
import 'package:meta/meta.dart';

/// The delegate requested for task execution.
enum MpDelegate {
  /// Execute with the CPU backend.
  cpu,

  /// Execute with the GPU backend when the platform and model support it.
  gpu,

  /// Execute through Android NNAPI on a supported Edge TPU path.
  edgeTpuNnapi,

  /// Let LiteRT choose a hardware accelerator.
  liteRt,
}

/// The preferred LiteRT accelerator when [MpDelegate.liteRt] is selected.
enum LiteRtAccelerator {
  /// Execute with the CPU.
  cpu,

  /// Execute with the GPU.
  gpu,

  /// Execute with a neural processing unit.
  npu,
}

/// Hardware-specific options for the LiteRT delegate.
@immutable
final class LiteRtOptions {
  /// Creates LiteRT options.
  LiteRtOptions({this.accelerator = LiteRtAccelerator.cpu, this.npuDispatchLibraryDirectory}) {
    if (accelerator != LiteRtAccelerator.npu && npuDispatchLibraryDirectory != null) {
      throw ArgumentError.value(
        npuDispatchLibraryDirectory,
        'npuDispatchLibraryDirectory',
        'is only valid for the NPU accelerator',
      );
    }
  }

  /// The accelerator that should execute the task.
  final LiteRtAccelerator accelerator;

  /// Directory containing the NPU dispatch library, when one is required.
  final String? npuDispatchLibraryDirectory;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is LiteRtOptions &&
          accelerator == other.accelerator &&
          npuDispatchLibraryDirectory == other.npuDispatchLibraryDirectory;

  @override
  int get hashCode => Object.hash(accelerator, npuDispatchLibraryDirectory);
}

/// A model source consumed by a MediaPipe task.
@immutable
sealed class ModelAsset {
  const ModelAsset._();

  /// Loads a model from a local filesystem [path].
  factory ModelAsset.path(String path) = ModelAssetPath;

  /// Loads a model from in-memory [bytes].
  factory ModelAsset.bytes(Uint8List bytes, {String? name}) = ModelAssetBytes;

  /// Loads a model from [uri], optionally checking [sha256].
  factory ModelAsset.uri(Uri uri, {String? sha256}) = ModelAssetUri;
}

/// A model stored at a local filesystem path.
@immutable
final class ModelAssetPath extends ModelAsset {
  /// Creates a path-backed model asset.
  ModelAssetPath(this.path) : super._() {
    if (path.trim().isEmpty) {
      throw ArgumentError.value(path, 'path', 'must not be empty');
    }
  }

  /// The local model path.
  final String path;

  @override
  bool operator ==(Object other) =>
      identical(this, other) || other is ModelAssetPath && path == other.path;

  @override
  int get hashCode => path.hashCode;
}

/// A model held in memory.
@immutable
final class ModelAssetBytes extends ModelAsset {
  /// Creates an immutable copy of [bytes].
  ModelAssetBytes(Uint8List bytes, {this.name}) : bytes = Uint8List.fromList(bytes), super._() {
    if (bytes.isEmpty) {
      throw ArgumentError.value(bytes, 'bytes', 'must not be empty');
    }
  }

  /// The model bytes.
  final Uint8List bytes;

  /// An optional diagnostic name for the model.
  final String? name;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ModelAssetBytes &&
          name == other.name &&
          const ListEquality<int>().equals(bytes, other.bytes);

  @override
  int get hashCode => Object.hash(name, const ListEquality<int>().hash(bytes));
}

/// A model retrieved from a URI by the active platform backend.
@immutable
final class ModelAssetUri extends ModelAsset {
  /// Creates a URI-backed model asset.
  ModelAssetUri(this.uri, {this.sha256}) : super._() {
    if (!uri.hasScheme) {
      throw ArgumentError.value(uri, 'uri', 'must be absolute');
    }
    if (sha256 != null && !RegExp(r'^[a-f0-9]{64}$').hasMatch(sha256!)) {
      throw ArgumentError.value(sha256, 'sha256', 'must be a lowercase SHA-256 digest');
    }
  }

  /// The absolute model URI.
  final Uri uri;

  /// An optional lowercase SHA-256 digest for supply-chain verification.
  final String? sha256;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ModelAssetUri && uri == other.uri && sha256 == other.sha256;

  @override
  int get hashCode => Object.hash(uri, sha256);
}

/// Options shared by every MediaPipe task.
@immutable
final class BaseOptions {
  /// Creates common task options.
  BaseOptions({required this.modelAsset, this.delegate = MpDelegate.cpu, this.liteRtOptions}) {
    if (delegate != MpDelegate.liteRt && liteRtOptions != null) {
      throw ArgumentError.value(liteRtOptions, 'liteRtOptions', 'requires MpDelegate.liteRt');
    }
  }

  /// The model to load.
  final ModelAsset modelAsset;

  /// The requested compute delegate.
  final MpDelegate delegate;

  /// Optional LiteRT accelerator settings.
  final LiteRtOptions? liteRtOptions;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is BaseOptions &&
          modelAsset == other.modelAsset &&
          delegate == other.delegate &&
          liteRtOptions == other.liteRtOptions;

  @override
  int get hashCode => Object.hash(modelAsset, delegate, liteRtOptions);
}

/// Options shared by classification tasks.
@immutable
final class ClassifierOptions {
  /// Creates classification post-processing options.
  ClassifierOptions({
    this.displayNamesLocale,
    this.maxResults,
    this.scoreThreshold,
    Iterable<String> categoryAllowlist = const <String>[],
    Iterable<String> categoryDenylist = const <String>[],
  }) : categoryAllowlist = List<String>.unmodifiable(categoryAllowlist),
       categoryDenylist = List<String>.unmodifiable(categoryDenylist) {
    if (maxResults != null && maxResults! <= 0) {
      throw ArgumentError.value(maxResults, 'maxResults', 'must be greater than zero');
    }
    if (scoreThreshold != null && (scoreThreshold! < 0 || scoreThreshold! > 1)) {
      throw ArgumentError.value(scoreThreshold, 'scoreThreshold', 'must be between 0 and 1');
    }
    if (this.categoryAllowlist.isNotEmpty && this.categoryDenylist.isNotEmpty) {
      throw ArgumentError('categoryAllowlist and categoryDenylist are mutually exclusive.');
    }
  }

  /// Locale used for translated display names in model metadata.
  final String? displayNamesLocale;

  /// Maximum number of top-scored results.
  final int? maxResults;

  /// Minimum accepted category score.
  final double? scoreThreshold;

  /// Categories that may appear in results.
  final List<String> categoryAllowlist;

  /// Categories that must not appear in results.
  final List<String> categoryDenylist;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ClassifierOptions &&
          displayNamesLocale == other.displayNamesLocale &&
          maxResults == other.maxResults &&
          scoreThreshold == other.scoreThreshold &&
          const ListEquality<String>().equals(categoryAllowlist, other.categoryAllowlist) &&
          const ListEquality<String>().equals(categoryDenylist, other.categoryDenylist);

  @override
  int get hashCode => Object.hash(
    displayNamesLocale,
    maxResults,
    scoreThreshold,
    const ListEquality<String>().hash(categoryAllowlist),
    const ListEquality<String>().hash(categoryDenylist),
  );
}

/// Options shared by embedding tasks.
@immutable
final class EmbedderOptions {
  /// Creates embedding post-processing options.
  const EmbedderOptions({this.l2Normalize = false, this.quantize = false});

  /// Whether to L2-normalize the returned embedding.
  final bool l2Normalize;

  /// Whether to scalar-quantize the returned embedding.
  final bool quantize;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is EmbedderOptions && l2Normalize == other.l2Normalize && quantize == other.quantize;

  @override
  int get hashCode => Object.hash(l2Normalize, quantize);
}
