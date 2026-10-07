import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:mp_camera/mp_camera.dart';
import 'package:mp_core/mp_core.dart';

void main() {
  test('processes one frame and keeps only the latest waiting frame', () async {
    final Completer<void> firstFrame = Completer<void>();
    final List<int> processed = <int>[];
    final LatestFrameScheduler<int> scheduler = LatestFrameScheduler<int>((int value) async {
      processed.add(value);
      if (value == 1) await firstFrame.future;
    });

    scheduler.submit(1);
    await Future<void>.delayed(Duration.zero);
    scheduler.submit(2);
    scheduler.submit(3);
    firstFrame.complete();
    await scheduler.idle;

    expect(processed, <int>[1, 3]);
    expect(scheduler.submittedCount, 3);
    expect(scheduler.processedCount, 2);
    expect(scheduler.droppedCount, 1);
  });

  test('close drains work and rejects new frames', () async {
    final LatestFrameScheduler<int> scheduler = LatestFrameScheduler<int>((int _) async {});
    scheduler.submit(1);

    await scheduler.close();

    expect(scheduler.isClosed, isTrue);
    expect(() => scheduler.submit(2), throwsA(isA<MpTaskClosedError>()));
  });

  test('reports a failed frame and continues with the latest frame', () async {
    final List<LatestFrameFailure<int>> failures = <LatestFrameFailure<int>>[];
    final List<int> processed = <int>[];
    final LatestFrameScheduler<int> scheduler = LatestFrameScheduler<int>((int value) async {
      if (value == 1) throw StateError('bad frame');
      processed.add(value);
    });
    final StreamSubscription<LatestFrameFailure<int>> subscription = scheduler.failures.listen(
      failures.add,
    );

    scheduler.submit(1);
    scheduler.submit(2);
    await scheduler.idle;

    expect(failures, hasLength(1));
    expect(failures.single.item, 1);
    expect(failures.single.error, isA<StateError>());
    expect(processed, <int>[2]);
    expect(scheduler.failedCount, 1);
    expect(scheduler.processedCount, 1);

    await scheduler.close();
    await subscription.cancel();
  });

  test('close is idempotent and completes without submissions', () async {
    final LatestFrameScheduler<int> scheduler = LatestFrameScheduler<int>((int _) async {});

    await scheduler.idle;

    await scheduler.close();
    await scheduler.close();
    expect(scheduler.isClosed, isTrue);
  });

  test('a throwing failures listener does not stop processing', () async {
    final List<int> processed = <int>[];
    final List<Object> zoneErrors = <Object>[];
    final LatestFrameScheduler<int> scheduler = LatestFrameScheduler<int>((int value) async {
      processed.add(value);
      if (value.isEven) throw StateError('bad frame');
    });

    await runZonedGuarded(() async {
      final StreamSubscription<LatestFrameFailure<int>> subscription = scheduler.failures.listen((
        LatestFrameFailure<int> failure,
      ) {
        throw StateError('listener blew up');
      });

      scheduler.submit(2);
      scheduler.submit(3);
      await scheduler.idle;
      await subscription.cancel();
    }, (Object error, StackTrace _) => zoneErrors.add(error));

    expect(zoneErrors, hasLength(1));
    expect(processed, <int>[2, 3]);
    expect(scheduler.failedCount, 1);
    expect(scheduler.processedCount, 1);
  });
}
