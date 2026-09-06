import 'dart:io';

import 'package:code_assets/code_assets.dart';
import 'package:hooks/hooks.dart';

/// Bundles a caller-supplied MediaPipe Tasks C library directory.
///
/// Release builds populate this from the checksummed native artifact selected
/// for the target. Source checkouts can set `hooks.user_defines.mp_core` /
/// `native_library_directory` in the workspace pubspec while developing a new
/// artifact. The directory must contain the main MediaPipe library and any
/// adjacent dynamic libraries it references. A directory for a different
/// target operating system is ignored.
Future<void> main(List<String> arguments) async {
  await build(arguments, (BuildInput input, BuildOutputBuilder output) async {
    if (!input.config.buildCodeAssets) return;
    final Uri? configured = input.userDefines.path('native_library_directory');
    if (configured == null) return;

    final Directory directory = Directory.fromUri(configured);
    if (!directory.existsSync()) {
      throw StateError(
        'The configured mp_core native library directory does not exist: ${directory.path}',
      );
    }
    final String? mainLibraryName = _mainLibraryName(input.config.code.targetOS);
    if (mainLibraryName == null) return;
    final List<File> libraries =
        directory
            .listSync()
            .whereType<File>()
            .where((File file) => _isDynamicLibrary(file.path, input.config.code.targetOS))
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
