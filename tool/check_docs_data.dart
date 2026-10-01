import 'dart:convert';
import 'dart:io';

/// Verifies that the documentation metadata under `docs/data/` still agrees
/// with the workspace it describes.
///
/// `mdt` renders whatever the data files say, so it cannot catch a package that
/// was renamed, a version that fell behind the pinned upstream release, or a
/// docs route that points at a page that does not exist. This check covers
/// those gaps and exits non-zero when the data and the repository disagree.
Future<void> main(List<String> arguments) async {
  final Directory root = Directory.current;
  final List<String> failures = <String>[];

  final Map<String, Object?> packages = _readJson(root, 'docs/data/packages.json');
  final Map<String, Object?> versions = _readJson(root, 'docs/data/versions.json');
  final Map<String, Object?> links = _readJson(root, 'docs/data/links.json');

  final Set<String> workspacePackages = _workspacePackages(root);
  final Set<String> documentedPackages = packages.keys.toSet();

  for (final String name in documentedPackages.difference(workspacePackages)) {
    failures.add('docs/data/packages.json documents `$name`, which is not in the workspace.');
  }
  for (final String name in workspacePackages.difference(documentedPackages)) {
    failures.add('The workspace contains `$name`, which is missing from docs/data/packages.json.');
  }

  for (final MapEntry<String, Object?> entry in packages.entries) {
    final Object? value = entry.value;
    if (value is! Map<String, Object?>) {
      failures.add('docs/data/packages.json has a non-object value for `${entry.key}`.');
      continue;
    }
    final String? path = value['path'] as String?;
    final String? docs = value['docs'] as String?;
    final String? description = value['description'] as String?;
    if (path == null || docs == null || description == null) {
      failures.add('`${entry.key}` needs `path`, `docs`, and `description` entries.');
      continue;
    }

    // The description is published on pub.dev, so it must match the pubspec.
    final File pubspec = File('${root.path}/$path/pubspec.yaml');
    if (!pubspec.existsSync()) {
      failures.add('`${entry.key}` points at a missing pubspec: $path/pubspec.yaml.');
    } else {
      final String? declared = _pubspecDescription(pubspec.readAsStringSync());
      if (declared != description) {
        failures.add(
          '`${entry.key}` description disagrees with $path/pubspec.yaml.\n'
          '    docs/data/packages.json: $description\n'
          '    pubspec.yaml:            ${declared ?? '<missing>'}',
        );
      }
    }

    // Every documented route must have a content page behind it.
    final File page = File('${root.path}/docs/content/$docs.md');
    if (!page.existsSync()) {
      failures.add('`${entry.key}` links to a missing docs page: docs/content/$docs.md.');
    }
  }

  // The pinned upstream versions must match what the binding generator uses.
  final String generator = File('${root.path}/tool/generate_bindings.dart').readAsStringSync();
  final RegExpMatch? declared = RegExp(
    r"""_mediaPipeVersion\s*=\s*'(v[0-9.]+)'""",
  ).firstMatch(generator);
  if (declared == null) {
    failures.add('tool/generate_bindings.dart no longer declares a pinned MediaPipe version.');
  } else if (declared.group(1) != versions['mediaPipe']) {
    failures.add(
      'docs/data/versions.json mediaPipe is ${versions['mediaPipe']}, '
      'but tool/generate_bindings.dart pins ${declared.group(1)}.',
    );
  }

  // Canonical URLs must stay absolute and HTTPS.
  for (final MapEntry<String, Object?> entry in links.entries) {
    final Object? value = entry.value;
    if (value is! String || !value.startsWith('https://')) {
      failures.add('docs/data/links.json `${entry.key}` must be an absolute HTTPS URL.');
    }
  }

  if (failures.isEmpty) {
    stdout.writeln(
      'docs data is consistent: ${documentedPackages.length} packages, '
      'mediaPipe ${versions['mediaPipe']}.',
    );
    return;
  }

  stderr.writeln('docs data check failed:');
  for (final String failure in failures) {
    stderr.writeln('  - $failure');
  }
  exitCode = 1;
}

Map<String, Object?> _readJson(Directory root, String path) {
  final File file = File('${root.path}/$path');
  if (!file.existsSync()) {
    stderr.writeln('Missing required data file: $path');
    exit(1);
  }
  final Object? decoded = jsonDecode(file.readAsStringSync());
  if (decoded is! Map<String, Object?>) {
    stderr.writeln('$path must contain a JSON object.');
    exit(1);
  }
  return decoded;
}

/// Reads the `name:` keys under the root `workspace:` list in `pubspec.yaml`.
Set<String> _workspacePackages(Directory root) {
  final List<String> lines = File('${root.path}/pubspec.yaml').readAsLinesSync();
  final Set<String> names = <String>{};
  var inWorkspace = false;
  for (final String line in lines) {
    if (line.startsWith('workspace:')) {
      inWorkspace = true;
      continue;
    }
    if (!inWorkspace) continue;
    if (line.trim().isEmpty || line.startsWith('  ') || line.startsWith('    ')) {
      final String trimmed = line.trim();
      if (trimmed.startsWith('- ')) {
        final String path = trimmed.substring(2).trim();
        // Only direct package directories are documented; example fixtures are
        // workspace members but never published on their own.
        if (path.startsWith('packages/') && !path.contains('/example')) {
          names.add(path.split('/').last);
        }
      }
      continue;
    }
    inWorkspace = false;
  }
  return names;
}

String? _pubspecDescription(String source) {
  for (final String line in source.split('\n')) {
    if (line.startsWith('description:')) {
      return line.substring('description:'.length).trim();
    }
  }
  return null;
}
