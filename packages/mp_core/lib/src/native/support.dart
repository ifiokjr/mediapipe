import 'dart:ffi' as ffi;
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:ffi/ffi.dart';

import '../../mp_core.dart';
import 'bindings.g.dart' as bindings;

const int _maximumRemoteModelBytes = 512 * 1024 * 1024;

/// Resolves URI-backed model assets before crossing the native ABI.
Future<ModelAsset> resolveNativeModelAsset(ModelAsset asset) async {
  if (asset case ModelAssetUri(:final uri, sha256: final expectedSha256)) {
    if (uri.scheme == 'file') {
      return ModelAsset.path(uri.toFilePath());
    }
    if (uri.scheme != 'https') {
      throw const MpException(
        MpStatus.invalidArgument,
        'Native model URIs must use HTTPS or the file scheme.',
      );
    }

    final HttpClient client = HttpClient()..connectionTimeout = const Duration(seconds: 30);
    try {
      final HttpClientRequest request = await client.getUrl(uri);
      final HttpClientResponse response = await request.close();
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw MpException(
          MpStatus.unavailable,
          'Downloading the model failed with HTTP ${response.statusCode}.',
        );
      }
      final BytesBuilder bytes = BytesBuilder(copy: false);
      var length = 0;
      await for (final List<int> chunk in response) {
        length += chunk.length;
        if (length > _maximumRemoteModelBytes) {
          throw const MpException(
            MpStatus.resourceExhausted,
            'The remote model exceeds the 512 MiB safety limit.',
          );
        }
        bytes.add(chunk);
      }
      final Uint8List result = bytes.takeBytes();
      if (expectedSha256 != null && sha256.convert(result).toString() != expectedSha256) {
        throw const MpException(
          MpStatus.dataLoss,
          'The downloaded model does not match its SHA-256 digest.',
        );
      }
      return ModelAsset.bytes(result, name: uri.pathSegments.lastOrNull);
    } finally {
      client.close(force: true);
    }
  }
  return asset;
}

/// Owns temporary native allocations for one task creation or invocation.
final class NativeScope {
  /// Creates an allocation scope.
  NativeScope({this.task});

  /// Task name included in converted native errors.
  final String? task;

  final Arena _arena = Arena();

  /// Allocator used by generated task-option factories in this scope.
  ffi.Allocator get allocator => _arena;

  /// Converts a Dart string to a scoped UTF-8 C string.
  ffi.Pointer<ffi.Char> string(String? value) =>
      value == null ? ffi.nullptr : value.toNativeUtf8(allocator: _arena).cast<ffi.Char>();

  /// Allocates a scoped C string array.
  ffi.Pointer<ffi.Pointer<ffi.Char>> strings(List<String> values) {
    if (values.isEmpty) return ffi.nullptr;
    final ffi.Pointer<ffi.Pointer<ffi.Char>> result = _arena<ffi.Pointer<ffi.Char>>(values.length);
    for (var index = 0; index < values.length; index += 1) {
      result[index] = string(values[index]);
    }
    return result;
  }

  /// Allocates the error output expected by MediaPipe C functions.
  ffi.Pointer<ffi.Pointer<ffi.Char>> errorOutput() {
    final ffi.Pointer<ffi.Pointer<ffi.Char>> result = _arena<ffi.Pointer<ffi.Char>>();
    result.value = ffi.nullptr;
    return result;
  }

  /// Converts a native status and owned error message to [MpException].
  void check(bindings.MpStatus status, ffi.Pointer<ffi.Pointer<ffi.Char>> errorOutput) {
    final ffi.Pointer<ffi.Char> error = errorOutput.value;
    String? message;
    if (error != ffi.nullptr) {
      message = error.cast<Utf8>().toDartString();
      bindings.MpErrorFree(error);
      errorOutput.value = ffi.nullptr;
    }
    if (status != bindings.MpStatus.kMpOk) {
      throw MpException(
        MpStatus.fromCode(status.value),
        message ?? 'The native MediaPipe runtime returned ${status.name}.',
        task: task,
      );
    }
  }

