@TestOn('vm')
library;

import 'dart:async';
import 'dart:io';

import 'package:crypto/crypto.dart' as crypto;
import 'package:mp_core/mp_core.dart';
// The generated bindings expose their own MpStatus, so hide it and keep the
// hand-written status enum used by the public API.
import 'package:mp_core/native.dart' as native;
import 'package:test/test.dart';

void main() {
  late Directory temporary;
  late HttpServer server;
  var requests = 0;
  final List<int> served = <int>[1, 2, 3, 4];

  setUp(() async {
    temporary = Directory.systemTemp.createTempSync('mp_model_cache_');
    requests = 0;
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((HttpRequest request) {
      requests += 1;
      final String path = request.uri.path;

      if (path.startsWith('/models/')) {
        request.response.add(served);
      } else if (path == '/redirect-relative') {
        request.response.statusCode = HttpStatus.found;
        request.response.headers.set(HttpHeaders.locationHeader, '/models/detector.task');
      } else if (path == '/redirect-absolute') {
        request.response.statusCode = HttpStatus.movedPermanently;
        request.response.headers.set(
          HttpHeaders.locationHeader,
          'http://127.0.0.1:${server.port}/models/detector.task',
        );
      } else if (path == '/redirect-off-host') {
        request.response.statusCode = HttpStatus.found;
        request.response.headers.set(HttpHeaders.locationHeader, 'http://10.255.255.1/stolen.task');
      } else if (path == '/redirect-file') {
        request.response.statusCode = HttpStatus.found;
        request.response.headers.set(HttpHeaders.locationHeader, 'file:///etc/passwd');
      } else if (path == '/redirect-loop') {
        request.response.statusCode = HttpStatus.found;
        request.response.headers.set(HttpHeaders.locationHeader, '/redirect-loop');
      } else if (path == '/redirect-missing-location') {
        request.response.statusCode = HttpStatus.temporaryRedirect;
      } else {
        request.response.statusCode = HttpStatus.notFound;
      }
      unawaited(request.response.close());
    });
  });

  tearDown(() async {
    await server.close(force: true);
    temporary.deleteSync(recursive: true);
  });

  Uri modelUri(String name) => Uri.parse('http://127.0.0.1:${server.port}/models/$name');

  String digestOf(List<int> bytes) => crypto.sha256.convert(bytes).toString();

  test('rejects a non-positive size limit', () {
    expect(() => native.ModelCache('.', maximumBytes: 0), throwsArgumentError);
  });

  test('downloads to a verified cache file and reuses it without a request', () async {
    final String digest = digestOf(served);
    final native.ModelCache cache = native.ModelCache('${temporary.path}/cache');

    final ModelAssetPath first = await cache.fetch(modelUri('detector.task'), digest);

    expect(File(first.path).readAsBytesSync(), served);
    expect(first.path, endsWith('$digest.task'));
    expect(requests, 1);

    final ModelAssetPath second = await cache.fetch(modelUri('detector.task'), digest);

    expect(second.path, first.path);
    expect(requests, 1);
  });

  test('re-downloads when the cached file no longer matches its digest', () async {
    final String digest = digestOf(served);
    final native.ModelCache cache = native.ModelCache('${temporary.path}/cache');

    final ModelAssetPath first = await cache.fetch(modelUri('detector.task'), digest);

    File(first.path).writeAsBytesSync(<int>[9, 9]);

    final ModelAssetPath second = await cache.fetch(modelUri('detector.task'), digest);

    expect(File(second.path).readAsBytesSync(), served);
    expect(requests, 2);
    expect(second.path, first.path);
  });

  test('fails with data loss on a digest mismatch and caches nothing', () async {
    final native.ModelCache cache = native.ModelCache('${temporary.path}/cache');

    await expectLater(
      cache.fetch(modelUri('detector.task'), 'a${digestOf(served).substring(1)}'),
      throwsA(
        isA<MpException>().having((MpException error) => error.status, 'status', MpStatus.dataLoss),
      ),
    );

    expect(
      Directory('${temporary.path}/cache').listSync().whereType<File>(),
      isEmpty,
      reason: 'A failed download must not leave a partial file behind.',
    );
  });

  test('fails with unavailable on an HTTP error and cleans the partial file', () async {
    final native.ModelCache cache = native.ModelCache('${temporary.path}/cache');

    await expectLater(
      cache.fetch(Uri.parse('http://127.0.0.1:${server.port}/missing.task'), digestOf(served)),
      throwsA(
        isA<MpException>().having(
          (MpException error) => error.status,
          'status',
          MpStatus.unavailable,
        ),
      ),
    );

    expect(Directory('${temporary.path}/cache').listSync().whereType<File>(), isEmpty);
  });

  test('enforces the configured remote size limit', () async {
    final native.ModelCache cache = native.ModelCache('${temporary.path}/cache', maximumBytes: 2);

    await expectLater(
      cache.fetch(modelUri('large.task'), digestOf(served)),
      throwsA(
        isA<MpException>().having(
          (MpException error) => error.status,
          'status',
          MpStatus.resourceExhausted,
        ),
      ),
    );

    expect(Directory('${temporary.path}/cache').listSync().whereType<File>(), isEmpty);
  });

  test('sanitizes the cached file name from the URI', () {
    final native.ModelCache cache = native.ModelCache('${temporary.path}/cache');
    final String digest = 'a' * 64;

    expect(
      cache.targetPath(Uri.parse('https://cdn.example.com/m.task'), digest),
      '${temporary.path}/cache/$digest.task',
    );
    expect(
      cache.targetPath(Uri.parse('https://cdn.example.com/very_long_extension012345678'), digest),
      '${temporary.path}/cache/$digest',
    );
    expect(
      cache.targetPath(Uri.parse('https://cdn.example.com'), digest),
      '${temporary.path}/cache/$digest',
    );
    expect(
      cache.targetPath(Uri.parse('https://cdn.example.com/model.tgz?from=..%2F..%2Fetc'), digest),
      '${temporary.path}/cache/$digest.tgz',
    );
  });

  test('resolveNativeModelAsset uses the cache when a directory is configured', () async {
    final String digest = digestOf(served);
    final ModelAsset asset = ModelAsset.uri(
      modelUri('detector.task'),
      sha256: digest,
      cacheDirectory: '${temporary.path}/cache',
    );

    final ModelAsset resolved = await native.resolveNativeModelAsset(asset);

    expect(resolved, isA<ModelAssetPath>());
    expect((resolved as ModelAssetPath).path, endsWith('$digest.task'));
    expect(File(resolved.path).readAsBytesSync(), served);
  });

  test('a cache directory requires a digest up front', () {
    expect(
      () => ModelAsset.uri(modelUri('detector.task'), cacheDirectory: '${temporary.path}/cache'),
      throwsArgumentError,
    );
    expect(
      () => ModelAsset.uri(modelUri('detector.task'), sha256: 'a' * 64, cacheDirectory: ' '),
      throwsArgumentError,
    );
  });

  test('the cache directory participates in value equality', () {
    final Uri uri = Uri.parse('https://cdn.example.com/m.task');
    final String digest = 'c' * 64;
    final ModelAsset cached = ModelAsset.uri(uri, sha256: digest, cacheDirectory: '/tmp/a');
    final ModelAsset same = ModelAsset.uri(uri, sha256: digest, cacheDirectory: '/tmp/a');
    final ModelAsset elsewhere = ModelAsset.uri(uri, sha256: digest, cacheDirectory: '/tmp/b');
    final ModelAsset uncached = ModelAsset.uri(uri, sha256: digest);

    expect(cached, same);
    expect(cached.hashCode, same.hashCode);
    expect(cached, isNot(elsewhere));
    expect(cached, isNot(uncached));
    expect(cached == cached, isTrue);
  });

  test('resolveNativeModelAsset downloads to bytes without a cache directory', () async {
    final ModelAsset resolved = await native.resolveNativeModelAsset(
      ModelAsset.uri(modelUri('detector.task'), sha256: digestOf(served)),
    );

    expect(resolved, isA<ModelAssetBytes>());
    expect((resolved as ModelAssetBytes).bytes, served);
    expect(resolved.name, 'detector.task');
  });

  test('resolveNativeModelAsset verifies the digest on the bytes path', () async {
    await expectLater(
      native.resolveNativeModelAsset(
        ModelAsset.uri(modelUri('detector.task'), sha256: 'b${digestOf(served).substring(1)}'),
      ),
      throwsA(
        isA<MpException>().having((MpException error) => error.status, 'status', MpStatus.dataLoss),
      ),
    );
  });

  test('follows a relative redirect and then verifies the digest', () async {
    final String digest = digestOf(served);

    final ModelAsset resolved = await native.resolveNativeModelAsset(
      ModelAsset.uri(
        Uri.parse('http://127.0.0.1:${server.port}/redirect-relative'),
        sha256: digest,
      ),
    );

    expect(resolved, isA<ModelAssetBytes>());
    expect((resolved as ModelAssetBytes).bytes, served);
    expect(requests, 2);
  });

  test('follows an absolute loopback redirect into the cache', () async {
    final String digest = digestOf(served);
    final native.ModelCache cache = native.ModelCache('${temporary.path}/cache');

    final ModelAssetPath asset = await cache.fetch(
      Uri.parse('http://127.0.0.1:${server.port}/redirect-absolute'),
      digest,
    );

    expect(File(asset.path).readAsBytesSync(), served);
    expect(requests, 2);
  });

  test('refuses a redirect off loopback and does not follow it', () async {
    final native.ModelCache cache = native.ModelCache('${temporary.path}/cache');

    await expectLater(
      cache.fetch(Uri.parse('http://127.0.0.1:${server.port}/redirect-off-host'), digestOf(served)),
      throwsA(
        isA<MpException>().having(
          (MpException error) => error.status,
          'status',
          MpStatus.invalidArgument,
        ),
      ),
    );

    expect(requests, 1);
    expect(Directory('${temporary.path}/cache').listSync().whereType<File>(), isEmpty);
  });

  test('refuses a redirect to a file URI', () async {
    await expectLater(
      native.resolveNativeModelAsset(
        ModelAsset.uri(Uri.parse('http://127.0.0.1:${server.port}/redirect-file')),
      ),
      throwsA(
        isA<MpException>().having(
          (MpException error) => error.status,
          'status',
          MpStatus.invalidArgument,
        ),
      ),
    );

    expect(requests, 1);
  });

  test('stops after five redirects', () async {
    await expectLater(
      native.resolveNativeModelAsset(
        ModelAsset.uri(Uri.parse('http://127.0.0.1:${server.port}/redirect-loop')),
      ),
      throwsA(
        isA<MpException>().having(
          (MpException error) => error.status,
          'status',
          MpStatus.unavailable,
        ),
      ),
    );

    expect(requests, 6);
  });

  test('rejects a redirect that omits Location', () async {
    await expectLater(
      native.resolveNativeModelAsset(
        ModelAsset.uri(Uri.parse('http://127.0.0.1:${server.port}/redirect-missing-location')),
      ),
      throwsA(
        isA<MpException>().having(
          (MpException error) => error.status,
          'status',
          MpStatus.unavailable,
        ),
      ),
    );
  });

  test('HTTPS stays allowed when loopback HTTP is not', () {
    expect(
      () => native.requireRemoteModelUri(
        Uri.parse('https://cdn.example.com/m.task'),
        allowLoopbackHttp: false,
      ),
      returnsNormally,
    );
    expect(
      () => native.requireRemoteModelUri(
        Uri.parse('http://127.0.0.1/m.task'),
        allowLoopbackHttp: false,
      ),
      throwsA(
        isA<MpException>().having(
          (MpException error) => error.status,
          'status',
          MpStatus.invalidArgument,
        ),
      ),
    );
    expect(
      () => native.requireRemoteModelUri(
        Uri.parse('http://127.0.0.1/m.task'),
        allowLoopbackHttp: true,
      ),
      returnsNormally,
    );
  });

  test('a file URI with a digest hashes the file before returning its path', () async {
    final File model = File('${temporary.path}/model.tflite')..writeAsBytesSync(served);
    final ModelAsset resolved = await native.resolveNativeModelAsset(
      ModelAsset.uri(model.uri, sha256: digestOf(served)),
    );

    expect(
      resolved,
      isA<ModelAssetPath>().having((ModelAssetPath asset) => asset.path, 'path', model.path),
    );
  });

  test('a file URI with the wrong digest fails before the path is used', () async {
    final File model = File('${temporary.path}/model.tflite')..writeAsBytesSync(served);

    await expectLater(
      native.resolveNativeModelAsset(
        ModelAsset.uri(model.uri, sha256: 'b${digestOf(served).substring(1)}'),
      ),
      throwsA(
        isA<MpException>().having((MpException error) => error.status, 'status', MpStatus.dataLoss),
      ),
    );
  });

  test('a missing file URI with a digest is not found', () async {
    await expectLater(
      native.resolveNativeModelAsset(
        ModelAsset.uri(Uri.file('${temporary.path}/missing.tflite'), sha256: digestOf(served)),
      ),
      throwsA(
        isA<MpException>().having((MpException error) => error.status, 'status', MpStatus.notFound),
      ),
    );
  });

  test('a directory presented as a file URI with a digest is not found', () async {
    await expectLater(
      native.resolveNativeModelAsset(ModelAsset.uri(temporary.uri, sha256: digestOf(served))),
      throwsA(
        isA<MpException>().having((MpException error) => error.status, 'status', MpStatus.notFound),
      ),
    );
  });

  test('only loopback plain HTTP is accepted', () async {
    expect(native.isLoopbackHttp(Uri.parse('http://127.0.0.1:9/m.task')), isTrue);
    expect(native.isLoopbackHttp(Uri.parse('http://localhost/m.task')), isTrue);
    expect(native.isLoopbackHttp(Uri.parse('http://[::1]:9/m.task')), isTrue);
    expect(native.isLoopbackHttp(Uri.parse('http://10.0.0.2/m.task')), isFalse);
    expect(native.isLoopbackHttp(Uri.parse('https://10.0.0.2/m.task')), isFalse);
    expect(native.isLoopbackHttp(Uri.parse('file:///m.task')), isFalse);

    await expectLater(
      native.resolveNativeModelAsset(ModelAsset.uri(Uri.parse('http://example.com/m.tflite'))),
      throwsA(
        isA<MpException>().having(
          (MpException error) => error.status,
          'status',
          MpStatus.invalidArgument,
        ),
      ),
    );
  });
}
