import 'package:test/test.dart';

import '../tool/native_target.dart';

void main() {
  test('parses desktop targets and selects their main library', () {
    expect(NativeTarget.parse('macos-arm64').libraryName, 'libmediapipe.dylib');
    expect(NativeTarget.parse('linux-x64').libraryName, 'libmediapipe.so');
    expect(NativeTarget.parse('windows-x64').libraryName, 'libmediapipe.dll');
  });

  test('maps Flutter Android architectures to MediaPipe Bazel configs', () {
    expect(NativeTarget.parse('android-arm').bazelArguments, <String>[
      '--config=android_arm',
      '--linkopt=-Wl,-z,max-page-size=16384',
      '--linkopt=-Wl,-z,common-page-size=16384',
    ]);
    expect(NativeTarget.parse('android-arm64').bazelArguments, <String>[
      '--config=android_arm64',
      '--linkopt=-Wl,-z,max-page-size=16384',
      '--linkopt=-Wl,-z,common-page-size=16384',
    ]);
    expect(NativeTarget.parse('android-x64').bazelArguments, <String>[
      '--config=android',
      '--cpu=x86_64',
      '--fat_apk_cpu=x86_64',
      '--platforms=@//third_party/android:x86_64',
      '--linkopt=-Wl,-z,max-page-size=16384',
      '--linkopt=-Wl,-z,common-page-size=16384',
    ]);
  });

  test('rejects targets without an artifact implementation', () {
    expect(() => NativeTarget.parse('ios-arm64'), throwsFormatException);
    expect(() => NativeTarget.parse('android-x86'), throwsFormatException);
  });
}
