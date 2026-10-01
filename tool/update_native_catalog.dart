import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:crypto/crypto.dart';

Future<void> main(List<String> arguments) async {
  final String release = _readOption(arguments, '--release');
  final Directory artifacts = Directory(_readOption(arguments, '--artifacts')).absolute;
  if (!RegExp(r'^native-v\d+\.\d+\.\d+-\d+$').hasMatch(release)) {
    throw FormatException('Invalid native release tag: $release');
  }
  if (!artifacts.existsSync()) {
    throw StateError('Artifact directory does not exist: ${artifacts.path}');
  }

  final Directory root = _findRepositoryRoot();
  final List<File> archives = artifacts
      .listSync(recursive: true)
      .whereType<File>()
      .where((File file) => file.path.endsWith('.zip'))
      .toList(growable: false);
  final Map<String, Object> catalog = await buildNativeArtifactCatalog(
    release: release,
    archives: archives,
  );
  final File output = File.fromUri(root.uri.resolve('packages/mp_core/hook/native_artifacts.json'));
  await output.writeAsString('${const JsonEncoder.withIndent('  ').convert(catalog)}\n');
  stdout.writeln('Updated ${output.path} from ${archives.length} native archives.');
}

Future<Map<String, Object>> buildNativeArtifactCatalog({
  required String release,
  required Iterable<File> archives,
}) async {
  String? mediaPipeVersion;
  final Map<String, Object> artifacts = <String, Object>{};
  for (final File archiveFile in archives) {
    final RegExpMatch? filename = RegExp(
      r'^mediapipe-(v\d+\.\d+\.\d+)-('
      r'(?:(?:macos|linux)-(?:arm64|x64)|windows-x64|android-(?:arm|arm64|x64))'
      r')\.zip$',
    ).firstMatch(archiveFile.uri.pathSegments.last);
    if (filename == null) {
      throw FormatException('Unexpected native archive name: ${archiveFile.path}');
    }
    final String version = filename.group(1)!;
    final String target = filename.group(2)!;
    if (mediaPipeVersion != null && mediaPipeVersion != version) {
      throw StateError('Native archives contain more than one MediaPipe version.');
    }
    mediaPipeVersion = version;

    final InputFileStream input = InputFileStream(archiveFile.path);
    try {
      final Archive archive = ZipDecoder().decodeStream(input);
      final ArchiveFile? manifestFile = archive.find('manifest.json');
      if (manifestFile == null) {
        throw FormatException('${archiveFile.path} does not contain manifest.json.');
      }
      final Object? manifest = jsonDecode(utf8.decode(manifestFile.content));
      if (manifest case {
        'mediaPipeVersion': final String manifestVersion,
        'target': final String manifestTarget,
      }) {
        if (manifestVersion != version || manifestTarget != target) {
          throw StateError('Native archive metadata does not match ${archiveFile.path}.');
        }
      } else {
        throw FormatException('Invalid manifest in ${archiveFile.path}.');
      }
    } finally {
      input.closeSync();
    }

    final String archiveDigest = await sha256
        .bind(archiveFile.openRead())
        .first
        .then((Digest digest) => digest.toString());
    final String name = archiveFile.uri.pathSegments.last;
    artifacts[target] = <String, String>{
      'url': 'https://github.com/ifiokjr/mediapipe/releases/download/$release/$name',
      'sha256': archiveDigest,
    };
  }
  if (mediaPipeVersion == null || artifacts.isEmpty) {
    throw StateError('No native ZIP archives were found.');
  }
  return <String, Object>{
    'schemaVersion': 1,
    'mediaPipeVersion': mediaPipeVersion,
    'artifacts': Map<String, Object>.fromEntries(
      artifacts.entries.toList(growable: false)..sort(
        (MapEntry<String, Object> left, MapEntry<String, Object> right) =>
            left.key.compareTo(right.key),
      ),
    ),
  };
}

String _readOption(List<String> arguments, String name) {
  final int index = arguments.indexOf(name);
  if (index == -1 || index + 1 >= arguments.length) {
    throw FormatException('Missing required option $name.');
  }
  return arguments[index + 1];
}

Directory _findRepositoryRoot() {
  Directory current = Directory.current.absolute;
  while (current.parent.path != current.path) {
    if (File.fromUri(current.uri.resolve('pubspec.yaml')).existsSync() &&
        Directory.fromUri(current.uri.resolve('packages/mp_core/')).existsSync()) {
      return current;
    }
    current = current.parent;
  }
  throw StateError('Could not find the MP workspace root.');
}
