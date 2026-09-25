import 'dart:io';

import 'package:code_assets/code_assets.dart';
import 'package:hooks/hooks.dart';
import 'package:test/test.dart';

import '../hook/build.dart' as build_hook;
import '../hook/native_artifact.dart';

void main() {
  test('tracks an existing ancestor before the artifact root exists', () async {
    final Directory temporary = await Directory.systemTemp.createTemp('mp-core-hook-');
    addTearDown(() => temporary.deleteSync(recursive: true));

    await testCodeBuildHook(
      mainMethod: build_hook.main,
      targetArchitecture: Architecture.current,
      targetOS: OS.current,
      userDefines: _userDefines(temporary, 'native'),
      check: (BuildInput input, BuildOutput output) {
        expect(output.dependencies, contains(temporary.uri));
        expect(output.assets.code, isEmpty);
      },
    );
  });

  test('the published catalog parses and lists only https targets', () {
    // Guard the committed catalog: every entry must be an immutable HTTPS URL
    // with a lowercase SHA-256 digest, so a published consumer can verify it.
    final File catalog = File('hook/native_artifacts.json');
    expect(catalog.existsSync(), isTrue);
    final NativeArtifactCatalog parsed = NativeArtifactCatalog.parse(catalog.readAsStringSync());
    expect(parsed.mediaPipeVersion, matches(RegExp(r'^v\d+\.\d+\.\d+$')));
    for (final MapEntry<String, NativeArtifact> entry in parsed.artifacts.entries) {
      expect(entry.value.uri.scheme, 'https', reason: entry.key);
      expect(entry.value.sha256, matches(RegExp(r'^[a-f0-9]{64}$')), reason: entry.key);
      expect(entry.value.target, entry.key);
    }
  });

  test('an explicit local directory never falls back to a published archive', () async {
    // A checkout that configures `native_library_directory` must stay hermetic:
    // if the target has no local build, the hook bundles nothing instead of
    // downloading the published archive. Without this, a unit test or an
    // offline build could silently fetch a release over the network.
    final Directory temporary = await Directory.systemTemp.createTemp('mp-core-hook-');
    addTearDown(() => temporary.deleteSync(recursive: true));
    final Directory artifacts = Directory.fromUri(temporary.uri.resolve('native/'))
      ..createSync(recursive: true);

    await testCodeBuildHook(
      mainMethod: build_hook.main,
      targetArchitecture: Architecture.current,
      targetOS: OS.current,
      userDefines: _userDefines(temporary, 'native'),
      check: (BuildInput input, BuildOutput output) {
        expect(output.assets.code, isEmpty);
        expect(artifacts.existsSync(), isTrue);
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
