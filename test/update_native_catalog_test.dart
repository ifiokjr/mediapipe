import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:test/test.dart';

import '../tool/update_native_catalog.dart';

void main() {
  test('builds a sorted catalog from verified archive manifests', () async {
    final Directory temporary = await Directory.systemTemp.createTemp('mp-catalog-test-');
    addTearDown(() => temporary.deleteSync(recursive: true));
    final File macOS = await _writeArchive(temporary, 'macos-arm64');
    final File linux = await _writeArchive(temporary, 'linux-x64');
    final File android = await _writeArchive(temporary, 'android-arm64');

    final Map<String, Object> catalog = await buildNativeArtifactCatalog(
      release: 'native-v1.0.0-1',
      archives: <File>[macOS, linux, android],
    );

    expect(catalog['mediaPipeVersion'], 'v1.0.0');
    final Map<String, Object> artifacts = catalog['artifacts']! as Map<String, Object>;
    expect(artifacts.keys, <String>['android-arm64', 'linux-x64', 'macos-arm64']);
    expect(
      (artifacts['linux-x64']! as Map<String, String>)['url'],
      endsWith('/native-v1.0.0-1/mediapipe-v1.0.0-linux-x64.zip'),
    );
  });

  test('rejects an archive whose filename and manifest disagree', () async {
    final Directory temporary = await Directory.systemTemp.createTemp('mp-catalog-test-');
    addTearDown(() => temporary.deleteSync(recursive: true));
    final File archive = await _writeArchive(temporary, 'linux-x64', manifestTarget: 'linux-arm64');

    await expectLater(
      buildNativeArtifactCatalog(release: 'native-v1.0.0-1', archives: <File>[archive]),
      throwsStateError,
    );
  });
}

Future<File> _writeArchive(Directory directory, String target, {String? manifestTarget}) async {
  final Archive archive = Archive()
    ..add(
      ArchiveFile.string(
        'manifest.json',
        jsonEncode(<String, Object>{
          'mediaPipeVersion': 'v1.0.0',
          'target': manifestTarget ?? target,
          'libraries': <String, String>{},
        }),
      ),
    );
  final File file = File.fromUri(directory.uri.resolve('mediapipe-v1.0.0-$target.zip'));
  await file.writeAsBytes(ZipEncoder().encodeBytes(archive, modified: DateTime.utc(1980)));
  return file;
}
