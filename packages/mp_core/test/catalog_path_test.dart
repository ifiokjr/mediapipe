import 'dart:io';

import 'package:code_assets/code_assets.dart';
import 'package:hooks/hooks.dart';
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
      final Map<String, Object?> catalog = _catalogTargets();
      final String host = '${OS.current.name}-${Architecture.current.name}';
      if (!catalog.containsKey(host)) {
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

/// Reads the artifact targets from the committed catalog without pulling in the
/// hook's networking dependencies.
Map<String, Object?> _catalogTargets() {
  final File catalog = File('hook/native_artifacts.json');
  final String source = catalog.readAsStringSync();
  final RegExpMatch? start = RegExp(r'"artifacts"\s*:\s*\{').firstMatch(source);

  if (start == null) return const <String, Object?>{};
  final Map<String, Object?> targets = <String, Object?>{};
  for (final RegExpMatch match in RegExp(
    r'^\s{4}"([a-z0-9-]+)"\s*:',
    multiLine: true,
  ).allMatches(source.substring(start.end))) {
    targets[match.group(1)!] = true;
  }

  return targets;
}
