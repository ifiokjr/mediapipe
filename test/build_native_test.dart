import 'package:test/test.dart';

import '../tool/build_native.dart';

void main() {
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
