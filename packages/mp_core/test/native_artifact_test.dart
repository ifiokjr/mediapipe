import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:crypto/crypto.dart';
import 'package:test/test.dart';

import '../hook/native_artifact.dart';

void main() {
  test('catalog accepts HTTPS artifacts with lowercase digests', () {
    final NativeArtifactCatalog catalog = NativeArtifactCatalog.parse(
      jsonEncode(<String, Object>{
        'schemaVersion': 1,
        'mediaPipeVersion': 'v1.0.0',
        'artifacts': <String, Object>{
          'linux-x64': <String, Object>{
            'url': 'https://example.com/mediapipe.zip',
            'sha256': 'a' * 64,
          },
        },
      }),
    );

    expect(catalog.mediaPipeVersion, 'v1.0.0');
    expect(catalog.artifacts['linux-x64']?.uri.host, 'example.com');
  });

  test('downloads and verifies an archive before exposing libraries', () async {
    final Directory output = await Directory.systemTemp.createTemp('mp-native-test-');
    final List<int> library = <int>[1, 3, 3, 7];
    final List<int> archive = _archiveBytes(<String, List<int>>{
      'libmediapipe.so': library,
      'manifest.json': utf8.encode(
        jsonEncode(<String, Object>{
          'mediaPipeVersion': 'v1.0.0',
          'target': 'linux-x64',
          'libraries': <String, String>{'libmediapipe.so': sha256.convert(library).toString()},
        }),
      ),
    });
    final HttpServer server = await _serve(archive);
    addTearDown(() async {
      await server.close(force: true);
      if (output.existsSync()) output.deleteSync(recursive: true);
    });

    final Directory resolved = await resolveNativeArtifact(
      artifact: NativeArtifact(
        mediaPipeVersion: 'v1.0.0',
        target: 'linux-x64',
        uri: Uri.parse('http://${server.address.host}:${server.port}/artifact.zip'),
        sha256: sha256.convert(archive).toString(),
      ),
      sharedOutputDirectory: output.uri,
    );

    expect(File.fromUri(resolved.uri.resolve('libmediapipe.so')).readAsBytesSync(), library);
    expect(File.fromUri(resolved.uri.resolve('.ready')).existsSync(), isTrue);
  });

  test('rejects an archive whose outer checksum does not match', () async {
    final Directory output = await Directory.systemTemp.createTemp('mp-native-test-');
    final List<int> archive = _archiveBytes(<String, List<int>>{
      'manifest.json': utf8.encode('{}'),
    });
    final HttpServer server = await _serve(archive);
    addTearDown(() async {
      await server.close(force: true);
      if (output.existsSync()) output.deleteSync(recursive: true);
    });

    await expectLater(
      resolveNativeArtifact(
        artifact: NativeArtifact(
          mediaPipeVersion: 'v1.0.0',
          target: 'linux-x64',
          uri: Uri.parse('http://${server.address.host}:${server.port}/artifact.zip'),
          sha256: '0' * 64,
        ),
        sharedOutputDirectory: output.uri,
      ),
      throwsStateError,
    );
    expect(
      Directory.fromUri(output.uri.resolve('mp_core/linux-x64-${'0' * 64}/')).existsSync(),
      isFalse,
    );
  });
}

List<int> _archiveBytes(Map<String, List<int>> files) {
  final Archive archive = Archive();
  for (final MapEntry<String, List<int>> entry in files.entries) {
    archive.add(ArchiveFile.bytes(entry.key, entry.value));
  }
  return ZipEncoder().encodeBytes(archive, modified: DateTime.utc(1980));
}

Future<HttpServer> _serve(List<int> responseBytes) async {
  final HttpServer server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
  server.listen((HttpRequest request) async {
    request.response
      ..statusCode = HttpStatus.ok
      ..contentLength = responseBytes.length
      ..add(responseBytes);
    await request.response.close();
  });
  return server;
}