  /// Allocates native base options backed by this scope.
  ffi.Pointer<bindings.MpBaseOptions> baseOptions(BaseOptions options) {
    final ffi.Pointer<bindings.MpBaseOptions> result = _arena<bindings.MpBaseOptions>();
    final bindings.MpBaseOptions value = result.ref;
    value
      ..model_asset_buffer = ffi.nullptr
      ..model_asset_buffer_count = 0
      ..model_asset_path = ffi.nullptr
      ..file_descriptor = -1
      ..delegate = _delegate(options.delegate)
      ..host_environment = _hostEnvironment()
      ..host_system = _hostSystem()
      ..host_version = string(Platform.version)
      ..ca_bundle_path = ffi.nullptr
      ..app_id = ffi.nullptr
      ..app_version = ffi.nullptr;

    switch (options.modelAsset) {
      case ModelAssetPath(path: final String path):
        value.model_asset_path = string(path);
      case ModelAssetBytes(bytes: final Uint8List bytes):
        final ffi.Pointer<ffi.Uint8> buffer = _arena<ffi.Uint8>(bytes.length);
        buffer.asTypedList(bytes.length).setAll(0, bytes);
        value
          ..model_asset_buffer = buffer.cast<ffi.Char>()
          ..model_asset_buffer_count = bytes.length;
      case ModelAssetUri():
        throw const MpException(
          MpStatus.failedPrecondition,
          'Resolve URI-backed model assets before creating native options.',
        );
    }
    return result;
  }

  /// Allocates native classifier options backed by this scope.
  ffi.Pointer<bindings.MpClassifierOptions> classifierOptions(ClassifierOptions? options) {
    final ClassifierOptions value = options ?? ClassifierOptions();
    return bindings.MpClassifierOptions.$allocate(
      _arena,
      display_names_locale: string(value.displayNamesLocale),
      max_results: value.maxResults ?? -1,
      score_threshold: value.scoreThreshold ?? 0,
      category_allowlist: strings(value.categoryAllowlist),
      category_allowlist_count: value.categoryAllowlist.length,
      category_denylist: strings(value.categoryDenylist),
      category_denylist_count: value.categoryDenylist.length,
    );
  }

  /// Allocates native embedding options backed by this scope.
  ffi.Pointer<bindings.MpEmbedderOptions> embedderOptions(EmbedderOptions options) =>
      bindings.MpEmbedderOptions.$allocate(
        _arena,
        l2_normalize: options.l2Normalize,
        quantize: options.quantize,
      );

  /// Allocates native image-processing options backed by this scope.
  ffi.Pointer<bindings.MpImageProcessingOptions> imageProcessingOptions(
    ImageProcessingOptions? options,
  ) {
    final ffi.Pointer<bindings.MpImageProcessingOptions> result =
        _arena<bindings.MpImageProcessingOptions>();
    final ImageProcessingOptions value = options ?? ImageProcessingOptions();
    result.ref
      ..has_region_of_interest = value.regionOfInterest == null ? 0 : 1
      ..rotation_degrees = value.rotationDegrees;
    if (value.regionOfInterest case final NormalizedRect rectangle) {
      result.ref.region_of_interest
        ..left = rectangle.left
        ..top = rectangle.top
        ..right = rectangle.right
        ..bottom = rectangle.bottom;
    }
    return result;
  }

  /// Copies [image] into an owned MediaPipe native image.
  bindings.MpImagePtr image(MpImage image) {
    final ffi.Pointer<bindings.MpImagePtr> output = _arena<bindings.MpImagePtr>();
    final ffi.Pointer<ffi.Pointer<ffi.Char>> error = errorOutput();
    final bindings.MpStatus status = switch (image) {
      MpImageUint8(:final data) => _createUint8Image(image, data, output, error),
      MpImageUint16(:final data) => _createUint16Image(image, data, output, error),
      MpImageFloat32(:final data) => _createFloatImage(image, data, output, error),
    };
    check(status, error);
    return output.value;
  }

