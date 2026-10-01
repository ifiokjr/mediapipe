import 'dart:io';

import 'package:test/test.dart';

/// Directories that never contain package sources worth scanning.
const Set<String> _unscannedDirectories = <String>{
  '.dart_tool',
  '.devenv',
  '.fvm',
  '.git',
  '.gradle',
  '.mp-sdk',
  'Pods',
  'build',
  'node_modules',
};

/// Hook entrypoints pub.dev accepts, mirroring `checkHooks` in pub-dev's
/// `pkg/pub_package_reader`.
///
/// pub.dev rejects every other Dart file under `hook/` with "Hook files are
/// experimental and `<path>` is not allowed yet", which failed the 0.1.0
/// upload after the release tag had already been pushed. Keep helper code and
/// catalog data outside `hook/` (for example in `lib/src/...`) and import it
/// from the hook with a `package:` URI.
final RegExp _allowedHookFile = RegExp(r'^(build|link)\.dart$');

void main() {
  test('hook/ directories contain only the Dart files pub.dev allows', () {
    final Uri rootUri = _repositoryRoot().uri;
    final List<String> violations = <String>[];

    for (final Directory hookDirectory in _hookDirectories(_repositoryRoot())) {
      final String hookUri = hookDirectory.uri.toString();
      for (final FileSystemEntity entity in hookDirectory.listSync(
        recursive: true,
        followLinks: false,
      )) {
        if (entity is! File || !entity.path.endsWith('.dart')) continue;
        final String name = entity.uri.toString().substring(hookUri.length);
        if (!_allowedHookFile.hasMatch(name)) {
          violations.add(
            entity.uri.toString().substring(rootUri.toString().length),
          );
        }
      }
    }

    expect(
      violations,
      isEmpty,
      reason:
          'pub.dev rejects Dart files under hook/ other than hook/build.dart and '
          'hook/link.dart; move helpers into lib/ and import them from the hook '
          'with a package: URI.',
    );
  });
}

/// Resolves the repository root so the scan works from any working directory.
Directory _repositoryRoot() {
  Directory directory = Directory.current.absolute;

  while (!File('${directory.path}/monochange.toml').existsSync()) {
    final Directory parent = directory.parent;

    if (parent.path == directory.path) {
      throw StateError(
        'Could not find monochange.toml above ${Directory.current.path}.',
      );
    }

    directory = parent;
  }

  return directory;
}

Iterable<Directory> _hookDirectories(Directory directory) sync* {
  for (final FileSystemEntity entity in directory.listSync(
    followLinks: false,
  )) {
    if (entity is! Directory) continue;
    final String name = entity.uri.pathSegments
        .where((String segment) => segment.isNotEmpty)
        .last;

    if (name == 'hook') {
      yield entity;
      continue;
    }

    if (_unscannedDirectories.contains(name)) continue;

    yield* _hookDirectories(entity);
  }
}
