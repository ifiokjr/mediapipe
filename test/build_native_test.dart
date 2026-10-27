import 'dart:io';

import 'package:test/test.dart';

import '../tool/build_native.dart';
import '../tool/native_target.dart';

// The anchors the builder patches, copied verbatim from MediaPipe v1.0.0.
const String _upstreamModule = '''
bazel_dep(name = "rules_java", version = "7.10.0")
single_version_override(
    module_name = "rules_java",
    version = "7.10.0",
)
''';

const String _upstreamThirdPartyBuild = '''
exports_files([
    "LICENSE",
])

OPENCV_SO_VERSION = "3.4"

        "//conditions:default": ["libopencv_%s.so.%s" % (module, OPENCV_SO_VERSION) for module in OPENCV_MODULES],

        "BUILD_EXAMPLES": "OFF",
        "BUILD_SHARED_LIBS": "ON" if OPENCV_SHARED_LIBS else "OFF",
''';

const String _upstreamWorkspace = '''
http_archive(
    name = "opencv",
    build_file_content = all_content,
    strip_prefix = "opencv-3.4.11",
)
''';

const String _upstreamBuild = '''
cc_binary(
    name = "mediapipe_source",
    linkopts = select({
        "@platforms//os:linux": [
            "-Wl,-soname=libmediapipe.so",
        ],
        "//conditions:default": [],
    }),
    deps = [
        ":mediapipe_tasks_c_version_script.lds",
        "//mediapipe/tasks/c/vision/pose_landmarker:pose_landmarker_c_lib",
    ],
)
''';

const String _upstreamVersionScript = '''
VERS_1.0 {
  global:
    MpObjectDetector*;
    MpPoseLandmarker*;
  local:
    *;
};
''';

