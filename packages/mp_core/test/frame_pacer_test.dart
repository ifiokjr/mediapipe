import 'package:mp_core/mp_core.dart';
import 'package:test/test.dart';

void main() {
  group('FramePacer', () {
    test('rejects non-positive intervals and rates', () {
      expect(() => FramePacer(minInterval: Duration.zero), throwsArgumentError);
      expect(() => FramePacer.targetFps(0), throwsArgumentError);
      expect(() => FramePacer.targetFps(double.infinity), throwsArgumentError);
    });

    test('derives the interval from a target frame rate', () {
      expect(FramePacer.targetFps(30).minInterval, const Duration(microseconds: 33333));
      expect(FramePacer.targetFps(15).minInterval, const Duration(microseconds: 66667));
    });

    test('admits one frame per interval by timestamp', () {
      final FramePacer pacer = FramePacer(minInterval: const Duration(milliseconds: 66));

      expect(pacer.admit(0), isTrue);
      expect(pacer.admit(33), isFalse);
      expect(pacer.admit(65), isFalse);
      expect(pacer.admit(66), isTrue);
      expect(pacer.admit(99), isFalse);
      expect(pacer.admit(140), isTrue);

      expect(pacer.admittedCount, 3);
      expect(pacer.skippedCount, 3);
      expect(pacer.lastAdmittedTimestampMs, 140);
    });

    test('always admits a timestamp that runs backwards', () {
      final FramePacer pacer = FramePacer(minInterval: const Duration(seconds: 1));

      expect(pacer.admit(5000), isTrue);
      expect(pacer.admit(5100), isFalse);
      expect(pacer.admit(10), isTrue);
      expect(pacer.lastAdmittedTimestampMs, 10);
    });

    test('reset forgets history and counters', () {
      final FramePacer pacer = FramePacer(minInterval: const Duration(seconds: 1));
      pacer
        ..admit(0)
        ..admit(1)
        ..reset();

      expect(pacer.lastAdmittedTimestampMs, isNull);
      expect(pacer.admittedCount, 0);
      expect(pacer.skippedCount, 0);
      expect(pacer.admit(1), isTrue);
    });
  });
}
