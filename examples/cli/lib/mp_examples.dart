/// Public MediaPipe test assets used by the examples and their tests.
///
/// Every entry points at Google's public `mediapipe-assets` bucket, which hosts
/// the same files the upstream MediaPipe test suites use. Each model is pinned
/// with the SHA-256 digest the SDK verifies at load time, so an example either
/// runs against the reviewed bytes or fails loudly.
library;

import 'dart:io';
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:image/image.dart' as img;
import 'package:mp_core/mp_core.dart';

/// A pinned test asset.
final class MpExampleAsset {
  /// Creates an asset description.
  const MpExampleAsset({required this.name, required this.url, required this.sha256});

  /// A short human-readable name used in example output.
  final String name;

  /// The absolute HTTPS source.
  final String url;

  /// The lowercase SHA-256 digest of the downloaded bytes.
  final String sha256;

  /// The asset as a digest-verified [ModelAsset].
  ModelAsset get modelAsset => ModelAsset.uri(Uri.parse(url), sha256: sha256);
}

const String _vision = 'https://storage.googleapis.com/mediapipe-assets/tasks/testdata/vision/';
const String _text = 'https://storage.googleapis.com/mediapipe-assets/tasks/testdata/text/';
const String _audio = 'https://storage.googleapis.com/mediapipe-assets/tasks/testdata/audio/';

/// Models used by the runnable examples.
abstract final class MpExampleModels {
  /// BlazeFace short-range face detector.
  static const MpExampleAsset faceDetector = MpExampleAsset(
    name: 'face_detection_short_range.tflite',
    url: '${_vision}face_detection_short_range.tflite',
    sha256: 'bbff11cebd1eb27a1e004cae0b0e63ec8c551cbf34a4451148b4908b8db3eca8',
  );

  /// MediaPipe face landmarker task bundle.
  static const MpExampleAsset faceLandmarker = MpExampleAsset(
    name: 'face_landmarker.task',
    url: '${_vision}face_landmarker.task',
    sha256: '7cf2bbf1842c429e9defee38e7f1c4238978d8a6faf2da145bb19846f86bd2f4',
  );

  /// MediaPipe hand landmarker task bundle.
  static const MpExampleAsset handLandmarker = MpExampleAsset(
    name: 'hand_landmarker.task',
    url: '${_vision}hand_landmarker.task',
    sha256: '32d1eab97e80a9a20edb29231e15301ce65abfd0fa9d41cf1757e0ecc8078a4e',
  );

  /// MediaPipe pose landmarker task bundle.
  static const MpExampleAsset poseLandmarker = MpExampleAsset(
    name: 'pose_landmarker.task',
    url: '${_vision}pose_landmarker.task',
    sha256: 'fb9cc326c88fc2a4d9a6d355c28520d5deacfbaa375b56243b0141b546080596',
  );

  /// ImageNet MobileNetV1 classifier.
  static const MpExampleAsset imageClassifier = MpExampleAsset(
    name: 'mobilenet_v1_0.25_224_quant.tflite',
    url: '${_vision}mobilenet_v1_0.25_224_quant.tflite',
    sha256: 'e480eb15572f86d3d5f1be6e83e35b3c7d509ab2bcec353707d1f614e14edca2',
  );

  /// MediaPipe language detector.
  static const MpExampleAsset languageDetector = MpExampleAsset(
    name: 'language_detector.tflite',
    url: '${_text}language_detector.tflite',
    sha256: '5f64d821110dd2a3280546e8cd59dff09547e25d5f5c9711ec3f03416414dbb2',
  );

  /// MobileBERT text embedder with metadata.
  static const MpExampleAsset textEmbedder = MpExampleAsset(
    name: 'mobilebert_embedding_with_metadata.tflite',
    url: '${_text}mobilebert_embedding_with_metadata.tflite',
    sha256: 'fa47142dcc6f446168bc672f2df9605b6da5d0c0d6264e9be62870282365b95c',
  );

