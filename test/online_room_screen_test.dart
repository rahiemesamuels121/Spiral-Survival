import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:spiral_pass_play/app/theme.dart';
import 'package:spiral_pass_play/firebase_config.dart';
import 'package:spiral_pass_play/features/multiplayer/presentation/online_room_screen.dart';

void main() {
  for (final size in [const Size(320, 640), const Size(800, 360)]) {
    testWidgets('Online character picker offers only three classes at $size', (
      tester,
    ) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      tester.platformDispatcher.textScaleFactorTestValue = 1.25;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      await tester.pumpWidget(
        MaterialApp(theme: AppTheme.dark, home: const OnlineRoomScreen()),
      );
      final choose = find.text('CHOOSE CHARACTER · Locks when the host starts');
      await tester.ensureVisible(choose);
      await tester.tap(choose);
      await tester.pumpAndSettle();
      expect(find.text('Choose your character'), findsOneWidget);
      expect(
        find.descendant(
          of: find.byType(AlertDialog),
          matching: find.byType(OutlinedButton),
        ),
        findsNWidgets(3),
      );
      expect(
        find.descendant(
          of: find.byType(AlertDialog),
          matching: find.text('Rocket'),
        ),
        findsNothing,
      );
      await tester.ensureVisible(find.text('Swimmer'));
      await tester.tap(find.text('Swimmer'));
      await tester.pumpAndSettle();
      expect(find.text('Swimmer'), findsOneWidget);
      expect(find.text('Choose your character'), findsNothing);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }

  testWidgets('Online lobby is available in a standard build', (tester) async {
    expect(FirebaseConfig.configured, isTrue);
    await tester.pumpWidget(
      MaterialApp(theme: AppTheme.dark, home: const OnlineRoomScreen()),
    );
    expect(find.text('CREATE ROOM'), findsOneWidget);
    expect(find.text('JOIN ROOM'), findsOneWidget);
    expect(find.textContaining('not enabled in this build'), findsNothing);
    await tester.enterText(find.byType(TextField).first, 'Alex');
    expect(find.text('Alex'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