  bindings.MpStatus _createUint8Image(
    MpImage image,
    Uint8List data,
    ffi.Pointer<bindings.MpImagePtr> output,
    ffi.Pointer<ffi.Pointer<ffi.Char>> error,
  ) {
    final ffi.Pointer<ffi.Uint8> buffer = _arena<ffi.Uint8>(data.length);
    buffer.asTypedList(data.length).setAll(0, data);
    return bindings.MpImageCreateFromUint8Data(
      _imageFormat(image.format),
      image.width,
      image.height,
      buffer,
      data.length,
      output,
      error,
    );
  }

  bindings.MpStatus _createUint16Image(
    MpImage image,
    Uint16List data,
    ffi.Pointer<bindings.MpImagePtr> output,
    ffi.Pointer<ffi.Pointer<ffi.Char>> error,
  ) {
    final ffi.Pointer<ffi.Uint16> buffer = _arena<ffi.Uint16>(data.length);
    buffer.asTypedList(data.length).setAll(0, data);
    return bindings.MpImageCreateFromUint16Data(
      _imageFormat(image.format),
      image.width,
      image.height,
      buffer,
      data.length,
      output,
      error,
    );
  }

  bindings.MpStatus _createFloatImage(
    MpImage image,
    Float32List data,
    ffi.Pointer<bindings.MpImagePtr> output,
    ffi.Pointer<ffi.Pointer<ffi.Char>> error,
  ) {
    final ffi.Pointer<ffi.Float> buffer = _arena<ffi.Float>(data.length);
    buffer.asTypedList(data.length).setAll(0, data);
    return bindings.MpImageCreateFromFloatData(
      _imageFormat(image.format),
      image.width,
      image.height,
      buffer,
      data.length,
      output,
      error,
    );
  }

  /// Releases every temporary allocation in this scope.
  void release() => _arena.releaseAll();
}

/// Converts a nullable native UTF-8 pointer without taking ownership.
String? nativeString(ffi.Pointer<ffi.Char> value) =>
    value == ffi.nullptr ? null : value.cast<Utf8>().toDartString();

/// Converts a native category.
Category categoryFromNative(bindings.MpCategory value) => Category(
  index: value.index,
  score: value.score,
  categoryName: nativeString(value.category_name),
  displayName: nativeString(value.display_name),
);

/// Converts a native classification result before its owner is released.
ClassificationResult classificationResultFromNative(bindings.MpClassificationResult value) {
  final List<Classifications> heads = List<Classifications>.generate(value.classifications_count, (
    int headIndex,
  ) {
    final bindings.MpClassifications head = value.classifications[headIndex];
    return Classifications(
      categories: List<Category>.generate(
        head.categories_count,
        (int categoryIndex) => categoryFromNative(head.categories[categoryIndex]),
      ),
      headIndex: head.head_index,
      headName: nativeString(head.head_name),
    );
  }, growable: false);
  return ClassificationResult(
    classifications: heads,
    timestampMs: value.has_timestamp_ms ? value.timestamp_ms : null,
  );
}

/// Converts one native category list before its owner is released.
List<Category> categoriesFromNative(bindings.MpCategories value) => List<Category>.generate(
  value.categories_count,
  (int index) => categoryFromNative(value.categories[index]),
  growable: false,
);

/// Converts one native classifications head before its owner is released.
Classifications classificationsFromNative(bindings.MpClassifications value) => Classifications(
  categories: List<Category>.generate(
    value.categories_count,
    (int index) => categoryFromNative(value.categories[index]),
    growable: false,
  ),
  headIndex: value.head_index,
  headName: nativeString(value.head_name),
);

