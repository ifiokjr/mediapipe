import 'package:mp_core/mp_core.dart';
import 'package:test/test.dart';

void main() {
  test('TaskLifecycle is idempotent and guards closed tasks', () {
    final TaskLifecycle lifecycle = TaskLifecycle('Detector');

    expect(lifecycle.isClosed, isFalse);
    expect(lifecycle.markClosed(), isTrue);
    expect(lifecycle.markClosed(), isFalse);
    expect(lifecycle.ensureOpen, throwsA(isA<MpTaskClosedError>()));
  });

  test('TimestampTracker requires monotonically increasing values', () {
    final TimestampTracker tracker = TimestampTracker()
      ..add(0)
      ..add(10);

    expect(tracker.lastTimestampMs, 10);
    expect(() => tracker.add(10), throwsArgumentError);
    expect(() => TimestampTracker().add(-1), throwsArgumentError);
  });
}
