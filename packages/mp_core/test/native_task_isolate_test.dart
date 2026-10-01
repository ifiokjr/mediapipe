@TestOn('vm')
library;

import 'dart:isolate';

import 'package:mp_core/mp_core.dart';
// The generated bindings expose their own MpStatus, so hide it and keep the
// hand-written status enum used by the public API.
import 'package:mp_core/native.dart' hide MpStatus;
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

  test('reports a missing native runtime as an actionable failure', () {
    // `dart:ffi` raises this shape when no code asset supplies the symbol. The
    // raw message names an internal asset id and never mentions the remedy.
    final ArgumentError raw = ArgumentError(
      "Couldn't resolve native function 'MpFaceDetectorCreate' in "
      "'package:mp_core/native.dart' : No asset with id "
      "'package:mp_core/native.dart' found. Available native assets: . "
      'Attempted to fallback to process lookup.',
    );

    final Object converted = nativeTaskFailure(raw);

    expect(converted, isA<MpException>());
    final MpException exception = converted as MpException;
    expect(exception.status, MpStatus.unavailable);
    expect(exception.message, contains('native_library_directory'));
  });

  test('leaves unrelated failures untouched', () {
    final Object original = StateError('something else');

    expect(nativeTaskFailure(original), same(original));
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
