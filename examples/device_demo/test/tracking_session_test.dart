import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mp_core/mp_core.dart';
import 'package:mp_device_demo/playground/tracking_session.dart';

void main() {
  test('camera cleanup errors are visible and a subsequent retry can recover', () async {
    final TrackingSession session = TrackingSession()..camera = _FailingCamera();
    await session.configure(enabled: false, faceMode: false);
    expect(session.status, contains('Resource cleanup failed'));
    expect(session.loading, isFalse);
    await session.configure(enabled: false, faceMode: false);
    expect(session.status, 'Camera off · animated demo');
    session.dispose();
  });
  test('upright frames rotate dimensions and pixel positions together', () {
    final MpImageUint8 image = MpImageUint8(
      width: 2,
      height: 3,
      format: MpImageFormat.gray8,
      data: Uint8List.fromList(<int>[1, 2, 3, 4, 5, 6]),
    );
    expect(uprightImage(image, 90).data, <int>[5, 3, 1, 6, 4, 2]);
    expect(uprightImage(image, 90).width, 3);
    expect(uprightImage(image, 90).height, 2);
    expect(uprightImage(image, 180).data, <int>[6, 5, 4, 3, 2, 1]);
    expect(uprightImage(image, 270).data, <int>[2, 4, 6, 1, 3, 5]);
    expect(uprightImage(image, 0), same(image));
    expect(() => uprightImage(image, 45), throwsArgumentError);
  });

  test('disposal while a mode change is queued never notifies a dead view', () async {
    final TrackingSession session = TrackingSession();
    final Future<void> first = session.configure(enabled: false, faceMode: true);
    final Future<void> second = session.configure(enabled: false, faceMode: false);
    session.dispose();
    await first;
    await second;
  });

  test('live mode on an unsupported platform reports the demo fallback', () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);

    final TrackingSession session = TrackingSession();
    await session.configure(enabled: true, faceMode: false);

    expect(session.status, contains('Live camera requires Android or iOS'));
    expect(session.status, isNot(contains('UnsupportedError')));
    expect(session.loading, isFalse);
    expect(session.camera, isNull);
    session.dispose();
  });

  test('statuses surface messages without exception prefixes', () {
    expect(
      describeSessionError(StateError('Camera permission denied. Enable it in Settings.')),
      'Camera permission denied. Enable it in Settings.',
    );
    expect(
      describeSessionError(const MpException(MpStatus.unavailable, 'No camera found.')),
      'No camera found.',
    );
    expect(describeSessionError('plain failure'), 'plain failure');
  });
}

class _FailingCamera extends CameraController {
  _FailingCamera()
    : super(
        const CameraDescription(
          name: 'fake',
          lensDirection: CameraLensDirection.front,
          sensorOrientation: 90,
        ),
        ResolutionPreset.medium,
      );

  @override
  Future<void> dispose() async {
    await super.dispose();
    throw StateError('Simulated platform cleanup failure');
  }
}
