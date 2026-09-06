@TestOn('vm')
library;

import 'dart:isolate';

import 'package:mp_core/native.dart';
import 'package:test/test.dart';

void main() {
  test('keeps state on one worker and returns typed results', () async {
    final NativeTaskIsolate worker = await NativeTaskIsolate.spawn(
      factory: _counterFactory,
      initialMessage: 3,
    );

    expect(await worker.request<int>(2), 5);
    expect(await worker.request<int>(4), 9);

    await worker.dispose();
  });

  test('forwards worker errors without stopping later requests', () async {
    final NativeTaskIsolate worker = await NativeTaskIsolate.spawn(
      factory: _counterFactory,
      initialMessage: 0,
    );

    await expectLater(worker.request<int>('invalid'), throwsArgumentError);
    expect(await worker.request<int>(2), 2);

    await worker.dispose();
  });

  test('fails pending work if the worker exits', () async {
    final NativeTaskIsolate worker = await NativeTaskIsolate.spawn(
      factory: _counterFactory,
      initialMessage: 0,
    );

    await expectLater(worker.request<int>('exit'), throwsStateError);
    expect(() => worker.request<int>(1), throwsStateError);
    await worker.dispose();
  });
}

NativeTaskWorkerHandler _counterFactory(Object? initialMessage) {
  var value = initialMessage! as int;
  return (Object? command) {
    if (command == 'exit') Isolate.exit();
    if (command is! int) throw ArgumentError.value(command, 'command');
    return value += command;
  };
}
