import 'dart:io';

import 'package:code_assets/code_assets.dart';
import 'package:hooks/hooks.dart';
import 'package:mp_core/src/native/artifact.dart';
import 'package:test/test.dart';

import '../hook/build.dart' as build_hook;

void main() {
  /// The path a package published to pub.dev takes: no
  /// `native_library_directory` user define, so the hook downloads the
  /// checksummed archive named by `native_artifacts.json` for this host.
  ///
  /// Skipped when the catalog publishes no build for the test host, because a
  /// missing target legitimately bundles nothing.
  test(
    'resolves the published catalog when no local directory is configured',
    () async {
      final NativeArtifactCatalog catalog = _catalog();
      final String host = '${OS.current.name}-${Architecture.current.name}';
      if (!catalog.artifacts.containsKey(host)) {
        markTestSkipped('No published runtime for $host.');
        return;
      }

      var assetCount = 0;
      await testCodeBuildHook(
        mainMethod: build_hook.main,
        targetArchitecture: Architecture.current,
        targetOS: OS.current,
        userDefines: PackageUserDefines(
          workspacePubspec: PackageUserDefinesSource(
            defines: const <String, Object?>{},
            basePath: Directory.current.uri.resolve('pubspec.yaml'),
          ),
        ),
        check: (BuildInput input, BuildOutput output) {
          assetCount = output.assets.code.length;
          // The archive carries MediaPipe plus its OpenCV dependencies, so a
          // successful resolution bundles more than just the entry point.
          expect(
            output.assets.code.map((CodeAsset asset) => asset.id),
            contains('package:mp_core/native.dart'),
          );
        },
      );
      expect(assetCount, greaterThan(1));
    },
    timeout: const Timeout(Duration(minutes: 5)),
  );
}

/// Reads the artifact catalog the way the build hook itself does, so the test
/// can never drift from the hook's understanding of the file.
NativeArtifactCatalog _catalog() =>
    NativeArtifactCatalog.parse(File('hook/native_artifacts.json').readAsStringSync());
