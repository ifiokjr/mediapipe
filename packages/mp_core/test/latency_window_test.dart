import 'package:mp_core/mp_core.dart';
import 'package:test/test.dart';

void main() {
  group('LatencyWindow', () {
    test('rejects a non-positive capacity', () {
      expect(() => LatencyWindow(capacity: 0), throwsArgumentError);
    });

    test('is empty until a sample arrives', () {
      final LatencyWindow window = LatencyWindow(capacity: 4);

      expect(window.isEmpty, isTrue);
      expect(window.count, 0);
      expect(window.last, isNull);
      expect(window.p50, isNull);
      expect(window.p95, isNull);
      expect(window.max, isNull);
      expect(window.mean, isNull);
    });

    test('answers nearest-rank percentiles over retained samples', () {
      final LatencyWindow window = LatencyWindow(capacity: 10);

      for (final int millis in <int>[50, 10, 30, 20, 40]) {
        window.add(Duration(milliseconds: millis));
      }

      expect(window.count, 5);
      expect(window.last, const Duration(milliseconds: 40));
      expect(window.p50, const Duration(milliseconds: 30));
      expect(window.p95, const Duration(milliseconds: 50));
      expect(window.max, const Duration(milliseconds: 50));
      expect(window.mean, const Duration(milliseconds: 30));
      expect(window.percentile(0), const Duration(milliseconds: 10));
    });

    test('evicts the oldest sample once full', () {
      final LatencyWindow window = LatencyWindow(capacity: 3);

      for (final int millis in <int>[100, 1, 2, 3]) {
        window.add(Duration(milliseconds: millis));
      }

      expect(window.count, 3);
      expect(window.max, const Duration(milliseconds: 3));
      expect(window.mean, const Duration(milliseconds: 2));
    });

    test('clear discards every sample', () {
      final LatencyWindow window = LatencyWindow(capacity: 3)..add(const Duration(seconds: 1));

      window.clear();

      expect(window.isEmpty, isTrue);
      expect(window.last, isNull);

      window.add(const Duration(seconds: 2));

      expect(window.max, const Duration(seconds: 2));
    });

    test('rejects percentiles outside 0–100', () {
      final LatencyWindow window = LatencyWindow()..add(Duration.zero);

      expect(() => window.percentile(-1), throwsRangeError);
      expect(() => window.percentile(101), throwsRangeError);
    });
  });
}