  /// Universal Sentence Encoder QA text embedder.
  static const MpExampleAsset textEmbedderQa = MpExampleAsset(
    name: 'universal_sentence_encoder_qa_with_metadata.tflite',
    url: '${_text}universal_sentence_encoder_qa_with_metadata.tflite',
    sha256: '82c2d0450aa458adbec2f78eff33cfbf2a41b606b44246726ab67373926e32bc',
  );

  /// YAMNet audio classifier with metadata.
  static const MpExampleAsset audioClassifier = MpExampleAsset(
    name: 'yamnet_audio_classifier_with_metadata.tflite',
    url: '${_audio}yamnet_audio_classifier_with_metadata.tflite',
    sha256: '10c95ea3eb9a7bb4cb8bddf6feb023250381008177ac162ce169694d05c317de',
  );
}

/// Assets used as example inputs.
abstract final class MpExampleInputs {
  /// A 16 kHz mono WAV clip of speech.
  static const MpExampleAsset speech16k = MpExampleAsset(
    name: 'speech_16000_hz_mono.wav',
    url: '${_audio}speech_16000_hz_mono.wav',
    sha256: '71caf50b8757d6ab9cad5eae4d36669d3c20c225a51660afd7fe0dc44cdb74f6',
  );

  /// Two cats and a dog, used for detection and classification.
  static const MpExampleAsset catsAndDogs = MpExampleAsset(
    name: 'cats_and_dogs.jpg',
    url: '${_vision}cats_and_dogs.jpg',
    sha256: 'a2eaa7ad3a1aae4e623dd362a5f737e8a88d122597ecd1a02b3e1444db56df9c',
  );
}

/// A small on-disk cache for example assets.
///
/// Examples and their tests download the same handful of files, so caching
/// keeps repeated runs off the network. Set `MP_EXAMPLE_CACHE` to relocate it.
final class MpAssetCache {
  /// Creates a cache rooted at [directory].
  MpAssetCache(this.directory);

  /// Creates a cache under the system temporary directory, or `MP_EXAMPLE_CACHE`.
  factory MpAssetCache.defaults() {
    final String? override = Platform.environment['MP_EXAMPLE_CACHE'];
    if (override != null && override.isNotEmpty) return MpAssetCache(Directory(override));
    return MpAssetCache(Directory.systemTemp.createTempSync('mp_examples_'));
  }

  /// The cache root.
  final Directory directory;

  final Map<String, Uint8List> _memory = <String, Uint8List>{};

  /// Returns the bytes for [asset], downloading and caching them on first use.
  ///
  /// The digest is verified here rather than left to the runtime so an example
  /// fails with the expected and actual hashes instead of a task-creation error.
  Future<Uint8List> bytes(MpExampleAsset asset, {http.Client? client}) async {
    final Uint8List? cached = _memory[asset.url];
    if (cached != null) return cached;

    final File file = File('${directory.path}/${asset.name}');
    final Uint8List result;
    if (file.existsSync()) {
      result = file.readAsBytesSync();
    } else {
      final http.Client httpClient = client ?? http.Client();
      try {
        final http.Response response = await httpClient.get(Uri.parse(asset.url));
        if (response.statusCode != 200) {
          throw MpException(
            MpStatus.unavailable,
            'Could not download ${asset.name}: HTTP ${response.statusCode}.',
          );
        }
        result = response.bodyBytes;
        directory.createSync(recursive: true);
        file.writeAsBytesSync(result, flush: true);
      } finally {
        if (client == null) httpClient.close();
      }
    }
    _memory[asset.url] = result;
    return result;
  }

  /// Returns a digest-verified [ModelAsset] backed by the downloaded bytes.
  ///
  /// The runtime re-verifies the digest when it loads the model, so this only
  /// needs to hand over the bytes.
  Future<ModelAsset> model(MpExampleAsset asset, {http.Client? client}) async {
    final Uint8List data = await bytes(asset, client: client);
    return ModelAsset.bytes(data, name: asset.name);
  }
}

