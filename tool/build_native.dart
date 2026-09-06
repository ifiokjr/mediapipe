import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';

const String _mediaPipeVersion = 'v1.0.0';
const String _repository = 'https://github.com/google-ai-edge/mediapipe.git';

Future<void> main(List<String> arguments) async {
  final Directory repositoryRoot = _findRepositoryRoot();
  final Directory upstream = Directory.fromUri(
    repositoryRoot.uri.resolve('.dart_tool/upstream/mediapipe/'),
  );
  await _ensureUpstream(repositoryRoot, upstream);
  _applyCompatibilityPatches(repositoryRoot, upstream);

  final List<String> bazelArguments = <String>[
    'build',
    '--lockfile_mode=update',
    '--experimental_google_legacy_api',
    '--repo_env=HERMETIC_PYTHON_VERSION=3.12',
    '-c',
    'opt',
    '--strip',
    'always',
    '--define',
    'MEDIAPIPE_DISABLE_GPU=1',
    '--define',
    'OPENCV=source',
    '//mediapipe/tasks/c:libmediapipe',
  ];
  await _runStreaming(
    'bazelisk',
    bazelArguments,
    workingDirectory: upstream.path,
    environment: const <String, String>{'USE_BAZEL_VERSION': '7.4.1'},
  );

  final List<File> artifacts = _findArtifacts(upstream);
  final String target = await _hostTarget();
  final Directory output = Directory.fromUri(repositoryRoot.uri.resolve('.mp-sdk/$target/'));
  if (output.existsSync()) output.deleteSync(recursive: true);
  output.createSync(recursive: true);
  final List<File> copied = <File>[];
  for (final File artifact in artifacts) {
    copied.add(await artifact.copy(output.uri.resolve(_baseName(artifact)).toFilePath()));
  }
  await _makeLibrariesRelocatable(copied, workingDirectory: repositoryRoot.path);
  await _writeManifest(output, target, copied);
  stdout.writeln('Built ${copied.length} libraries in ${output.path}');
}

