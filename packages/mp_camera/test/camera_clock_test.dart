import 'package:flutter_test/flutter_test.dart';
import 'package:mp_camera/mp_camera.dart';

void main() {
  test('advances equal clock readings by one millisecond', () {
    final MpCameraClock clock = MpCameraClock();

    // Two requests in the same millisecond must still produce strictly
    // increasing timestamps, because video and live-stream tasks reject
    // repeated values.
    final int first = clock.nextTimestampMs();
    final int second = clock.nextTimestampMs();

    expect(second, greaterThan(first));
    expect(clock.lastTimestampMs, second);
  });

  test('never rewinds, even after the stopwatch stalls', () {
    final MpCameraClock clock = MpCameraClock();

    final List<int> readings = <int>[for (var i = 0; i < 500; i++) clock.nextTimestampMs()];
    for (var i = 1; i < readings.length; i++) {
      expect(readings[i], greaterThan(readings[i - 1]));
    }
  });

  test('starts at or after zero', () {
    final MpCameraClock clock = MpCameraClock();

    expect(clock.nextTimestampMs(), greaterThanOrEqualTo(0));
  });
}
