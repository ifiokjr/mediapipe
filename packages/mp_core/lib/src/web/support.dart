import 'dart:js_interop';
import 'dart:js_interop_unsafe';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

import '../containers.dart';
import '../errors.dart';
import '../image.dart';
import '../options.dart';

/// Matches the native runtime's remote-model safety limit.
const int _maximumRemoteModelBytes = 512 * 1024 * 1024;

/// A pinned ECMAScript module and its adjacent MediaPipe Wasm directory.
final class WebTaskAssets {
  /// Creates a web asset location.
  const WebTaskAssets({required this.moduleUri, required this.wasmRoot});

  /// URI of the official MediaPipe `.mjs` task bundle.
  final Uri moduleUri;

  /// Directory containing the unrenamed MediaPipe Wasm loader and binary.
  final Uri wasmRoot;
}

/// Imports an ECMAScript module without requiring a script tag in `index.html`.
Future<JSObject> importWebTaskModule(Uri moduleUri) async {
  try {
    return await importModule(moduleUri.toString().toJS).toDart;
  } on Object catch (error) {
    throw MpException(
      MpStatus.unavailable,
      'Could not load the MediaPipe web runtime from $moduleUri.',
      cause: error,
    );
  }
}

/// Calls a JavaScript method with a bounded list of arguments.
R callWebMethod<R extends JSAny?>(
  JSObject receiver,
  String method, [
  List<JSAny?> arguments = const <JSAny?>[],
]) => receiver.callMethodVarArgs<R>(method.toJS, arguments);

/// Gets a required JavaScript object property.
JSObject requireWebObject(JSObject receiver, String property) {
  final JSAny? value = receiver[property];

  if (value.isUndefinedOrNull || !value.isA<JSObject>()) {
    throw MpException(MpStatus.internal, 'The MediaPipe web runtime did not expose `$property`.');
  }

  return value as JSObject;
}

/// Converts a Dart JSON-like value to a JavaScript value.
JSAny? webJsify(Object? value) => value.jsify();

/// Converts a JavaScript result containing plain objects and typed arrays.
Object? webDartify(JSAny? value) => value.dartify();

/// Maps common model options to the MediaPipe Tasks web API.
Map<String, Object?> webBaseOptions(BaseOptions options) {
  final Map<String, Object?> baseOptions = <String, Object?>{};

  switch (options.modelAsset) {
    case ModelAssetPath(path: final String path):
      baseOptions['modelAssetPath'] = path;
    case ModelAssetUri(uri: final Uri uri):
      baseOptions['modelAssetPath'] = uri.toString();
    case ModelAssetBytes(bytes: final Uint8List bytes):
      baseOptions['modelAssetBuffer'] = Uint8List.fromList(bytes);
  }

  baseOptions['delegate'] = switch (options.delegate) {
    MpDelegate.cpu => 'CPU',
    MpDelegate.gpu => 'GPU',
    MpDelegate.edgeTpuNnapi || MpDelegate.liteRt => throw MpException(
      MpStatus.invalidArgument,
      '${options.delegate.name} is not available in the MediaPipe web runtime.',
    ),
  };

  return baseOptions;
}

/// Resolves model options and verifies checksum-pinned remote models in Dart.
Future<Map<String, Object?>> resolveWebBaseOptions(BaseOptions options) async {
  if (options.modelAsset case ModelAssetUri(
    uri: final Uri uri,
    sha256: final String? expected,
  ) when expected != null) {
    final Uint8List bytes = await _downloadWebBytes(uri);
    final String actual = sha256.convert(bytes).toString();

    if (actual != expected) {
      throw MpException(
        MpStatus.dataLoss,
        'Model checksum mismatch for $uri: expected $expected, received $actual.',
      );
    }
    return webBaseOptions(
      BaseOptions(
        modelAsset: ModelAsset.bytes(bytes, name: uri.pathSegments.last),
        delegate: options.delegate,
        liteRtOptions: options.liteRtOptions,
      ),
    );
  }

  return webBaseOptions(options);
}