/// Decodes [bytes] into an [MpImage].
///
/// MediaPipe vision tasks accept tightly packed pixel buffers, so this converts
/// whatever JPEG or PNG the asset contains into 8-bit sRGB. Set [width] and
/// [height] to resize; classifier models usually require a fixed input size.
MpImage mpImageFromBytes(Uint8List bytes, {int? width, int? height}) {
  img.Image? decoded = img.decodeImage(bytes);
  if (decoded == null) {
    throw const MpException(MpStatus.invalidArgument, 'The example image could not be decoded.');
  }
  if (width != null && height != null && (decoded.width != width || decoded.height != height)) {
    decoded = img.copyResize(
      decoded,
      width: width,
      height: height,
      interpolation: img.Interpolation.linear,
    );
  }
  final img.Image rgb = decoded.numChannels == 3 ? decoded : decoded.convert(numChannels: 3);
  return MpImage.uint8(
    width: rgb.width,
    height: rgb.height,
    format: MpImageFormat.srgb,
    data: Uint8List.fromList(rgb.getBytes(order: img.ChannelOrder.rgb)),
  );
}

/// Decodes 16-bit PCM WAV [bytes] into mono [AudioData].
///
/// MediaPipe audio models expect mono float samples at a fixed sample rate.
/// Channel 0 is used when the file is stereo, and the sample rate is reported
/// unchanged so the caller can decide whether resampling is required.
AudioData mpAudioFromWav(Uint8List bytes) {
  if (bytes.length < 44 ||
      String.fromCharCodes(bytes.sublist(0, 4)) != 'RIFF' ||
      String.fromCharCodes(bytes.sublist(8, 12)) != 'WAVE') {
    throw const MpException(MpStatus.invalidArgument, 'The example audio is not a RIFF WAVE file.');
  }

  var offset = 12;
  var channelCount = 1;
  var sampleRate = 16_000;
  var bitsPerSample = 16;
  Uint8List? samples;

  while (offset + 8 <= bytes.length) {
    final String chunkId = String.fromCharCodes(bytes.sublist(offset, offset + 4));
    final int chunkSize = ByteData.sublistView(
      bytes,
      offset + 4,
      offset + 8,
    ).getUint32(0, Endian.little);
    final int body = offset + 8;
    if (chunkId == 'fmt ' && body + 16 <= bytes.length) {
      channelCount = ByteData.sublistView(bytes, body + 2, body + 4).getUint16(0, Endian.little);
      sampleRate = ByteData.sublistView(bytes, body + 4, body + 8).getUint32(0, Endian.little);
      bitsPerSample = ByteData.sublistView(bytes, body + 14, body + 16).getUint16(0, Endian.little);
    } else if (chunkId == 'data') {
      final int end = (body + chunkSize).clamp(body, bytes.length);
      samples = Uint8List.sublistView(bytes, body, end);
    }
    offset = body + chunkSize + (chunkSize.isOdd ? 1 : 0);
  }

  if (samples == null) {
    throw const MpException(MpStatus.invalidArgument, 'The example audio has no data chunk.');
  }
  if (bitsPerSample != 16) {
    throw MpException(
      MpStatus.unimplemented,
      'The example decoder supports 16-bit PCM WAV, found $bitsPerSample-bit samples.',
    );
  }

  final Float32List mono = Float32List(samples.length ~/ 2 ~/ channelCount);
  for (var frame = 0; frame < mono.length; frame++) {
    final int byteOffset = frame * channelCount * 2;
    mono[frame] =
        ByteData.sublistView(samples, byteOffset, byteOffset + 2).getInt16(0, Endian.little) /
        32768.0;
  }
  return AudioData(samples: mono, sampleRateHz: sampleRate.toDouble(), channelCount: 1);
}
