import 'dart:io';

import 'package:test/test.dart';

void main() {
  test('hook/ contains only the hook entrypoint pub.dev allows', () {
    // pub.dev's package reader accepts only hook/build.dart and hook/link.dart
    // as Dart files under hook/ and rejects anything else, which failed the
    // 0.1.0 upload with "Hook files are experimental and
    // `hook/native_artifact.dart` is not allowed yet". Helper code belongs in
    // lib/ (imported from the hook with a package: URI).
    final List<String> hookDartFiles =
        Directory('hook')
            .listSync(recursive: true)
            .whereType<File>()
            .map((File file) => file.path.replaceAll(r'\', '/'))
            .where((String path) => path.endsWith('.dart'))
            .toList()
          ..sort();

    expect(hookDartFiles, <String>['hook/build.dart']);
  });
}