Future<Uint8List> _downloadWebBytes(Uri uri) async {
  try {
    final JSPromise<JSObject> responsePromise = globalContext.callMethod<JSPromise<JSObject>>(
      'fetch'.toJS,
      uri.toString().toJS,
    );
    final JSObject response = await responsePromise.toDart;
    final JSAny? ok = response['ok'];

    if (ok == null || !ok.isA<JSBoolean>() || !(ok as JSBoolean).toDart) {
      final Object? status = webDartify(response['status']);
      throw MpException(MpStatus.unavailable, 'Model download failed with HTTP status $status.');
    }

    final JSPromise<JSArrayBuffer> bufferPromise = callWebMethod<JSPromise<JSArrayBuffer>>(
      response,
      'arrayBuffer',
    );

    final JSArrayBuffer buffer = await bufferPromise.toDart;

    final Uint8List bytes = Uint8List.view(buffer.toDart);
    if (bytes.length > _maximumRemoteModelBytes) {
      throw const MpException(
        MpStatus.resourceExhausted,
        'The remote model exceeds the 512 MiB safety limit.',
      );
    }
    return bytes;
  } on MpException {
    rethrow;
  } on Object catch (error) {
    throw MpException(
      MpStatus.unavailable,
      'Could not download the model from $uri.',
      cause: error,
    );
  }
}

/// Maps common classifier filtering options to the web API.
Map<String, Object?> webClassifierOptions(ClassifierOptions? options) {
  if (options == null) return <String, Object?>{};
  return <String, Object?>{
    if (options.displayNamesLocale case final String locale) 'displayNamesLocale': locale,
    if (options.maxResults case final int maxResults) 'maxResults': maxResults,
    if (options.scoreThreshold case final double threshold) 'scoreThreshold': threshold,
    if (options.categoryAllowlist.isNotEmpty) 'categoryAllowlist': options.categoryAllowlist,
    if (options.categoryDenylist.isNotEmpty) 'categoryDenylist': options.categoryDenylist,
  };
}

/// Maps common embedder options to the web API.
Map<String, Object?> webEmbedderOptions(EmbedderOptions options) => <String, Object?>{
  'l2Normalize': options.l2Normalize,
  'quantize': options.quantize,
};

/// Converts a JavaScript number into a Dart integer without trusting its shape.
int? webOptionalInt(Object? value) => switch (value) {
  final int number => number,
  final num number => number.toInt(),
  _ => null,
};

/// Converts a JSON-like MediaPipe web classification result.
///
/// Every field is validated so a malformed runtime response surfaces as an
/// [MpException] instead of a null-check or cast error.
ClassificationResult webClassificationResult(Map<Object?, Object?> result) {
  final List<Object?> heads = _requireList(result['classifications'], 'classifications');
  return ClassificationResult(
    timestampMs: webOptionalInt(result['timestampMs']),
    classifications: heads.map((Object? value) {
      final Map<Object?, Object?> head = _requireMap(value, 'classification head');
      final List<Object?> categories = _requireList(head['categories'], 'categories');
      return Classifications(
        headIndex: _requireInt(head['headIndex'], 'headIndex'),
        headName: _optionalString(head['headName'], 'headName'),
        categories: categories.map((Object? categoryValue) {
          final Map<Object?, Object?> category = _requireMap(categoryValue, 'category');
          return Category(
            index: _requireInt(category['index'], 'category index'),
            score: _requireDouble(category['score'], 'category score'),
            categoryName: _optionalString(category['categoryName'], 'categoryName'),
            displayName: _optionalString(category['displayName'], 'displayName'),
          );
        }),
      );
    }),
  );
}

List<Object?> _requireList(Object? value, String field) {
  if (value is! List<Object?>) {
    throw _malformedResult(field);
  }
  return value;
}

Map<Object?, Object?> _requireMap(Object? value, String field) {
  if (value is! Map<Object?, Object?>) {
    throw _malformedResult(field);
  }
  return value;
}

int _requireInt(Object? value, String field) {
  if (value is num) return value.toInt();
  throw _malformedResult(field);
}

double _requireDouble(Object? value, String field) {
  if (value is num) return value.toDouble();
  throw _malformedResult(field);
}

String? _optionalString(Object? value, String field) {
  if (value == null) return null;
  if (value is String) return webEmptyToNull(value);
  throw _malformedResult(field);
}

MpException _malformedResult(String field) => MpException(
  MpStatus.internal,
  'The MediaPipe web runtime returned a malformed result: expected $field.',
);

/// Treats MediaPipe's empty optional strings as absent values.
String? webEmptyToNull(String? value) => value == null || value.isEmpty ? null : value;

