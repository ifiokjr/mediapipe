import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:archive/archive_io.dart';
import 'package:crypto/crypto.dart';

final class NativeArtifact {
  const NativeArtifact({
    required this.mediaPipeVersion,
    required this.target,
    required this.uri,
    required this.sha256,
  });

  final String mediaPipeVersion;
  final String target;
  final Uri uri;
  final String sha256;
}

final class NativeArtifactCatalog {
  const NativeArtifactCatalog({required this.mediaPipeVersion, required this.artifacts});

  final String mediaPipeVersion;
  final Map<String, NativeArtifact> artifacts;

  static NativeArtifactCatalog parse(String source) {
    final Object? decoded = jsonDecode(source);
    if (decoded case {
      'schemaVersion': 1,
      'mediaPipeVersion': final String mediaPipeVersion,
      'artifacts': final Map<String, Object?> artifactValues,
    }) {
      if (!RegExp(r'^v\d+\.\d+\.\d+$').hasMatch(mediaPipeVersion)) {
        throw FormatException('Invalid MediaPipe version: $mediaPipeVersion.');
      }
      final Map<String, NativeArtifact> artifacts = <String, NativeArtifact>{};
      for (final MapEntry<String, Object?> entry in artifactValues.entries) {
        if (entry.value case {'url': final String url, 'sha256': final String checksum}) {
          _requireDigest(checksum, 'artifact ${entry.key}');
          final Uri uri = Uri.parse(url);
          if (!uri.isScheme('https')) {
            throw FormatException('Artifact ${entry.key} must use HTTPS.');
          }
          artifacts[entry.key] = NativeArtifact(
            mediaPipeVersion: mediaPipeVersion,
            target: entry.key,
            uri: uri,
            sha256: checksum,
          );
          continue;
        }
        throw FormatException('Invalid artifact entry for ${entry.key}.');
      }
      return NativeArtifactCatalog(mediaPipeVersion: mediaPipeVersion, artifacts: artifacts);
    }
    throw const FormatException('Invalid native artifact catalog.');
  }
}

Future<Directory> resolveNativeArtifact({
  required NativeArtifact artifact,
  required Uri sharedOutputDirectory,
  HttpClient? client,
}) async {
  final Directory cache = Directory.fromUri(
    sharedOutputDirectory.resolve('mp_core/${artifact.target}-${artifact.sha256}/'),
  );
  final File ready = File.fromUri(cache.uri.resolve('.ready'));
  if (ready.existsSync()) return cache;

  if (cache.existsSync()) cache.deleteSync(recursive: true);
  cache.createSync(recursive: true);
  final File archiveFile = File.fromUri(cache.uri.resolve('artifact.zip'));
  final File temporary = File.fromUri(cache.uri.resolve('artifact.zip.part'));
  final HttpClient httpClient =
      client ?? (HttpClient()..connectionTimeout = const Duration(seconds: 30));
  try {
    final HttpClientRequest request = await httpClient.getUrl(artifact.uri);
    request.headers.set(HttpHeaders.userAgentHeader, 'mp_core native asset hook');
    final HttpClientResponse response = await request.close();
    if (response.statusCode != HttpStatus.ok) {
      await response.drain<void>();
      throw HttpException(
        'Native artifact download returned HTTP ${response.statusCode}.',
        uri: artifact.uri,
      );
    }
    await response.pipe(temporary.openWrite());
    final String actualDigest = await sha256
        .bind(temporary.openRead())
        .first
        .then((Digest digest) => digest.toString());
    if (actualDigest != artifact.sha256) {
      throw StateError(
        'Native artifact checksum mismatch for ${artifact.target}: '
        'expected ${artifact.sha256}, received $actualDigest.',
      );
    }
    await temporary.rename(archiveFile.path);
    await _extractArchive(archiveFile, cache);
    await _verifyManifest(cache, artifact.target, artifact.mediaPipeVersion);
    ready.writeAsStringSync('${artifact.sha256}\n');
    return cache;
  } catch (_) {
    if (cache.existsSync()) cache.deleteSync(recursive: true);
    rethrow;
  } finally {
    if (client == null) httpClient.close(force: true);
  }
}

Future<void> _extractArchive(File source, Directory destination) async {
  final InputFileStream input = InputFileStream(source.path);
  try {
    final Archive archive = ZipDecoder().decodeStream(input);
    for (final ArchiveFile entry in archive) {
      if (!entry.isFile || entry.isSymbolicLink || !_isSafeFlatName(entry.name)) {
        throw FormatException('Unsafe native artifact entry: ${entry.name}');
      }
      final OutputFileStream output = OutputFileStream(
        destination.uri.resolve(entry.name).toFilePath(),
      );
      try {
        entry.writeContent(output);
      } finally {
        output.closeSync();
      }
    }
  } finally {
    input.closeSync();
  }
}

Future<void> _verifyManifest(
  Directory directory,
  String expectedTarget,
  String expectedMediaPipeVersion,
) async {
  final File manifestFile = File.fromUri(directory.uri.resolve('manifest.json'));
  if (!manifestFile.existsSync()) {
    throw const FormatException('Native artifact does not contain manifest.json.');
  }
  final Object? decoded = jsonDecode(await manifestFile.readAsString());
  if (decoded case {
    'mediaPipeVersion': final String mediaPipeVersion,
    'target': final String target,
    'libraries': final Map<String, Object?> libraryValues,
  }) {
    if (mediaPipeVersion != expectedMediaPipeVersion) {
      throw FormatException(
        'Expected MediaPipe $expectedMediaPipeVersion, received $mediaPipeVersion.',
      );
    }
    if (target != expectedTarget) {
      throw FormatException('Expected native target $expectedTarget, received $target.');
    }
    if (libraryValues.isEmpty) {
      throw const FormatException('Native artifact manifest has no libraries.');
    }
    for (final MapEntry<String, Object?> entry in libraryValues.entries) {
      if (!_isSafeFlatName(entry.key) || entry.value is! String) {
        throw FormatException('Invalid native library manifest entry: ${entry.key}.');
      }
      final String expectedDigest = entry.value! as String;
      _requireDigest(expectedDigest, entry.key);
      final File library = File.fromUri(directory.uri.resolve(entry.key));
      if (!library.existsSync()) {
        throw FormatException('Native artifact is missing ${entry.key}.');
      }
      final String actualDigest = await sha256
          .bind(library.openRead())
          .first
          .then((Digest digest) => digest.toString());
      if (actualDigest != expectedDigest) {
        throw StateError('Native library checksum mismatch for ${entry.key}.');
      }
    }
    final Set<String> extractedFiles = directory
        .listSync()
        .whereType<File>()
        .map((File file) => file.uri.pathSegments.last)
        .where((String name) => name != 'artifact.zip' && name != 'manifest.json')
        .toSet();
    if (extractedFiles.length != libraryValues.length ||
        !extractedFiles.containsAll(libraryValues.keys)) {
      throw const FormatException('Native artifact contains undeclared files.');
    }
    return;
  }
  throw const FormatException('Invalid native artifact manifest.');
}

bool _isSafeFlatName(String name) =>
    name.isNotEmpty && !name.contains('/') && !name.contains(r'\') && name != '.' && name != '..';

void _requireDigest(String value, String subject) {
  if (!RegExp(r'^[0-9a-f]{64}$').hasMatch(value)) {
    throw FormatException('Invalid SHA-256 digest for $subject.');
  }
}