/// Converts a native detection result before its owner is released.
DetectionResult detectionResultFromNative(bindings.MpDetectionResult value, {int? timestampMs}) =>
    DetectionResult(
      detections: List<Detection>.generate(value.detections_count, (int index) {
        final bindings.MpDetection detection = value.detections[index];
        return Detection(
          categories: List<Category>.generate(
            detection.categories_count,
            (int categoryIndex) => categoryFromNative(detection.categories[categoryIndex]),
            growable: false,
          ),
          boundingBox: BoundingBox(
            left: detection.bounding_box.left,
            top: detection.bounding_box.top,
            width: detection.bounding_box.right - detection.bounding_box.left,
            height: detection.bounding_box.bottom - detection.bounding_box.top,
          ),
          keypoints: List<NormalizedKeypoint>.generate(detection.keypoints_count, (
            int keypointIndex,
          ) {
            final bindings.MpNormalizedKeypoint keypoint = detection.keypoints[keypointIndex];
            return NormalizedKeypoint(
              x: keypoint.x,
              y: keypoint.y,
              label: nativeString(keypoint.label),
              score: keypoint.has_score ? keypoint.score : null,
            );
          }, growable: false),
        );
      }, growable: false),
      timestampMs: timestampMs,
    );

/// Converts one native normalized-landmark list before its owner is released.
List<NormalizedLandmark> normalizedLandmarksFromNative(bindings.MpNormalizedLandmarks value) =>
    List<NormalizedLandmark>.generate(value.landmarks_count, (int index) {
      final bindings.MpNormalizedLandmark landmark = value.landmarks[index];
      return NormalizedLandmark(
        x: landmark.x,
        y: landmark.y,
        z: landmark.z,
        visibility: landmark.has_visibility ? landmark.visibility : null,
        presence: landmark.has_presence ? landmark.presence : null,
        name: nativeString(landmark.name),
      );
    }, growable: false);

/// Converts one native world-landmark list before its owner is released.
List<Landmark> landmarksFromNative(bindings.MpLandmarks value) =>
    List<Landmark>.generate(value.landmarks_count, (int index) {
      final bindings.MpLandmark landmark = value.landmarks[index];
      return Landmark(
        x: landmark.x,
        y: landmark.y,
        z: landmark.z,
        visibility: landmark.has_visibility ? landmark.visibility : null,
        presence: landmark.has_presence ? landmark.presence : null,
        name: nativeString(landmark.name),
      );
    }, growable: false);

/// Converts a native column-major matrix into the public row-major format.
MpMatrix matrixFromNative(bindings.MpMatrix value) {
  final Float32List rowMajor = Float32List(value.rows * value.cols);
  for (var column = 0; column < value.cols; column += 1) {
    for (var row = 0; row < value.rows; row += 1) {
      rowMajor[row * value.cols + column] = value.data[column * value.rows + row];
    }
  }
  return MpMatrix(rows: value.rows, columns: value.cols, values: rowMajor);
}

/// Copies a native image into an immutable Dart image.
MpImage imageFromNative(bindings.MpImagePtr image, {String? task}) {
  final NativeScope scope = NativeScope(task: task);
  try {
    final int width = bindings.MpImageGetWidth(image);
    final int height = bindings.MpImageGetHeight(image);
    final bindings.MpImageFormat format = bindings.MpImageGetFormat(image);
    final int samples = width * height * bindings.MpImageGetChannels(image);
    final ffi.Pointer<ffi.Pointer<ffi.Char>> error = scope.errorOutput();
    return switch (format) {
      bindings.MpImageFormat.kMpImageFormatSrgb ||
      bindings.MpImageFormat.kMpImageFormatSrgba ||
      bindings.MpImageFormat.kMpImageFormatGray8 => _uint8ImageFromNative(
        scope,
        image,
        _dartImageFormat(format),
        width,
        height,
        samples,
        error,
      ),
      bindings.MpImageFormat.kMpImageFormatGray16 ||
      bindings.MpImageFormat.kMpImageFormatSrgb48 ||
      bindings.MpImageFormat.kMpImageFormatSrgba64 => _uint16ImageFromNative(
        scope,
        image,
        _dartImageFormat(format),
        width,
        height,
        samples,
        error,
      ),
      bindings.MpImageFormat.kMpImageFormatVec32F1 ||
      bindings.MpImageFormat.kMpImageFormatVec32F2 ||
      bindings.MpImageFormat.kMpImageFormatVec32F4 => _floatImageFromNative(
        scope,
        image,
        _dartImageFormat(format),
        width,
        height,
        samples,
        error,
      ),
      bindings.MpImageFormat.kMpImageFormatUnknown => throw MpException(
        MpStatus.dataLoss,
        'The native task returned an image with an unknown format.',
        task: task,
      ),
    };
  } finally {
    scope.release();
  }
}