Future<void> _ensureUpstream(Directory repositoryRoot, Directory upstream) async {
  if (!upstream.existsSync()) {
    upstream.parent.createSync(recursive: true);
    await _runStreaming('git', <String>[
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
}

void _applyCompatibilityPatches(Directory repositoryRoot, Directory upstream) {
  _replaceExactly(
    File.fromUri(upstream.uri.resolve('MODULE.bazel')),
    'bazel_dep(name = "rules_java", version = "7.10.0")\n'
        'single_version_override(\n'
        '    module_name = "rules_java",\n'
        '    version = "7.10.0",\n'
        ')',
    'bazel_dep(name = "rules_java", version = "8.3.2")\n'
        'single_version_override(\n'
        '    module_name = "rules_java",\n'
        '    version = "8.3.2",\n'
        ')',
  );

  const String patchName = 'opencv_macos_modern_sdk.patch';
  final File sourcePatch = File.fromUri(
    repositoryRoot.uri.resolve('tool/patches/opencv-macos-modern-sdk.patch'),
  );
  final File upstreamPatch = File.fromUri(upstream.uri.resolve('third_party/$patchName'));
  upstreamPatch.writeAsStringSync(sourcePatch.readAsStringSync());
  _replaceExactly(
    File.fromUri(upstream.uri.resolve('third_party/BUILD')),
    'exports_files([\n    "LICENSE",',
    'exports_files([\n    "LICENSE",\n    "$patchName",',
  );
  _replaceExactly(
    File.fromUri(upstream.uri.resolve('WORKSPACE')),
    'http_archive(\n'
        '    name = "opencv",\n'
        '    build_file_content = all_content,\n'
        '    strip_prefix = "opencv-3.4.11",',
    'http_archive(\n'
        '    name = "opencv",\n'
        '    build_file_content = all_content,\n'
        '    patch_args = ["-p1"],\n'
        '    patches = ["@//third_party:$patchName"],\n'
        '    strip_prefix = "opencv-3.4.11",',
  );
}

void _replaceExactly(File file, String original, String replacement) {
  final String contents = file.readAsStringSync();
  if (contents.contains(replacement)) return;
  if (!contents.contains(original)) {
    throw StateError('Compatibility patch no longer matches ${file.path}.');
  }
  file.writeAsStringSync(contents.replaceFirst(original, replacement));
}

List<File> _findArtifacts(Directory upstream) {
  final Directory output = Directory.fromUri(upstream.uri.resolve('bazel-bin/mediapipe/tasks/c/'));
  final List<File> candidates = output
      .listSync()
      .whereType<File>()
      .where((File file) => file.uri.pathSegments.last == _libraryName())
      .toList();
  if (candidates.length != 1) {
    throw StateError('Expected one ${_libraryName()} in ${output.path}, found $candidates.');
  }
  final Directory openCvOutput = Directory.fromUri(
    upstream.uri.resolve('bazel-bin/third_party/opencv_cmake/lib/'),
  );
  final List<File> openCvLibraries =
      openCvOutput
          .listSync()
          .whereType<File>()
          .where((File file) => _isSharedLibrary(_baseName(file)))
          .toList()
        ..sort((File left, File right) => left.path.compareTo(right.path));
  if (openCvLibraries.isEmpty) {
    throw StateError('No OpenCV shared libraries found in ${openCvOutput.path}.');
  }
  return <File>[candidates.single, ...openCvLibraries];
}

bool _isSharedLibrary(String name) {
  if (Platform.isMacOS) return name.endsWith('.dylib');
  if (Platform.isLinux) return name.contains('.so');
  if (Platform.isWindows) return name.endsWith('.dll');
  return false;
}

String _baseName(File file) => file.uri.pathSegments.last;

Future<void> _makeLibrariesRelocatable(
  List<File> libraries, {
  required String workingDirectory,
}) async {
  if (Platform.isMacOS) {
    for (final File library in libraries) {
      final String name = _baseName(library);
      await _runStreaming('install_name_tool', <String>[
        '-id',
        '@rpath/$name',
        '-add_rpath',
        '@loader_path',
        library.path,
      ], workingDirectory: workingDirectory);
    }
  } else if (Platform.isLinux) {
    for (final File library in libraries) {
      await _runStreaming('patchelf', <String>[
        '--set-rpath',
        r'$ORIGIN',
        library.path,
      ], workingDirectory: workingDirectory);
    }
  }
}

Future<void> _writeManifest(Directory output, String target, List<File> libraries) async {
  final Map<String, String> checksums = <String, String>{};
  for (final File library in libraries) {
    checksums[_baseName(library)] = sha256.convert(await library.readAsBytes()).toString();
  }
  final File manifest = File.fromUri(output.uri.resolve('manifest.json'));
  final String contents = const JsonEncoder.withIndent('  ').convert(<String, Object>{
    'mediaPipeVersion': _mediaPipeVersion,
    'target': target,
    'libraries': checksums,
  });
  await manifest.writeAsString('$contents\n');
}

String _libraryName() {
  if (Platform.isMacOS) return 'libmediapipe.dylib';
  if (Platform.isLinux || Platform.isAndroid) return 'libmediapipe.so';
  if (Platform.isWindows) return 'mediapipe.dll';
  throw UnsupportedError(
    'Native MediaPipe builds are not configured for ${Platform.operatingSystem}.',
  );
}

Future<String> _hostTarget() async {
  final String architecture = Platform.isWindows
      ? (Platform.environment['PROCESSOR_ARCHITECTURE'] ?? '').toLowerCase()
      : (await _run('uname', const <String>[
          '-m',
        ], workingDirectory: Directory.current.path)).trim();
  final String normalizedArchitecture = switch (architecture) {
    'arm64' || 'aarch64' => 'arm64',
    'x86_64' || 'amd64' => 'x64',
    _ => throw UnsupportedError('Unsupported host architecture: $architecture'),
  };
  final String os = Platform.isMacOS
      ? 'macos'
      : Platform.isLinux
      ? 'linux'
      : Platform.isWindows
      ? 'windows'
      : throw UnsupportedError('Unsupported host OS: ${Platform.operatingSystem}');
  return '$os-$normalizedArchitecture';
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
  if (result.exitCode != 0) {
    stderr.write(result.stderr);
    throw ProcessException(executable, arguments, 'Command failed', result.exitCode);
  }
  return result.stdout as String;
}

Future<void> _runStreaming(
  String executable,
  List<String> arguments, {
  required String workingDirectory,
  Map<String, String> environment = const <String, String>{},
}) async {
  final Process process = await Process.start(
    executable,
    arguments,
    workingDirectory: workingDirectory,
    environment: environment,
    mode: ProcessStartMode.inheritStdio,
  );
  final int exitCode = await process.exitCode;
  if (exitCode != 0) {
    throw ProcessException(executable, arguments, 'Command failed', exitCode);
  }
}