/// Converts an immutable [MpImage] into browser `ImageData`.
///
/// Browser image sources are eight-bit RGBA. Higher precision formats are
/// deterministically converted to that representation at this boundary.
JSObject webImageData(MpImage image) {
  final Uint8ClampedList rgba = Uint8ClampedList(image.width * image.height * 4);
  final int pixelCount = image.width * image.height;

  // Resolve the storage subtype once per image rather than once per pixel.
  switch (image) {
    case MpImageUint8(:final format, :final data):
      for (
        int pixel = 0, input = 0, output = 0;
        pixel < pixelCount;
        pixel += 1, input += format.channels, output += 4
      ) {
        _writeUint8Pixel(rgba, output, data, input, format);
      }
    case MpImageUint16(:final format, :final data):
      for (
        int pixel = 0, input = 0, output = 0;
        pixel < pixelCount;
        pixel += 1, input += format.channels, output += 4
      ) {
        _writeUint16Pixel(rgba, output, data, input, format);
      }
    case MpImageFloat32(:final format, :final data):
      for (
        int pixel = 0, input = 0, output = 0;
        pixel < pixelCount;
        pixel += 1, input += format.channels, output += 4
      ) {
        _writeFloatPixel(rgba, output, data, input, format);
      }
  }

  final JSAny? constructor = globalContext['ImageData'];

  if (constructor == null || !constructor.isA<JSFunction>()) {
    throw const MpException(MpStatus.unavailable, 'This browser does not expose ImageData.');
  }
  return (constructor as JSFunction).callAsConstructor<JSObject>(
    rgba.toJS,
    image.width.toJS,
    image.height.toJS,
  );
}

void _writeUint8Pixel(
  Uint8ClampedList output,
  int outputOffset,
  Uint8List input,
  int inputOffset,
  MpImageFormat format,
) {
  switch (format) {
    case MpImageFormat.srgb:
      output.setRange(outputOffset, outputOffset + 3, input, inputOffset);
      output[outputOffset + 3] = 255;
    case MpImageFormat.srgba:
      output.setRange(outputOffset, outputOffset + 4, input, inputOffset);
    case MpImageFormat.gray8:
      final int value = input[inputOffset];
      output[outputOffset] = value;
      output[outputOffset + 1] = value;
      output[outputOffset + 2] = value;
      output[outputOffset + 3] = 255;
    case MpImageFormat.gray16 ||
        MpImageFormat.srgb48 ||
        MpImageFormat.srgba64 ||
        MpImageFormat.float32x1 ||
        MpImageFormat.float32x2 ||
        MpImageFormat.float32x4:
      throw StateError('Unexpected ${format.name} storage.');
  }
}

void _writeUint16Pixel(
  Uint8ClampedList output,
  int outputOffset,
  Uint16List input,
  int inputOffset,
  MpImageFormat format,
) {
  int byte(int channel) => (input[inputOffset + channel] / 257).round();

  switch (format) {
    case MpImageFormat.gray16:
      final int value = byte(0);
      output[outputOffset] = value;
      output[outputOffset + 1] = value;
      output[outputOffset + 2] = value;
      output[outputOffset + 3] = 255;
    case MpImageFormat.srgb48:
      output[outputOffset] = byte(0);
      output[outputOffset + 1] = byte(1);
      output[outputOffset + 2] = byte(2);
      output[outputOffset + 3] = 255;
    case MpImageFormat.srgba64:
      output[outputOffset] = byte(0);
      output[outputOffset + 1] = byte(1);
      output[outputOffset + 2] = byte(2);
      output[outputOffset + 3] = byte(3);
    case MpImageFormat.srgb ||
        MpImageFormat.srgba ||
        MpImageFormat.gray8 ||
        MpImageFormat.float32x1 ||
        MpImageFormat.float32x2 ||
        MpImageFormat.float32x4:
      throw StateError('Unexpected ${format.name} storage.');
  }
}

void _writeFloatPixel(
  Uint8ClampedList output,
  int outputOffset,
  Float32List input,
  int inputOffset,
  MpImageFormat format,
) {
  int byte(int channel) => (input[inputOffset + channel].clamp(0, 1) * 255).round();

  switch (format) {
    case MpImageFormat.float32x1:
      final int value = byte(0);
      output[outputOffset] = value;
      output[outputOffset + 1] = value;
      output[outputOffset + 2] = value;
      output[outputOffset + 3] = 255;
    case MpImageFormat.float32x2:
      output[outputOffset] = byte(0);
      output[outputOffset + 1] = byte(1);
      output[outputOffset + 2] = 0;
      output[outputOffset + 3] = 255;
    case MpImageFormat.float32x4:
      output[outputOffset] = byte(0);
      output[outputOffset + 1] = byte(1);
      output[outputOffset + 2] = byte(2);
      output[outputOffset + 3] = byte(3);
    case MpImageFormat.srgb ||
        MpImageFormat.srgba ||
        MpImageFormat.gray8 ||
        MpImageFormat.gray16 ||
        MpImageFormat.srgb48 ||
        MpImageFormat.srgba64:
      throw StateError('Unexpected ${format.name} storage.');
  }
}