MpImage _uint8ImageFromNative(
  NativeScope scope,
  bindings.MpImagePtr image,
  MpImageFormat format,
  int width,
  int height,
  int samples,
  ffi.Pointer<ffi.Pointer<ffi.Char>> error,
) {
  final ffi.Pointer<ffi.Pointer<ffi.Uint8>> output = scope.allocator<ffi.Pointer<ffi.Uint8>>();
  scope.check(bindings.MpImageDataUint8(image, output, error), error);
  return MpImage.uint8(
    width: width,
    height: height,
    format: format,
    data: Uint8List.fromList(output.value.asTypedList(samples)),
  );
}

MpImage _uint16ImageFromNative(
  NativeScope scope,
  bindings.MpImagePtr image,
  MpImageFormat format,
  int width,
  int height,
  int samples,
  ffi.Pointer<ffi.Pointer<ffi.Char>> error,
) {
  final ffi.Pointer<ffi.Pointer<ffi.Uint16>> output = scope.allocator<ffi.Pointer<ffi.Uint16>>();
  scope.check(bindings.MpImageDataUint16(image, output, error), error);
  return MpImage.uint16(
    width: width,
    height: height,
    format: format,
    data: Uint16List.fromList(output.value.asTypedList(samples)),
  );
}

MpImage _floatImageFromNative(
  NativeScope scope,
  bindings.MpImagePtr image,
  MpImageFormat format,
  int width,
  int height,
  int samples,
  ffi.Pointer<ffi.Pointer<ffi.Char>> error,
) {
  final ffi.Pointer<ffi.Pointer<ffi.Float>> output = scope.allocator<ffi.Pointer<ffi.Float>>();
  scope.check(bindings.MpImageDataFloat32(image, output, error), error);
  return MpImage.float32(
    width: width,
    height: height,
    format: format,
    data: Float32List.fromList(output.value.asTypedList(samples)),
  );
}

/// Converts a native embedding result before its owner is released.
EmbeddingResult embeddingResultFromNative(bindings.MpEmbeddingResult value) {
  final List<Embedding> embeddings = List<Embedding>.generate(value.embeddings_count, (int index) {
    final bindings.MpEmbedding embedding = value.embeddings[index];
    final String? headName = nativeString(embedding.head_name);
    if (embedding.float_embedding != ffi.nullptr) {
      return Embedding.float(
        Float32List.fromList(embedding.float_embedding.asTypedList(embedding.values_count)),
        headIndex: embedding.head_index,
        headName: headName,
      );
    }
    return Embedding.quantized(
      Uint8List.fromList(
        embedding.quantized_embedding.cast<ffi.Uint8>().asTypedList(embedding.values_count),
      ),
      headIndex: embedding.head_index,
      headName: headName,
    );
  }, growable: false);
  return EmbeddingResult(
    embeddings: embeddings,
    timestampMs: value.has_timestamp_ms ? value.timestamp_ms : null,
  );
}

