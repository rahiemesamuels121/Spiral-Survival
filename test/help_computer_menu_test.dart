import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';
import 'package:spiral_pass_play/app/theme.dart';
import 'package:spiral_pass_play/main.dart';
import 'package:spiral_pass_play/features/game/data/board_repository.dart';
import 'package:spiral_pass_play/features/game/domain/board_definition.dart';
import 'package:spiral_pass_play/features/game/presentation/game_screen.dart';
import 'package:spiral_pass_play/features/help/help_screen.dart';
import 'package:spiral_pass_play/features/help/tile_guide.dart';

void main() {
  test('Every tile type has a meaningful guide entry', () {
    for (final type in TileType.values) {
      expect(tileGuide(type).title, isNotEmpty);
      expect(tileGuide(type).description.length, greaterThan(50));
    }
    expect(
      tileGuide(TileType.hospital).description,
      contains('5 real minutes'),
    );
    expect(
      tileGuide(TileType.secretSociety).description,
      contains('20 route spaces'),
    );
  });

  for (final size in [const Size(320, 640), const Size(800, 360)]) {
    testWidgets('Help is searchable and fits $size with larger text', (
      tester,
    ) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      tester.platformDispatcher.textScaleFactorTestValue = 1.25;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      final board = (await tester.runAsync(
        () => const BoardRepository().loadReferenceBoard(),
      ))!;
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.dark,
          home: HelpScreen(board: board),
        ),
      );
      expect(find.text('1. Choose a mode'), findsOneWidget);
      await tester.tap(find.text('TILE GUIDE'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'Secret Society');
      await tester.pump();
      expect(
        find.byWidgetPredicate(
          (widget) => widget is Text && widget.data == 'Secret Society',
        ),
        findsOneWidget,
      );
      expect(find.text('Spaces: 60'), findsOneWidget);
      await tester.enterText(find.byType(TextField), 'not-a-tile-xyz');
      await tester.pump();
      expect(find.text('No matching tiles.'), findsOneWidget);
      await tester.enterText(find.byType(TextField), 'Mines: red');
      await tester.pump();
      expect(find.text('Mines: red, blue and green'), findsOneWidget);
      tester.view.viewInsets = FakeViewPadding(
        bottom: size.height < 500 ? 220 : 300,
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(tester.takeException(), isNull);
      tester.view.resetViewInsets();
    });
  }

  testWidgets('Menu offers computer mode with one to four opponents and Help', (
    tester,
  ) async {
    SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.empty();
    await tester.pumpWidget(const SpiralApp());
    await tester.pumpAndSettle();
    expect(find.byType(TextFormField), findsNothing);
    final mode = find.text('VS COMPUTER');
    await tester.ensureVisible(mode);
    await tester.tap(mode);
    await tester.pumpAndSettle();
    expect(find.byType(TextFormField), findsOneWidget);
    expect(find.text('Number of computer opponents'), findsOneWidget);
    expect(find.widgetWithText(ChoiceChip, '1'), findsOneWidget);
    expect(find.widgetWithText(ChoiceChip, '4'), findsOneWidget);
    await tester.tap(find.widgetWithText(ChoiceChip, '4'));
    await tester.pumpAndSettle();
    expect(find.text('You vs 4 computer opponents • Offline'), findsOneWidget);
    final help = find.byTooltip('How to play');
    await tester.ensureVisible(help);
    await tester.tap(help);
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 150)),
    );
    await tester.pumpAndSettle();
    expect(find.byType(HelpScreen), findsOneWidget);
    await tester.pageBack();
    await tester.pumpAndSettle();
    final start = find.text('START VS COMPUTER');
    await tester.ensureVisible(start);
    await tester.tap(start);
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 200)),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    final screen = tester.widget<GameScreen>(find.byType(GameScreen));
    expect(screen.controller.session.players.length, 5);
    expect(screen.controller.session.computerPlayerIds, {
      'p2',
      'p3',
      'p4',
      'p5',
    });
    expect(screen.controller.localPlayerId, 'p1');
    expect(find.text('PASS THE DEVICE'), findsNothing);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
