import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';

import 'native_target.dart';

const String _mediaPipeVersion = 'v1.0.0';
const String _repository = 'https://github.com/google-ai-edge/mediapipe.git';

Future<void> main(List<String> arguments) async {
  final Directory repositoryRoot = _findRepositoryRoot();
  final NativeTarget target = await _readTarget(arguments);
  final Directory upstream = Directory.fromUri(
    repositoryRoot.uri.resolve('.dart_tool/upstream/mediapipe-${target.name}/'),
  );
  await _ensureUpstream(repositoryRoot, upstream);
  _applyCompatibilityPatches(repositoryRoot, upstream, target);

  final List<String> bazelArguments = <String>[
    'build',
    ...target.bazelArguments,
    '--lockfile_mode=update',
    '--experimental_google_legacy_api',
    '--repo_env=HERMETIC_PYTHON_VERSION=3.12',
    '--features=-layering_check',
    '--host_features=-layering_check',
    '-c',
    'opt',
    '--strip',
    'always',
    '--define',
    'MEDIAPIPE_DISABLE_GPU=${target.isAndroid ? 0 : 1}',
    '--define',
    'OPENCV=source',
    '//mediapipe/tasks/c:libmediapipe',
  ];
  await _runStreaming(
    'bazelisk',
    bazelArguments,
    workingDirectory: upstream.path,
    environment: <String, String>{
      'USE_BAZEL_VERSION': '7.4.1',
      if (target.isAndroid) 'ANDROID_NDK_HOME': _androidNdk().path,
    },
  );

  final List<File> artifacts = _findArtifacts(upstream, target);
  final Directory output = Directory.fromUri(repositoryRoot.uri.resolve('.mp-sdk/${target.name}/'));
  if (output.existsSync()) output.deleteSync(recursive: true);
  output.createSync(recursive: true);
  final List<File> copied = <File>[];
  for (final File artifact in artifacts) {
    copied.add(await artifact.copy(output.uri.resolve(_baseName(artifact)).toFilePath()));
  }
  await _makeLibrariesRelocatable(copied, target: target, workingDirectory: repositoryRoot.path);
  await _writeManifest(output, target.name, copied);
  stdout.writeln('Built ${copied.length} libraries in ${output.path}');
}