bindings.MpDelegate _delegate(MpDelegate delegate) => switch (delegate) {
  MpDelegate.cpu => bindings.MpDelegate.MP_DELEGATE_CPU,
  MpDelegate.gpu => bindings.MpDelegate.MP_DELEGATE_GPU,
  MpDelegate.edgeTpuNnapi => bindings.MpDelegate.MP_DELEGATE_EDGETPU_NNAPI,
  MpDelegate.liteRt => throw const MpException(
    MpStatus.unimplemented,
    'The MediaPipe v1.0 C runtime does not expose the LiteRT delegate.',
  ),
};

bindings.MpImageFormat _imageFormat(MpImageFormat format) => switch (format) {
  MpImageFormat.srgb => bindings.MpImageFormat.kMpImageFormatSrgb,
  MpImageFormat.srgba => bindings.MpImageFormat.kMpImageFormatSrgba,
  MpImageFormat.gray8 => bindings.MpImageFormat.kMpImageFormatGray8,
  MpImageFormat.gray16 => bindings.MpImageFormat.kMpImageFormatGray16,
  MpImageFormat.srgb48 => bindings.MpImageFormat.kMpImageFormatSrgb48,
  MpImageFormat.srgba64 => bindings.MpImageFormat.kMpImageFormatSrgba64,
  MpImageFormat.float32x1 => bindings.MpImageFormat.kMpImageFormatVec32F1,
  MpImageFormat.float32x2 => bindings.MpImageFormat.kMpImageFormatVec32F2,
  MpImageFormat.float32x4 => bindings.MpImageFormat.kMpImageFormatVec32F4,
};

MpImageFormat _dartImageFormat(bindings.MpImageFormat format) => switch (format) {
  bindings.MpImageFormat.kMpImageFormatSrgb => MpImageFormat.srgb,
  bindings.MpImageFormat.kMpImageFormatSrgba => MpImageFormat.srgba,
  bindings.MpImageFormat.kMpImageFormatGray8 => MpImageFormat.gray8,
  bindings.MpImageFormat.kMpImageFormatGray16 => MpImageFormat.gray16,
  bindings.MpImageFormat.kMpImageFormatSrgb48 => MpImageFormat.srgb48,
  bindings.MpImageFormat.kMpImageFormatSrgba64 => MpImageFormat.srgba64,
  bindings.MpImageFormat.kMpImageFormatVec32F1 => MpImageFormat.float32x1,
  bindings.MpImageFormat.kMpImageFormatVec32F2 => MpImageFormat.float32x2,
  bindings.MpImageFormat.kMpImageFormatVec32F4 => MpImageFormat.float32x4,
  bindings.MpImageFormat.kMpImageFormatUnknown => throw const MpException(
    MpStatus.dataLoss,
    'The native task returned an image with an unknown format.',
  ),
};

bindings.MpHostEnvironment _hostEnvironment() => switch (MpPlatform.current) {
  MpPlatform.android => bindings.MpHostEnvironment.MP_HOST_ENVIRONMENT_ANDROID,
  MpPlatform.ios => bindings.MpHostEnvironment.MP_HOST_ENVIRONMENT_IOS,
  MpPlatform.web => bindings.MpHostEnvironment.MP_HOST_ENVIRONMENT_WEB,
  _ => bindings.MpHostEnvironment.MP_HOST_ENVIRONMENT_UNKNOWN,
};

bindings.MpHostSystem _hostSystem() => switch (MpPlatform.current) {
  MpPlatform.linux => bindings.MpHostSystem.MP_HOST_SYSTEM_LINUX,
  MpPlatform.macos => bindings.MpHostSystem.MP_HOST_SYSTEM_MAC,
  MpPlatform.windows => bindings.MpHostSystem.MP_HOST_SYSTEM_WINDOWS,
  MpPlatform.ios => bindings.MpHostSystem.MP_HOST_SYSTEM_IOS,
  MpPlatform.android => bindings.MpHostSystem.MP_HOST_SYSTEM_ANDROID,
  _ => bindings.MpHostSystem.MP_HOST_SYSTEM_UNKNOWN,
};

extension<T> on List<T> {
  T? get lastOrNull => isEmpty ? null : last;
}
