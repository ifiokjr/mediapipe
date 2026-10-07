import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart' as crypto;
import 'package:http/http.dart' as http;
import 'package:image/image.dart' as img;
import 'package:mp_core/mp_core.dart';
import 'package:mp_examples/mp_examples.dart';
import 'package:test/test.dart';

void main() {
  test('downloads an asset, verifies its digest, and caches it on disk', () async {
    final Directory root = await Directory.systemTemp.createTemp('mp_examples_test_');
    addTearDown(() => root.deleteSync(recursive: true));
    final List<int> payload = <int>[1, 2, 3, 4];
    final _ServedAsset served = await _serve(payload);

    final MpAssetCache cache = MpAssetCache(root);
    final MpExampleAsset asset = MpExampleAsset(
      name: served.name,
      url: served.url,
      sha256: crypto.sha256.convert(payload).toString(),
    );

    expect(await cache.bytes(asset, client: http.Client()), payload);
    expect(File('${root.path}/${served.name}').existsSync(), isTrue);
  });

  test('rejects downloaded bytes whose digest does not match', () async {
    final Directory root = await Directory.systemTemp.createTemp('mp_examples_test_');
    addTearDown(() => root.deleteSync(recursive: true));
    final _ServedAsset served = await _serve(<int>[9, 9]);

    final MpAssetCache cache = MpAssetCache(root);
    final MpExampleAsset asset = MpExampleAsset(
      name: served.name,
      url: served.url,
      sha256: crypto.sha256.convert(<int>[1]).toString(),
    );

    await expectLater(
      cache.bytes(asset, client: http.Client()),
      throwsA(
        isA<MpException>()
            .having((error) => error.message, 'message', contains('digest mismatch'))
            .having((error) => error.message, 'message', contains('got')),
      ),
    );
    expect(cache.directory.listSync(), isEmpty);
  });

  test('re-verifies a corrupted cache file instead of trusting it', () async {
    final Directory root = await Directory.systemTemp.createTemp('mp_examples_test_');
    addTearDown(() => root.deleteSync(recursive: true));
    final List<int> payload = <int>[1, 2, 3];
    final _ServedAsset served = await _serve(payload);

    final MpExampleAsset asset = MpExampleAsset(
      name: served.name,
      url: served.url,
      sha256: crypto.sha256.convert(payload).toString(),
    );
    expect(await MpAssetCache(root).bytes(asset, client: http.Client()), payload);

    File('${root.path}/${served.name}').writeAsBytesSync(<int>[7, 7, 7]);
    await expectLater(
      MpAssetCache(root).bytes(asset, client: http.Client()),
      throwsA(isA<MpException>().having((error) => error.status, 'status', MpStatus.dataLoss)),
    );
  });

  test('reports a failed download with the HTTP status', () async {
    final Directory root = await Directory.systemTemp.createTemp('mp_examples_test_');
    addTearDown(() => root.deleteSync(recursive: true));
    final HttpServer server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((HttpRequest request) async {
      request.response
        ..statusCode = HttpStatus.notFound
        ..contentLength = 0;
      await request.response.close();
    });
    addTearDown(() => server.close(force: true));

    final MpAssetCache cache = MpAssetCache(root);
    final MpExampleAsset asset = MpExampleAsset(
      name: 'missing.bin',
      url: 'http://${server.address.host}:${server.port}/missing.bin',
      sha256: '0' * 64,
    );

    await expectLater(
      cache.bytes(asset, client: http.Client()),
      throwsA(isA<MpException>().having((error) => error.status, 'status', MpStatus.unavailable)),
    );
  });

  test('mpAudioFromWav decodes mono 16-bit PCM with metadata', () {
    final Uint8List wav = _wav(
      sampleRate: 8000,
      channelCount: 1,
      samples: <int>[0, 0, 0, 128, 255, 127],
    );

    final AudioData audio = mpAudioFromWav(wav);

    expect(audio.sampleRateHz, 8000);
    expect(audio.channelCount, 1);
    // Little-endian int16 frames: 0, -32768, 32767.
    expect(audio.samples, <double>[0, -1, 32767 / 32768]);
    expect(audio.frameCount, 3);
  });

  test('mpAudioFromWav downmixes stereo and rejects non-PCM16 files', () {
    final Uint8List stereo = _wav(
      sampleRate: 16000,
      channelCount: 2,
      samples: <int>[
        0, 0, 0, 0, // frame 0: L=0, R=0
        255, 127, 255, 127, // frame 1: both max
      ],
    );

    final Float32List mono = mpAudioFromWav(stereo).samples;
    expect(mono[0], 0);
    expect(mono[1], closeTo(1, 1e-4));

    final Uint8List notWave = Uint8List(64);
    expect(() => mpAudioFromWav(notWave), throwsA(isA<MpException>()));
  });

  test('mpImageFromBytes decodes PNG pixels and resizes on request', () {
    final List<int> png = _png2x2();
    final MpImage native = mpImageFromBytes(Uint8List.fromList(png));

    expect(native.width, 2);
    expect(native.height, 2);
    expect(native.format, MpImageFormat.srgb);
    expect((native as MpImageUint8).data.length, 12);

    final MpImage resized = mpImageFromBytes(Uint8List.fromList(png), width: 4, height: 4);
    expect(resized.width, 4);
    expect(resized.height, 4);

    expect(() => mpImageFromBytes(Uint8List.fromList(<int>[1, 2, 3])), throwsA(isA<MpException>()));
  });
}

Future<_ServedAsset> _serve(List<int> payload) async {
  final String name = 'asset-${payload.length}-${DateTime.now().microsecondsSinceEpoch}.bin';
  final HttpServer server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
  server.listen((HttpRequest request) async {
    request.response
      ..statusCode = HttpStatus.ok
      ..contentLength = payload.length
      ..add(payload);
    await request.response.close();
  });

  return _ServedAsset(name, 'http://${server.address.host}:${server.port}/$name', server);
}

final class _ServedAsset {
  const _ServedAsset(this.name, this.url, this.server);

  final String name;
  final String url;
  final HttpServer server;
}

/// Builds a minimal RIFF WAVE file with 16-bit PCM [samples].
Uint8List _wav({required int sampleRate, required int channelCount, required List<int> samples}) {
  final ByteData bytes = ByteData(44 + samples.length);
  void ascii(int offset, String value) {
    for (int index = 0; index < value.length; index += 1) {
      bytes.setUint8(offset + index, value.codeUnitAt(index));
    }
  }

  ascii(0, 'RIFF');
  bytes.setUint32(4, 36 + samples.length, Endian.little);
  ascii(8, 'WAVE');
  ascii(12, 'fmt ');
  bytes.setUint32(16, 16, Endian.little);
  bytes.setUint16(20, 1, Endian.little); // PCM.
  bytes.setUint16(22, channelCount, Endian.little);
  bytes.setUint32(24, sampleRate, Endian.little);
  bytes.setUint32(28, sampleRate * channelCount * 2, Endian.little);
  bytes.setUint16(32, channelCount * 2, Endian.little);
  bytes.setUint16(34, 16, Endian.little);
  ascii(36, 'data');
  bytes.setUint32(40, samples.length, Endian.little);
  for (int index = 0; index < samples.length; index += 1) {
    bytes.setUint8(44 + index, samples[index]);
  }

  return bytes.buffer.asUint8List();
}

List<int> _png2x2() {
  final img.Image image = img.Image(width: 2, height: 2);
  image.setPixelRgb(0, 0, 255, 0, 0);
  image.setPixelRgb(1, 1, 0, 255, 0);

  return img.encodePng(image);
}
