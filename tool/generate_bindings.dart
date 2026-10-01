import 'dart:io';

const String _mediaPipeVersion = 'v1.0.0';
const String _repository = 'https://github.com/google-ai-edge/mediapipe.git';

Future<void> main() async {
  final Directory repositoryRoot = _findRepositoryRoot();
  final Directory upstream = Directory.fromUri(
    repositoryRoot.uri.resolve('.dart_tool/upstream/mediapipe/'),
  );
  if (!upstream.existsSync()) {
    upstream.parent.createSync(recursive: true);
    await _run('git', <String>[
      'clone',
      '--depth=1',
      '--filter=blob:none',
      '--branch=$_mediaPipeVersion',
      _repository,
      upstream.path,
    ], workingDirectory: repositoryRoot.path);
  }

  final String revision = (await _run('git', const <String>[
    'describe',
    '--tags',
    '--exact-match',
  ], workingDirectory: upstream.path)).trim();
  if (revision != _mediaPipeVersion) {
    throw StateError('Expected MediaPipe $_mediaPipeVersion, found $revision.');
  }

  _createCCompatibleHeaders(repositoryRoot, upstream);

  await _run('dart', const <String>[
    'run',
    'ffigen',
    '--config',
    'packages/mp_core/ffigen.yaml',
  ], workingDirectory: repositoryRoot.path);
}

void _createCCompatibleHeaders(Directory repositoryRoot, Directory upstream) {
  final Directory source = Directory.fromUri(upstream.uri.resolve('mediapipe/tasks/c/'));
  final Directory generatedRoot = Directory.fromUri(
    repositoryRoot.uri.resolve('.dart_tool/ffigen/'),
  );
  final Directory destination = Directory.fromUri(
    generatedRoot.uri.resolve('include/mediapipe/tasks/c/'),
  );
  if (generatedRoot.existsSync()) {
    generatedRoot.deleteSync(recursive: true);
  }
  destination.createSync(recursive: true);

  for (final FileSystemEntity entity in source.listSync(recursive: true)) {
    if (entity is! File || !entity.path.endsWith('.h')) {
      continue;
    }
    final String relativePath = entity.path.substring(source.path.length);
    final File output = File.fromUri(destination.uri.resolve(relativePath));
    output.parent.createSync(recursive: true);
    output.writeAsStringSync(_makeCCompatible(entity.readAsStringSync()));
  }

  File.fromUri(generatedRoot.uri.resolve('mediapipe_tasks.h')).writeAsStringSync(
    File.fromUri(repositoryRoot.uri.resolve('tool/mediapipe_tasks.h')).readAsStringSync(),
  );
}

String _makeCCompatible(String source) {
  String output = source
      .replaceAll('<cstdint>', '<stdint.h>')
      .replaceAll('<cstddef>', '<stddef.h>')
      .replaceAllMapped(
        RegExp(r'const (Mp[A-Za-z0-9_]+)&'),
        (Match match) => 'const ${match.group(1)}*',
      );
  output = output.replaceAllMapped(
    RegExp(
      r'  typedef void \(\*result_callback_fn\)\(([\s\S]*?)\);\n'
      r'  result_callback_fn result_callback;',
    ),
    (Match match) => '  void (*result_callback)(${match.group(1)});',
  );

  final RegExp defaultValue = RegExp(
    r'^(\s+(?:bool|int|float|MpAudioRunningMode|MpRunningMode)\s+'
    r'[A-Za-z_]\w*)\s*=\s*[^;]+;$',
  );
  output = output
      .split('\n')
      .map((String line) {
        final Match? match = defaultValue.firstMatch(line);
        return match == null ? line : '${match.group(1)};';
      })
      .join('\n');
  return _addCTypedefs(output.replaceAll('MpRunningMode::', ''));
}

String _addCTypedefs(String source) {
  final List<String> output = <String>[];
  String? activeType;
  final RegExp declaration = RegExp(r'^(struct|enum) (Mp[A-Za-z0-9_]+) \{$');
  for (final String line in source.split('\n')) {
    final Match? match = declaration.firstMatch(line);
    if (match != null) {
      activeType = match.group(2);
      output.add('typedef ${match.group(1)} $activeType {');
      continue;
    }
    if (activeType != null && line == '};') {
      output.add('} $activeType;');
      activeType = null;
      continue;
    }
    output.add(line);
  }
  if (activeType != null) {
    throw FormatException('Unclosed declaration for $activeType.');
  }
  return output.join('\n');
}

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

Future<String> _run(
  String executable,
  List<String> arguments, {
  required String workingDirectory,
}) async {
  final ProcessResult result = await Process.run(
    executable,
    arguments,
    workingDirectory: workingDirectory,
  );
  stdout.write(result.stdout);
  stderr.write(result.stderr);
  if (result.exitCode != 0) {
    throw ProcessException(executable, arguments, 'Command failed', result.exitCode);
  }
  return result.stdout as String;
}
