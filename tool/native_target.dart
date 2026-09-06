import 'dart:io';

/// A native runtime target supported by the artifact build pipeline.
final class NativeTarget {
  const NativeTarget._(this.name, this.os, this.architecture);

  static const List<String> _androidLinkerArguments = <String>[
    '--linkopt=-Wl,-z,max-page-size=16384',
    '--linkopt=-Wl,-z,common-page-size=16384',
  ];

  static const Set<String> supportedNames = <String>{
    'android-arm',
    'android-arm64',
    'android-x64',
    'linux-arm64',
    'linux-x64',
    'macos-arm64',
    'macos-x64',
    'windows-x64',
  };

  final String name;
  final String os;
  final String architecture;

  bool get isAndroid => os == 'android';

  String get libraryName => switch (os) {
    'macos' => 'libmediapipe.dylib',
    'linux' || 'android' => 'libmediapipe.so',
    'windows' => 'libmediapipe.dll',
    _ => throw StateError('Unsupported native target OS: $os.'),
  };

  List<String> get bazelArguments => switch (name) {
    'android-arm' => const <String>['--config=android_arm', ..._androidLinkerArguments],
    'android-arm64' => const <String>['--config=android_arm64', ..._androidLinkerArguments],
    'android-x64' => const <String>[
      '--config=android',
      '--cpu=x86_64',
      '--fat_apk_cpu=x86_64',
      '--platforms=@//third_party/android:x86_64',
      ..._androidLinkerArguments,
    ],
    _ => const <String>[],
  };

  static NativeTarget parse(String name) {
    if (!supportedNames.contains(name)) {
      throw FormatException(
        'Unsupported native target: $name. Expected one of '
        '${supportedNames.join(', ')}.',
      );
    }
    final List<String> segments = name.split('-');
    return NativeTarget._(name, segments.first, segments.last);
  }

  static Future<NativeTarget> host() async {
    final String architecture = Platform.isWindows
        ? (Platform.environment['PROCESSOR_ARCHITECTURE'] ?? '').toLowerCase()
        : (await Process.run('uname', const <String>['-m'])).stdout.toString().trim();
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
    return parse('$os-$normalizedArchitecture');
  }
}
