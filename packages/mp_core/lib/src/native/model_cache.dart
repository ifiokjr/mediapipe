import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';

import '../errors.dart';
import '../options.dart';

/// The largest model a remote URI may deliver.
const int maximumRemoteModelBytes = 512 * 1024 * 1024;

/// Redirects followed for one model download before giving up.
const int _maximumModelRedirects = 5;

/// Whether [uri] is plain HTTP aimed at this machine.
///
/// Remote models must arrive over HTTPS; loopback is exempted so applications
/// and tests can serve models from a local development server. Digest
/// verification applies to loopback downloads exactly as it does to HTTPS.
bool isLoopbackHttp(Uri uri) {
  if (uri.scheme != 'http') return false;

  return switch (uri.host) {
    'localhost' || '127.0.0.1' || '[::1]' || '::1' => true,
    _ => false,
  };
}

/// Rejects a remote model [uri] that is not an allowed transport.
///
/// HTTPS is always accepted. Plain HTTP is accepted only when
/// [allowLoopbackHttp] is set and [uri] is loopback, which is true for an
/// original loopback URI and for redirects that stay there. Redirects from an
/// HTTPS URL pass `false`, so they cannot downgrade to HTTP or target loopback.
void requireRemoteModelUri(Uri uri, {required bool allowLoopbackHttp}) {
  if (uri.scheme == 'https') return;
  if (allowLoopbackHttp && isLoopbackHttp(uri)) return;

  throw const MpException(
    MpStatus.invalidArgument,
    'Native model URIs must use HTTPS (plain HTTP is accepted only on '
    'loopback, so local development servers stay testable) or the file '
    'scheme.',
  );
}

/// Opens [uri] without letting [HttpClient] follow redirects on its own.
///
/// Each hop is checked with [requireRemoteModelUri]. Loopback HTTP stays
/// allowed only when [uri] itself is loopback HTTP; an HTTPS URL cannot be
/// redirected onto loopback or onto plain HTTP. More than five redirects fails
/// with [MpStatus.unavailable].
Future<HttpClientResponse> openRemoteModel(HttpClient client, Uri uri) async {
  final bool allowLoopbackHttp = isLoopbackHttp(uri);
  Uri current = uri;

  for (int followed = 0; ; followed += 1) {
    requireRemoteModelUri(current, allowLoopbackHttp: allowLoopbackHttp);
    final HttpClientRequest request = await client.getUrl(current);
    request.followRedirects = false;
    final HttpClientResponse response = await request.close();

    if (!response.isRedirect) return response;

    if (followed >= _maximumModelRedirects) {
      await response.drain<void>();
      throw const MpException(MpStatus.unavailable, 'The model download exceeded 5 redirects.');
    }

    final String? location = response.headers.value(HttpHeaders.locationHeader);
    await response.drain<void>();

    if (location == null || location.trim().isEmpty) {
      throw const MpException(
        MpStatus.unavailable,
        'The model download redirect did not include a Location header.',
      );
    }

    current = current.resolve(location.trim());
  }
}

/// Whether [file] contains bytes whose SHA-256 digest is [digest].
Future<bool> fileMatchesDigest(File file, String digest) async {
  final _DigestCollector collector = _DigestCollector();
  final ByteConversionSink hasher = sha256.startChunkedConversion(collector);

  await for (final List<int> chunk in file.openRead()) {
    hasher.add(chunk);
  }
  hasher.close();

  return collector.value.toString() == digest;
}

/// A content-addressed cache for digest-pinned models.
///
/// [fetch] returns a path asset for a model, downloading it only when the
/// cached file is missing or fails verification. The SHA-256 digest is the
/// cache key, so verifying a hit costs one file read rather than a download,
/// and a corrupted or truncated file heals itself on the next fetch.
/// Downloads stream to a temporary file and hash as bytes arrive — the model
/// never occupies the Dart heap, and MediaPipe reads the completed file by
/// path, which lets it map the file instead of copying it.
final class ModelCache {
  /// Creates a cache rooted at [directory], created on first use.
  ///
  /// [maximumBytes] caps what a single download may deliver; it defaults to
  /// [maximumRemoteModelBytes] and exists so tests can exercise the limit.
  ModelCache(this.directory, {this.maximumBytes = maximumRemoteModelBytes}) {
    if (maximumBytes <= 0) {
      throw ArgumentError.value(maximumBytes, 'maximumBytes', 'must be greater than zero');
    }
  }

