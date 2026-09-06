import 'dart:io';

import 'package:code_assets/code_assets.dart';
import 'package:hooks/hooks.dart';
import 'package:test/test.dart';

import '../hook/build.dart' as build_hook;

void main() {
  test('tracks a configured local artifact root before it exists', () async {
    final Directory temporary = await Directory.systemTemp.createTemp('mp-core-hook-');
    addTearDown(() => temporary.deleteSync(recursive: true));
    final Uri artifacts = Directory.fromUri(temporary.uri.resolve('native')).uri;

    await testCodeBuildHook(
      mainMethod: build_hook.main,
      targetArchitecture: Architecture.current,
      targetOS: OS.current,
      userDefines: _userDefines(temporary, 'native'),
      check: (BuildInput input, BuildOutput output) {
        expect(output.dependencies, contains(artifacts));
        expect(output.assets.code, isEmpty);
      },
    );
  });

  test('bundles every local dynamic library and names the main asset', () async {
    final Directory temporary = await Directory.systemTemp.createTemp('mp-core-hook-');
    addTearDown(() => temporary.deleteSync(recursive: true));
    final String target = '${OS.current.name}-${Architecture.current.name}';
    final Directory artifacts = Directory.fromUri(temporary.uri.resolve('native/$target/'))
      ..createSync(recursive: true);
    final String mainLibrary = switch (OS.current) {
      OS.macOS => 'libmediapipe.dylib',
      OS.linux => 'libmediapipe.so',
      OS.windows => 'libmediapipe.dll',
      _ => throw UnsupportedError('Unsupported test host: ${OS.current.name}'),
    };
    final String dependency = switch (OS.current) {
      OS.macOS => 'libopencv_core.dylib',
      OS.linux => 'libopencv_core.so',
      OS.windows => 'opencv_core.dll',
      _ => throw UnsupportedError('Unsupported test host: ${OS.current.name}'),
    };
    File.fromUri(artifacts.uri.resolve(mainLibrary)).writeAsBytesSync(<int>[1]);
    File.fromUri(artifacts.uri.resolve(dependency)).writeAsBytesSync(<int>[2]);

    await testCodeBuildHook(
      mainMethod: build_hook.main,
      targetArchitecture: Architecture.current,
      targetOS: OS.current,
      userDefines: _userDefines(temporary, 'native'),
      check: (BuildInput input, BuildOutput output) {
        final List<CodeAsset> assets = output.assets.code;
        expect(assets, hasLength(2));
        expect(
          assets.singleWhere((CodeAsset asset) => asset.id == 'package:mp_core/native.dart').file,
          isNotNull,
        );
        expect(
          assets
              .singleWhere((CodeAsset asset) => asset.id == 'package:mp_core/native/$dependency')
              .file,
          isNotNull,
        );
      },
    );
  });
}

PackageUserDefines _userDefines(Directory root, String artifacts) => PackageUserDefines(
  workspacePubspec: PackageUserDefinesSource(
    defines: <String, Object?>{'native_library_directory': artifacts},
    basePath: root.uri.resolve('pubspec.yaml'),
  ),
);
