import 'dart:io';

import 'package:code_assets/code_assets.dart';
import 'package:hooks/hooks.dart';

import 'native_artifact.dart';

/// Bundles the MediaPipe Tasks C libraries for a desktop target.
///
/// Source checkouts can set `hooks.user_defines.mp_core` /
/// `native_library_directory` to test a local build. Published packages resolve
/// the target from `native_artifacts.json`, download the immutable release
/// archive into the hook's shared cache, and verify both the archive and each
/// library before bundling them.
Future<void> main(List<String> arguments) async {
  await build(arguments, (BuildInput input, BuildOutputBuilder output) async {
    if (!input.config.buildCodeAssets) return;
    final OS targetOS = input.config.code.targetOS;
    final String? mainLibraryName = _mainLibraryName(targetOS);
    if (mainLibraryName == null) return;

    Directory? directory;
    final Uri? configured = input.userDefines.path('native_library_directory');
    if (configured != null) {
      final Directory localDirectory = Directory.fromUri(configured);
      if (localDirectory.existsSync()) directory = localDirectory;
    }

    if (directory == null) {
      final Uri catalogUri = input.packageRoot.resolve('hook/native_artifacts.json');
      final File catalogFile = File.fromUri(catalogUri);
      output.dependencies.add(catalogUri);
      final NativeArtifactCatalog catalog = NativeArtifactCatalog.parse(
        await catalogFile.readAsString(),
      );
      final String target = '${targetOS.name}-${input.config.code.targetArchitecture.name}';
      final NativeArtifact? artifact = catalog.artifacts[target];
      if (artifact == null) return;
      directory = await resolveNativeArtifact(
        artifact: artifact,
        sharedOutputDirectory: input.outputDirectoryShared,
      );
    }

    final List<File> libraries =
        directory
            .listSync()
            .whereType<File>()
            .where((File file) => _isDynamicLibrary(file.path, targetOS))
            .toList(growable: false)
          ..sort((File left, File right) => left.path.compareTo(right.path));
    if (libraries.isEmpty) return;
    if (!libraries.any((File file) => file.uri.pathSegments.last == mainLibraryName)) {
      throw StateError('$mainLibraryName is missing from ${directory.path}.');
    }

    for (final File source in libraries) {
      final String fileName = source.uri.pathSegments.last;
      final Uri bundled = input.outputDirectory.resolve(fileName);
      output.dependencies.add(source.uri);
      await source.copy(bundled.toFilePath());
      output.assets.code.add(
        CodeAsset(
          package: input.packageName,
          name: fileName == mainLibraryName ? 'native.dart' : 'native/$fileName',
          linkMode: DynamicLoadingBundled(),
          file: bundled,
        ),
      );
    }
  });
}

String? _mainLibraryName(OS os) => switch (os) {
  OS.macOS => 'libmediapipe.dylib',
  OS.linux || OS.android => 'libmediapipe.so',
  OS.windows => 'mediapipe.dll',
  _ => null,
};

bool _isDynamicLibrary(String path, OS os) => switch (os) {
  OS.macOS => path.endsWith('.dylib'),
  OS.linux || OS.android => path.endsWith('.so') || path.contains('.so.'),
  OS.windows => path.endsWith('.dll'),
  _ => false,
};
