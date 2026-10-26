import 'dart:async';

import 'package:mp_core/mp_core.dart';
import 'package:test/test.dart';

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

  test('records queue wait, processing time, and throughput in stats', () async {
    Duration now = Duration.zero;
    final LatestFrameScheduler<int> scheduler = LatestFrameScheduler<int>(
      (int value) async => now += Duration(milliseconds: value),
      statsWindow: 4,
      clock: () => now,
    );

    final LatestFrameStats empty = scheduler.stats;

    expect(empty.processedCount, 0);
    expect(empty.processedPerSecond, 0);
    expect(empty.lastProcessing, isNull);
    expect(empty.processingP50, isNull);

    scheduler.submit(10);
    await scheduler.idle;
    now += const Duration(milliseconds: 5);
    scheduler.submit(30);
    await scheduler.idle;

    final LatestFrameStats stats = scheduler.stats;

    expect(stats.submittedCount, 2);
    expect(stats.processedCount, 2);
    expect(stats.droppedCount, 0);
    expect(stats.staleCount, 0);
    expect(stats.failedCount, 0);
    expect(stats.lastProcessing, const Duration(milliseconds: 30));
    expect(stats.lastQueueWait, Duration.zero);
    expect(stats.processingP50, const Duration(milliseconds: 10));
    expect(stats.processingP95, const Duration(milliseconds: 30));
    expect(stats.queueWaitP50, Duration.zero);
    expect(stats.queueWaitP95, Duration.zero);
    expect(stats.processedPerSecond, 2);

    now += const Duration(seconds: 2);

    expect(scheduler.stats.processedPerSecond, 0);

    await scheduler.close();
  });

  test('drops a waiting frame that exceeded the maximum queue age', () async {
    Duration now = Duration.zero;
    final Completer<void> release = Completer<void>();
    final List<int> processed = <int>[];
    final LatestFrameScheduler<int> scheduler = LatestFrameScheduler<int>(
      (int value) async {
        processed.add(value);
        if (value == 1) await release.future;
      },
      maxQueueAge: const Duration(milliseconds: 100),
      clock: () => now,
    );

    scheduler.submit(1);
    await Future<void>.delayed(Duration.zero);
    scheduler.submit(2);
    now += const Duration(milliseconds: 250);
    release.complete();
    await scheduler.idle;

    expect(processed, <int>[1]);
    expect(scheduler.staleCount, 1);
    expect(scheduler.droppedCount, 0);
    expect(scheduler.processedCount, 1);
    expect(scheduler.stats.staleCount, 1);

    // A fresh frame after the stall is processed normally.
    scheduler.submit(3);
    await scheduler.idle;

    expect(processed, <int>[1, 3]);
    await scheduler.close();
  });

  test('rejects a non-positive maximum queue age', () {
    expect(
      () => LatestFrameScheduler<int>((int _) async {}, maxQueueAge: Duration.zero),
      throwsArgumentError,
    );
  });

  test('uses a monotonic stopwatch clock by default', () async {
    final LatestFrameScheduler<int> scheduler = LatestFrameScheduler<int>(
      (int _) => Future<void>.delayed(const Duration(milliseconds: 2)),
    );

    scheduler.submit(1);
    await scheduler.idle;

    expect(scheduler.stats.lastProcessing, greaterThanOrEqualTo(const Duration(milliseconds: 1)));
    expect(scheduler.stats.processedPerSecond, 1);
    await scheduler.close();
  });
}
