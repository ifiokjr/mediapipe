// Run with: dart run examples/bin/core_model_assets.dart
//
// Shows the parts of `mp_core` that every task depends on: model assets and
// their validation, image containers, audio containers, and the error contract.
// Nothing here loads a model or a native library, so it runs anywhere.

import 'dart:io';
import 'dart:typed_data';

import 'package:mp_core/mp_core.dart';

void main() {
  _modelAssets();
  _imageContainers();
  _audioContainers();
  _failureContract();
}

void _modelAssets() {
  stdout.writeln('== Model assets ==');

  // A path is the common native case.
  final ModelAsset path = ModelAsset.path('models/face_landmarker.task');
  stdout.writeln('  path    ${(path as ModelAssetPath).path}');

  // Bytes skip the filesystem entirely, which is how Flutter asset bundles and
  // downloaded models are usually handed to a task.
  final ModelAsset bytes = ModelAsset.bytes(Uint8List(128), name: 'tiny.tflite');
  stdout.writeln('  bytes   ${(bytes as ModelAssetBytes).bytes.length} bytes, name=${bytes.name}');

  // A URI is the only source the runtime will fetch, and a digest makes that
  // fetch tamper-evident.
  final ModelAsset remote = ModelAsset.uri(
    Uri.parse('https://cdn.example.com/models/gesture_recognizer/1/model.task'),
    sha256: '0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef',
  );
  stdout.writeln('  uri     ${(remote as ModelAssetUri).uri.host}');

  // Delegates are validated against each other rather than silently ignored.
  final BaseOptions gpu = BaseOptions(modelAsset: path, delegate: MpDelegate.gpu);
  stdout.writeln('  delegate ${gpu.delegate.name}');

  final BaseOptions liteRt = BaseOptions(
    modelAsset: path,
    delegate: MpDelegate.liteRt,
    liteRtOptions: LiteRtOptions(accelerator: LiteRtAccelerator.npu),
  );
  stdout.writeln('  liteRt  accelerator=${liteRt.liteRtOptions!.accelerator.name}');

  _expectArgumentError(
    () => BaseOptions(modelAsset: path, liteRtOptions: LiteRtOptions()),
    'liteRtOptions without MpDelegate.liteRt',
  );
  _expectArgumentError(
    () => ModelAsset.uri(Uri.parse('models/relative.tflite')),
    'a model URI without a scheme',
  );
  _expectArgumentError(
    () => ModelAsset.uri(Uri.parse('https://example.com/m.tflite'), sha256: 'not-a-digest'),
    'a malformed SHA-256 digest',
  );
}

void _imageContainers() {
  stdout.writeln('\n== Image containers ==');

  // A single-channel 8-bit image is one byte per pixel.
  final MpImage gray = MpImage.uint8(
    width: 4,
    height: 2,
    format: MpImageFormat.gray8,
    data: Uint8List(8)..fillRange(0, 8, 128),
  );
  stdout.writeln(
    '  gray8   ${gray.width}x${gray.height} '
    'samples=${gray.sampleCount} bytes=${gray.byteLength}',
  );

  // Three channels are three bytes per pixel, and the buffer length is checked
  // against the declared geometry.
  final MpImage rgb = MpImage.uint8(
    width: 2,
    height: 2,
    format: MpImageFormat.srgb,
    data: Uint8List(2 * 2 * 3),
  );
  stdout.writeln('  srgb    expected=${rgb.expectedSampleCount} actual=${rgb.sampleCount}');

  // Input transforms are validated up front so a bad rotation cannot reach a
  // native call.
  final ImageProcessingOptions options = ImageProcessingOptions(
    rotationDegrees: 90,
    regionOfInterest: NormalizedRect(left: 0.1, top: 0.1, right: 0.9, bottom: 0.9),
  );
  stdout.writeln('  rotate  ${options.rotationDegrees} deg with ROI');

  _expectArgumentError(
    () => MpImage.uint8(width: 4, height: 4, format: MpImageFormat.srgb, data: Uint8List(4)),
    'an image whose buffer does not match its dimensions',
  );
  _expectArgumentError(() => ImageProcessingOptions(rotationDegrees: 45), 'a 45 degree rotation');
  _expectArgumentError(
    () => NormalizedRect(left: 0.8, top: 0, right: 0.2, bottom: 1),
    'a rectangle whose left edge crosses its right edge',
  );
}

void _audioContainers() {
  stdout.writeln('\n== Audio containers ==');

  final AudioData clip = AudioData(
    samples: Float32List(16_000),
    sampleRateHz: 16_000,
    channelCount: 1,
  );
  stdout.writeln(
    '  ${clip.duration.inMilliseconds} ms at ${clip.sampleRateHz} Hz, '
    '${clip.channelCount} channel(s)',
  );

  _expectArgumentError(
    () => AudioData(samples: Float32List(0), sampleRateHz: 16_000, channelCount: 1),
    'an empty audio clip',
  );
}

void _failureContract() {
  stdout.writeln('\n== Failure contract ==');

  // Every native or platform failure is normalized onto the same status enum,
  // so callers can branch on a category instead of parsing messages.
  const MpException error = MpException(
    MpStatus.unimplemented,
    'Native audio stream mode requires the callback-copy bridge.',
    task: 'AudioClassifier',
  );
  stdout.writeln('  $error');
  stdout.writeln('  status code ${error.status.code} (${error.status.name})');

  // Timestamps must strictly increase, otherwise a frame could be applied out
  // of order.
  final TimestampTracker tracker = TimestampTracker();
  tracker.add(0);
  tracker.add(33);
  stdout.writeln('  last timestamp ${tracker.lastTimestampMs} ms');
  _expectArgumentError(() => tracker.add(33), 'a repeated timestamp');
  _expectArgumentError(() => tracker.add(10), 'a decreasing timestamp');
}

void _expectArgumentError(void Function() action, String description) {
  try {
    action();
    stdout.writeln('  UNEXPECTED: $description was accepted');
  } on ArgumentError catch (error) {
    stdout.writeln('  rejected $description: ${error.message}');
  }
}
