import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';

import '../errors.dart';
import '../options.dart';

/// The largest model a remote URI may deliver.
const int maximumRemoteModelBytes = 512 * 1024 * 1024;

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
  /// `MpStatus.dataLoss` and leaves no cached file behind.
  Future<ModelAssetPath> fetch(Uri uri, String digest) async {
    final File target = File(targetPath(uri, digest));

    if (target.existsSync()) {
      if (await _hasDigest(target, digest)) return ModelAssetPath(target.path);

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

  static Future<bool> _hasDigest(File file, String digest) async {
    final _DigestCollector collector = _DigestCollector();
    final ByteConversionSink hasher = sha256.startChunkedConversion(collector);

    await for (final List<int> chunk in file.openRead()) {
      hasher.add(chunk);
    }
    hasher.close();

    return collector.value.toString() == digest;
  }

  Future<void> _download(Uri uri, File target, String digest) async {
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