  /// Directory holding the cached models.
  final String directory;

  /// The largest model one download may deliver.
  final int maximumBytes;

  /// Returns a path asset for the model at [uri], fetching it when needed.
  ///
  /// The digest must match what the server delivers; a mismatch fails with
  /// `MpStatus.dataLoss` and leaves no cached file behind. A redirect that
  /// leaves the remote-model transport policy fails with
  /// `MpStatus.invalidArgument` and also leaves nothing cached.
  Future<ModelAssetPath> fetch(Uri uri, String digest) async {
    final File target = File(targetPath(uri, digest));

    if (target.existsSync()) {
      if (await fileMatchesDigest(target, digest)) {
        return ModelAssetPath(target.path);
      }

      target.deleteSync();
    }

    Directory(directory).createSync(recursive: true);

    final File partial = File('${target.path}.${DateTime.now().microsecondsSinceEpoch}.part');

    try {
      await _download(uri, partial, digest);
      partial.renameSync(target.path);
    } finally {
      if (partial.existsSync()) partial.deleteSync();
    }

    return ModelAssetPath(target.path);
  }

  /// The cache path for [uri] verified by [sha256].
  ///
  /// The digest is the file name and the source URI only contributes a
  /// sanitized extension for readability, so the path can never escape
  /// [directory] through a crafted URI.
  String targetPath(Uri uri, String digest) {
    final String separator = directory.endsWith('/') || directory.endsWith(r'\') ? '' : '/';

    return '$directory$separator$digest${_extensionOf(uri)}';
  }

  static String _extensionOf(Uri uri) {
    final List<String> segments = uri.pathSegments;

    if (segments.isEmpty) return '';

    final String name = segments.last;
    final int dot = name.lastIndexOf('.');

    if (dot == -1) return '';

    final String extension = name.substring(dot);

    return RegExp(r'^\.[A-Za-z0-9]{1,16}$').hasMatch(extension) ? extension : '';
  }

  Future<void> _download(Uri uri, File target, String digest) async {
    final HttpClient client = HttpClient()..connectionTimeout = const Duration(seconds: 30);

    try {
      final HttpClientResponse response = await openRemoteModel(client, uri);

      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw MpException(
          MpStatus.unavailable,
          'Downloading the model failed with HTTP ${response.statusCode}.',
        );
      }

      final _DigestCollector collector = _DigestCollector();
      final ByteConversionSink hasher = sha256.startChunkedConversion(collector);
      final IOSink sink = target.openWrite();
      var length = 0;

      try {
        await for (final List<int> chunk in response) {
          length += chunk.length;

          if (length > maximumBytes) {
            throw MpException(
              MpStatus.resourceExhausted,
              'The remote model exceeds the $maximumBytes-byte safety limit.',
            );
          }

          hasher.add(chunk);
          sink.add(chunk);
        }

        await sink.flush();
      } finally {
        await sink.close();
      }

      hasher.close();

      if (collector.value.toString() != digest) {
        throw const MpException(
          MpStatus.dataLoss,
          'The downloaded model does not match its SHA-256 digest.',
        );
      }
    } finally {
      client.close(force: true);
    }
  }
}

/// Receives the single digest a chunked SHA-256 conversion emits on close.
final class _DigestCollector implements Sink<Digest> {
  Digest? _value;

  /// The digest, available once the hashing sink has been closed.
  Digest get value => _value!;

  @override
  void add(Digest data) => _value = data;

  @override
  void close() {}
}
