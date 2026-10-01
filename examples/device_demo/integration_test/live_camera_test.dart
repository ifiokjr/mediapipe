import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:mp_device_demo/playground/playground_app.dart';

/// Device smoke test. Requires camera permission and a bundled native runtime.
/// It checks actual camera frames through both real models, without assuming
/// that a person happens to be standing in front of the test device.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'camera runs pose inference, switches to face inference, and stops',
    (WidgetTester tester) async {
      await tester.pumpWidget(const MotionPlaygroundApp());
      await tester.ensureVisible(find.text('Start camera'));
      await tester.tap(find.text('Start camera'));
      await _waitForInference(tester);
      expect(find.text('● LIVE CAMERA'), findsOneWidget);

      await tester.ensureVisible(find.text('Face studio'));
      await tester.tap(find.text('Face studio'));
      await _waitForInference(tester);
      expect(find.text('3D FACE PLAY'), findsOneWidget);

      await tester.ensureVisible(find.text('Use demo'));
      await tester.tap(find.text('Use demo'));
      await tester.pump();
      expect(find.text('◌ ANIMATED DEMO'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    },
  );
}

Future<void> _waitForInference(WidgetTester tester) async {
  final DateTime deadline = DateTime.now().add(const Duration(seconds: 90));
  final Finder inference = find.textContaining('ms inference');

  while (inference.evaluate().isEmpty) {
    if (find.textContaining('Could not start:').evaluate().isNotEmpty ||
        find.textContaining('Tracking interrupted:').evaluate().isNotEmpty) {
      fail(
        'Live tracking failed: ${tester.widget<Text>(find.textContaining(RegExp('Could not start:|Tracking interrupted:'))).data}',
      );
    }

    if (DateTime.now().isAfter(deadline))
      fail('Timed out waiting for real camera inference.');
    await tester.pump(const Duration(milliseconds: 100));
  }

  // The latency label is shown only once initialization completes; require a
  // tracking result too so merely opening a camera cannot satisfy this test.
  while (find.textContaining('No person found').evaluate().isEmpty &&
      find.textContaining('Tracking live').evaluate().isEmpty) {
    if (find.textContaining('Tracking interrupted:').evaluate().isNotEmpty) {
      fail('Frame inference failed.');
    }

    if (DateTime.now().isAfter(deadline))
      fail('Camera opened but no result arrived.');
    await tester.pump(const Duration(milliseconds: 100));
  }
}
