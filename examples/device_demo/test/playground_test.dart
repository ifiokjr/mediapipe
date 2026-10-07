import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mp_device_demo/playground/playground_app.dart';

void main() {
  testWidgets('choose movements, customize the character, and layer face accessories', (
    WidgetTester tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1440, 1200));
    tester.view.physicalSize = const Size(1440, 1200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(const MotionPlaygroundApp());
    expect(find.text('◌ ANIMATED DEMO'), findsOneWidget);
    expect(find.text('00'), findsOneWidget);
    await tester.tap(find.text('Burpees'));
    await tester.pump();
    expect(find.text('Crouch, plank, crouch, jump, then land.'), findsOneWidget);
    await tester.ensureVisible(find.text('Neon noodle'));
    await tester.tap(find.text('Neon noodle'));
    await tester.pump();
    await tester.tap(find.byTooltip('Sky accent'));
    await tester.pump();
    expect(tester.takeException(), isNull);
    await tester.ensureVisible(find.text('Face studio'));
    await tester.tap(find.text('Face studio'));
    await tester.pump();
    await tester.tap(find.text('Crown'));
    await tester.pump();
    await tester.tap(find.text('Robot ears'));
    await tester.pump();
    expect(find.text('3D FACE PLAY'), findsOneWidget);
    expect(find.text('00'), findsNothing);
    await tester.tap(find.byTooltip('Use dark theme'));
    await tester.pump();
    expect(find.byTooltip('Use light theme'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('the theme follows the platform brightness until toggled', (
    WidgetTester tester,
  ) async {
    tester.binding.platformDispatcher.platformBrightnessTestValue = Brightness.dark;
    addTearDown(tester.binding.platformDispatcher.clearPlatformBrightnessTestValue);
    await tester.pumpWidget(const MotionPlaygroundApp());

    expect(find.byTooltip('Use light theme'), findsOneWidget);
    await tester.tap(find.byTooltip('Use light theme'));
    await tester.pump();
    expect(find.byTooltip('Use dark theme'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('phone layout scrolls to all ten exercises without overflow', (
    WidgetTester tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(const MotionPlaygroundApp());
    await tester.ensureVisible(find.text('Side bends'));
    await tester.tap(find.text('Side bends'));
    await tester.pump();
    expect(find.text('Lean sideways, then return to the center.'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });
}