void main() {
  group('applyCompatibilityPatches', () {
    late Directory temporary;
    late Directory repositoryRoot;
    late Directory upstream;

    String read(String path) => File('${upstream.path}/$path').readAsStringSync();

    setUp(() {
      temporary = Directory.systemTemp.createTempSync('build_native_patches_');
      repositoryRoot = Directory.current;
      upstream = Directory('${temporary.path}/upstream')..createSync();
      Directory('${upstream.path}/mediapipe/tasks/c').createSync(recursive: true);
      Directory('${upstream.path}/third_party').createSync(recursive: true);
      File('${upstream.path}/MODULE.bazel').writeAsStringSync(_upstreamModule);
      File('${upstream.path}/WORKSPACE').writeAsStringSync(_upstreamWorkspace);
      File('${upstream.path}/third_party/BUILD').writeAsStringSync(_upstreamThirdPartyBuild);
      File('${upstream.path}/mediapipe/tasks/c/BUILD').writeAsStringSync(_upstreamBuild);
      File(
        '${upstream.path}/mediapipe/tasks/c/mediapipe_tasks_c_version_script.lds',
      ).writeAsStringSync(_upstreamVersionScript);
    });

    tearDown(() {
      temporary.deleteSync(recursive: true);
    });

    test('patches a Linux checkout and adds the pixel shim', () {
      applyCompatibilityPatches(repositoryRoot, upstream, NativeTarget.parse('linux-x64'));

      expect(read('MODULE.bazel'), contains('version = "8.3.2"'));
      expect(read('MODULE.bazel'), isNot(contains('rules_android_ndk')));
      expect(read('third_party/BUILD'), contains('"opencv_modern_toolchains.patch",'));
      expect(read('third_party/BUILD'), contains('"BUILD_ZLIB": "ON"'));
      expect(read('third_party/BUILD'), isNot(contains('CMAKE_CXX_STANDARD_LIBRARIES')));
      expect(read('third_party/BUILD'), isNot(contains('CPU_BASELINE')));
      expect(read('third_party/opencv_modern_toolchains.patch'), isNotEmpty);
      expect(
        read('WORKSPACE'),
        contains('patches = ["@//third_party:opencv_modern_toolchains.patch"],'),
      );
      expect(
        read('mediapipe/tasks/c/BUILD'),
        contains('srcs = ["mp_pixel_conversion.cc", "mp_pixel_conversion.h"],'),
      );
      expect(read('mediapipe/tasks/c/BUILD'), contains('        "@libyuv",\n    ],'));
      expect(read('mediapipe/tasks/c/BUILD'), isNot(contains('@platforms//os:android')));
      expect(
        read('mediapipe/tasks/c/mediapipe_tasks_c_version_script.lds'),
        contains('    MpObjectDetector*;\n    MpPixel*;\n    MpPoseLandmarker*;'),
      );
      expect(
        read('mediapipe/tasks/c/mp_pixel_conversion.cc'),
        File('${repositoryRoot.path}/tool/native/mp_pixel_conversion.cc').readAsStringSync(),
      );
      expect(File('${upstream.path}/mediapipe/tasks/c/mp_pixel_conversion.h').existsSync(), isTrue);
    });

    test('adds the Android toolchain, linker, and CMake settings', () {
      applyCompatibilityPatches(repositoryRoot, upstream, NativeTarget.parse('android-arm64'));

      expect(read('MODULE.bazel'), contains('rules_android_ndk'));
      expect(read('MODULE.bazel'), contains('register_toolchains("@androidndk//:all")'));
      expect(read('mediapipe/tasks/c/BUILD'), contains('"@platforms//os:android": ['));
      expect(
        read('third_party/BUILD'),
        contains('["libopencv_%s.so" % module for module in OPENCV_MODULES]'),
      );
      expect(read('third_party/BUILD'), contains('CMAKE_CXX_STANDARD_LIBRARIES'));
      expect(read('third_party/BUILD'), contains('max-page-size=16384'));
    });

    test('keeps the NEON baseline for macOS', () {
      applyCompatibilityPatches(repositoryRoot, upstream, NativeTarget.parse('macos-arm64'));

      expect(read('third_party/BUILD'), contains('"CPU_BASELINE": "NEON"'));
      expect(read('MODULE.bazel'), isNot(contains('rules_android_ndk')));
    });

    test('is idempotent on an already patched checkout', () {
      final NativeTarget target = NativeTarget.parse('linux-x64');

      applyCompatibilityPatches(repositoryRoot, upstream, target);
      final String build = read('mediapipe/tasks/c/BUILD');
      final String module = read('MODULE.bazel');

      applyCompatibilityPatches(repositoryRoot, upstream, target);

      expect(read('mediapipe/tasks/c/BUILD'), build);
      expect(read('MODULE.bazel'), module);
      expect(build.split('"@libyuv"'), hasLength(2));
    });

    test('fails loudly when an upstream anchor moved', () {
      File('${upstream.path}/mediapipe/tasks/c/BUILD').writeAsStringSync('cc_binary(name = "x")');

      expect(
        () => applyCompatibilityPatches(repositoryRoot, upstream, NativeTarget.parse('linux-x64')),
        throwsStateError,
      );
    });
  });

  test('pins macOS native builds to the active Xcode toolchain', () async {
    final List<String> commands = <String>[];

    final Map<String, String> environment = await resolveMacOsToolchainEnvironment(
      commandRunner: (String executable, List<String> arguments) async {
        commands.add(<String>[executable, ...arguments].join(' '));
        return switch ((executable, arguments)) {
          ('xcode-select', ['--print-path']) => '/Applications/Xcode.app/Developer',
          _ => throw StateError('Unexpected command: $executable $arguments'),
        };
      },
    );

    expect(environment, <String, String>{
      'CC': '/usr/bin/clang',
      'CXX': '/usr/bin/clang++',
      'DEVELOPER_DIR': '/Applications/Xcode.app/Developer',
    });
    expect(commands, <String>['xcode-select --print-path']);
  });
}
