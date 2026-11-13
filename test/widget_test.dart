import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';
import 'package:spiral_pass_play/main.dart';

void main() {
  testWidgets(
    'Setup opens with three players and supports changing the count',
    (tester) async {
      SharedPreferencesAsyncPlatform.instance =
          InMemorySharedPreferencesAsync.empty();
      await tester.pumpWidget(const SpiralApp());
      await tester.pumpAndSettle();

      expect(find.text('SPIRAL QUEST'), findsOneWidget);
      expect(find.byType(TextFormField), findsNWidgets(3));
      expect(find.text('START GAME'), findsOneWidget);
      expect(find.text('BOARD STUDIO'), findsNothing);

      await tester.tap(find.widgetWithText(ChoiceChip, '2'));
      await tester.pumpAndSettle();

      expect(find.byType(TextFormField), findsNWidgets(2));
      expect(tester.takeException(), isNull);
    },
  );
  for (final size in [const Size(360, 800), const Size(800, 360)]) {
    testWidgets('Setup fits $size with larger text', (tester) async {
      SharedPreferencesAsyncPlatform.instance =
          InMemorySharedPreferencesAsync.empty();
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      tester.platformDispatcher.textScaleFactorTestValue = 1.25;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      await tester.pumpWidget(const SpiralApp());
      await tester.pumpAndSettle();
      expect(find.text('START GAME'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }
}