Future<NativeTarget> _readTarget(List<String> arguments) async {
  if (arguments.isEmpty) return NativeTarget.host();
  if (arguments case ['--target', final String value]) {
    return NativeTarget.parse(value);
  }
  throw const FormatException('Usage: build_native.dart [--target <os-architecture>]');
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

void _applyCompatibilityPatches(Directory repositoryRoot, Directory upstream, NativeTarget target) {
  final String javaDependency = target.isAndroid
      ? 'bazel_dep(name = "rules_android_ndk", version = "0.1.3")\n'
            'android_ndk_repository_extension = use_extension(\n'
            '    "@rules_android_ndk//:extension.bzl",\n'
            '    "android_ndk_repository_extension",\n'
            ')\n'
            'android_ndk_repository_extension.configure(api_level = 24)\n'
            'use_repo(android_ndk_repository_extension, "androidndk")\n'
            'register_toolchains("@androidndk//:all")\n\n'
            'bazel_dep(name = "rules_java", version = "8.3.2")'
      : 'bazel_dep(name = "rules_java", version = "8.3.2")';
  _replaceExactly(
    File.fromUri(upstream.uri.resolve('MODULE.bazel')),
    'bazel_dep(name = "rules_java", version = "7.10.0")\n'
        'single_version_override(\n'
        '    module_name = "rules_java",\n'
        '    version = "7.10.0",\n'
        ')',
    '$javaDependency\n'
        'single_version_override(\n'
        '    module_name = "rules_java",\n'
        '    version = "8.3.2",\n'
        ')',
  );

  const String patchName = 'opencv_modern_toolchains.patch';
  final File sourcePatch = File.fromUri(
    repositoryRoot.uri.resolve('tool/patches/opencv-modern-toolchains.patch'),
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
  _replaceExactly(
    File.fromUri(upstream.uri.resolve('third_party/BUILD')),
    '        "BUILD_EXAMPLES": "OFF",\n'
        '        "BUILD_SHARED_LIBS": "ON" if OPENCV_SHARED_LIBS else "OFF",',
    '        "BUILD_EXAMPLES": "OFF",\n'
        '        # Build image dependencies inside the sandbox. Host discovery can\n'
        '        # otherwise find a library without making its headers available.\n'
        '        "BUILD_ZLIB": "ON",\n'
        '        "BUILD_PNG": "ON",\n'
        '        # OpenCV 3.4 cannot generate projects for current Android SDKs.\n'
        '        "BUILD_ANDROID_PROJECTS": "OFF",\n'
        '        "BUILD_SHARED_LIBS": "ON" if OPENCV_SHARED_LIBS else "OFF",',
  );
  if (target.isAndroid) {
    _replaceExactly(
      File.fromUri(upstream.uri.resolve('third_party/BUILD')),
      '        "BUILD_ANDROID_PROJECTS": "OFF",\n'
          '        "BUILD_SHARED_LIBS": "ON" if OPENCV_SHARED_LIBS else "OFF",',
      '        "BUILD_ANDROID_PROJECTS": "OFF",\n'
          '        # rules_android_ndk does not expose its C++ runtime to\n'
          '        # rules_foreign_cc. OpenCV is linked with clang rather than\n'
          '        # clang++, so supply the shared runtime explicitly.\n'
          '        "CMAKE_CXX_STANDARD_LIBRARIES": "-lc++_shared -lc -lm -latomic -ldl -landroid -llog",\n'
          '        # Every Android shared object must be compatible with 16 KB\n'
          '        # page-size devices, including foreign CMake outputs.\n'
          '        "CMAKE_SHARED_LINKER_FLAGS": "-Wl,-z,noexecstack -Wl,-z,separate-code -Wl,--no-rosegment -Wl,-z,max-page-size=16384 -Wl,-z,common-page-size=16384 -Wl,--gc-sections -Wl,--build-id=md5 -Wl,--exclude-libs,libunwind.a -fuse-ld=lld -Wl,--icf=safe -Wl,--no-undefined",\n'
          '        "BUILD_SHARED_LIBS": "ON" if OPENCV_SHARED_LIBS else "OFF",',
    );
  } else if (target.os == 'macos') {
    _replaceExactly(
      File.fromUri(upstream.uri.resolve('third_party/BUILD')),
      '        "BUILD_ANDROID_PROJECTS": "OFF",\n'
          '        "BUILD_SHARED_LIBS": "ON" if OPENCV_SHARED_LIBS else "OFF",',
      '        "BUILD_ANDROID_PROJECTS": "OFF",\n'
          '        # Xcode 16 cannot compile OpenCV 3.4 CPU feature probes with\n'
          '        # their original warning policy. ARM64 already guarantees\n'
          '        # NEON, so use the compiler target as the baseline.\n'
          '        "CPU_BASELINE": "DETECT",\n'
          '        "BUILD_SHARED_LIBS": "ON" if OPENCV_SHARED_LIBS else "OFF",',
    );
  }
}

void _replaceExactly(File file, String original, String replacement) {
  final String contents = file.readAsStringSync();
  if (contents.contains(replacement)) return;
  if (!contents.contains(original)) {
    throw StateError('Compatibility patch no longer matches ${file.path}.');
  }
  file.writeAsStringSync(contents.replaceFirst(original, replacement));
}

List<File> _findArtifacts(Directory upstream, NativeTarget target) {
  final Directory output = Directory.fromUri(upstream.uri.resolve('bazel-bin/mediapipe/tasks/c/'));
  final List<File> candidates = output
      .listSync()
      .whereType<File>()
      .where((File file) => file.uri.pathSegments.last == target.libraryName)
      .toList();
  if (candidates.length != 1) {
    throw StateError('Expected one ${target.libraryName} in ${output.path}, found $candidates.');
  }
  final Directory openCvOutput = Directory.fromUri(
    upstream.uri.resolve('bazel-bin/third_party/opencv_cmake/lib/'),
  );
  final List<File> openCvLibraries =
      openCvOutput
          .listSync()
          .whereType<File>()
          .where((File file) => _isSharedLibrary(_baseName(file), target.os))
          .toList()
        ..sort((File left, File right) => left.path.compareTo(right.path));
  if (openCvLibraries.isEmpty) {
    throw StateError('No OpenCV shared libraries found in ${openCvOutput.path}.');
  }
  return <File>[
    candidates.single,
    ...openCvLibraries,
    if (target.isAndroid) _androidCxxRuntime(target),
  ];
}

File _androidCxxRuntime(NativeTarget target) {
  final Directory prebuilt = Directory.fromUri(
    _androidNdk().uri.resolve('toolchains/llvm/prebuilt/'),
  );
  final List<Directory> hosts = prebuilt.listSync().whereType<Directory>().toList();
  if (hosts.length != 1) {
    throw StateError('Expected one Android NDK host toolchain in ${prebuilt.path}.');
  }
  final String triple = switch (target.architecture) {
    'arm' => 'arm-linux-androideabi',
    'arm64' => 'aarch64-linux-android',
    'x64' => 'x86_64-linux-android',
    _ => throw StateError('Unsupported Android architecture: ${target.architecture}.'),
  };
  final File runtime = File.fromUri(
    hosts.single.uri.resolve('sysroot/usr/lib/$triple/libc++_shared.so'),
  );
  if (!runtime.existsSync()) {
    throw StateError('Android C++ runtime does not exist at ${runtime.path}.');
  }
  return runtime;
}

bool _isSharedLibrary(String name, String os) => switch (os) {
  'macos' => name.endsWith('.dylib'),
  'linux' || 'android' => name.endsWith('.so') || name.contains('.so.'),
  'windows' => name.endsWith('.dll'),
  _ => false,
};

String _baseName(File file) => file.uri.pathSegments.last;

Future<void> _makeLibrariesRelocatable(
  List<File> libraries, {
  required NativeTarget target,
  required String workingDirectory,
}) async {
  if (target.os == 'macos') {
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
  } else if (target.os == 'linux') {
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

Directory _androidNdk() {
  const String pinnedVersion = '28.2.13676358';
  final String? explicit = Platform.environment['ANDROID_NDK_HOME'];
  final String? sdk =
      Platform.environment['ANDROID_SDK_ROOT'] ?? Platform.environment['ANDROID_HOME'];
  final Directory ndk = explicit != null && explicit.isNotEmpty
      ? Directory(explicit)
      : sdk != null && sdk.isNotEmpty
      ? Directory.fromUri(Directory(sdk).uri.resolve('ndk/$pinnedVersion/'))
      : throw StateError(
          'Set ANDROID_NDK_HOME, ANDROID_SDK_ROOT, or ANDROID_HOME to build Android artifacts.',
        );
  if (!ndk.existsSync()) {
    throw StateError('Android NDK does not exist at ${ndk.path}.');
  }
  return ndk;
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
