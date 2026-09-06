import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:crypto/crypto.dart';

Future<void> main(List<String> arguments) async {
  final String target = _readOption(arguments, '--target');
  if (!RegExp(r'^(macos|linux|windows)-(arm64|x64)$').hasMatch(target)) {
    throw FormatException('Invalid native target: $target');
  }

  final Directory root = _findRepositoryRoot();
  final Directory source = Directory.fromUri(root.uri.resolve('.mp-sdk/$target/'));
  final File manifestFile = File.fromUri(source.uri.resolve('manifest.json'));
  if (!manifestFile.existsSync()) {
    throw StateError('No native manifest found for $target. Run native:build first.');
  }
  final Object? decoded = jsonDecode(await manifestFile.readAsString());
  if (decoded case {
    'mediaPipeVersion': final String mediaPipeVersion,
    'target': final String manifestTarget,
    'libraries': final Map<String, Object?> libraryValues,
  }) {
    if (manifestTarget != target) {
      throw StateError('Manifest target $manifestTarget does not match $target.');
    }
    if (libraryValues.isEmpty) {
      throw const FormatException('Native artifact manifest has no libraries.');
    }
    final List<String> libraryNames = libraryValues.keys.toList(growable: false)..sort();
    final Archive archive = Archive();
    for (final String name in libraryNames) {
      if (!_isSafeFlatName(name) || libraryValues[name] is! String) {
        throw FormatException('Invalid native library manifest entry: $name.');
      }
      final File library = File.fromUri(source.uri.resolve(name));
      final List<int> bytes = await library.readAsBytes();
      final String digest = sha256.convert(bytes).toString();
      if (digest != libraryValues[name]) {
        throw StateError('Native library checksum mismatch for $name.');
      }
      archive.add(ArchiveFile.bytes(name, bytes)..mode = 0x1ed);
    }
    archive.add(ArchiveFile.bytes('manifest.json', await manifestFile.readAsBytes())..mode = 0x1a4);

    final List<int> zip = ZipEncoder().encodeBytes(archive, modified: DateTime.utc(1980));
    final Directory output = Directory.fromUri(root.uri.resolve('dist/'))
      ..createSync(recursive: true);
    final String filename = 'mediapipe-$mediaPipeVersion-$target.zip';
    final File archiveFile = File.fromUri(output.uri.resolve(filename));
    await archiveFile.writeAsBytes(zip, flush: true);
    final String checksum = sha256.convert(zip).toString();
    await File.fromUri(
      output.uri.resolve('$filename.sha256'),
    ).writeAsString('$checksum  $filename\n', flush: true);
    stdout.writeln(
      jsonEncode(<String, Object>{
        'file': archiveFile.path,
        'mediaPipeVersion': mediaPipeVersion,
        'target': target,
        'sha256': checksum,
      }),
    );
    return;
  }
  throw const FormatException('Invalid native artifact manifest.');
}

String _readOption(List<String> arguments, String name) {
  final int index = arguments.indexOf(name);
  if (index == -1 || index + 1 >= arguments.length) {
    throw FormatException('Missing required option $name.');
  }
  return arguments[index + 1];
}

bool _isSafeFlatName(String name) =>
    name.isNotEmpty && !name.contains('/') && !name.contains(r'\') && name != '.' && name != '..';

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
