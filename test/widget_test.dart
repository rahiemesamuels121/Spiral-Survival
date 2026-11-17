import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';
import 'package:spiral_pass_play/main.dart';
import 'package:spiral_pass_play/features/multiplayer/presentation/online_room_screen.dart';
import 'package:spiral_pass_play/features/game/data/session_store.dart';
import 'package:spiral_pass_play/features/game/data/board_repository.dart';
import 'package:spiral_pass_play/features/game/application/game_controller.dart';
import 'package:spiral_pass_play/features/game/presentation/game_screen.dart';
import 'package:spiral_pass_play/features/game/domain/player_icon.dart';

void main() {
  setUp(() => rootBundle.evict(BoardRepository.assetPath));
  testWidgets('Main menu separates mode selection from player setup', (
    tester,
  ) async {
    SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.empty();
    await tester.pumpWidget(const SpiralApp());
    await tester.pumpAndSettle();

    expect(find.text('SPIRAL SURVIVAL'), findsOneWidget);
    expect(find.byType(TextFormField), findsNothing);
    expect(find.byType(ChoiceChip), findsNothing);
    expect(find.text('VS COMPUTER'), findsOneWidget);
    expect(find.text('ONLINE'), findsOneWidget);
    await tester.tap(find.text('PASS & PLAY'));
    await tester.pumpAndSettle();
    expect(find.byType(TextFormField), findsNWidgets(3));
    expect(find.text('START GAME'), findsOneWidget);
    expect(find.text('BOARD STUDIO'), findsNothing);

    await tester.tap(find.widgetWithText(ChoiceChip, '2'));
    await tester.pumpAndSettle();

    expect(find.byType(TextFormField), findsNWidgets(2));
    expect(tester.takeException(), isNull);
  });
  testWidgets(
    'Main menu opens Online and its character selection before the room starts',
    (tester) async {
      SharedPreferencesAsyncPlatform.instance =
          InMemorySharedPreferencesAsync.empty();
      await tester.pumpWidget(const SpiralApp());
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('ONLINE'));
      await tester.tap(find.text('ONLINE'));
      await tester.pumpAndSettle();
      expect(find.byType(OnlineRoomScreen), findsOneWidget);
      expect(
        find.text('CHOOSE CHARACTER · Locks when the host starts'),
        findsOneWidget,
      );
      expect(find.text('Number of players'), findsNothing);
      await tester.tap(find.byIcon(Icons.arrow_back));
      await tester.pumpAndSettle();
      expect(find.text('PASS & PLAY'), findsOneWidget);
    },
  );

  testWidgets(
    'Continue saved game remains on the main menu after splitting setup',
    (tester) async {
      SharedPreferencesAsyncPlatform.instance =
          InMemorySharedPreferencesAsync.empty();
      final board = (await tester.runAsync(
        () => const BoardRepository().loadReferenceBoard(),
      ))!;
      final initial = GameController.newGame(
        names: ['You', 'Computer'],
        colors: [1, 2],
        board: board,
        computerPlayerIds: {'p2'},
        icons: [PlayerIcon.secretAgent, PlayerIcon.swimmer],
      );
      await tester.runAsync(() => SessionStore().save(initial.session));
      initial.dispose();
      await tester.pumpWidget(const SpiralApp());
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('CONTINUE SAVED GAME'));
      await tester.tap(find.text('CONTINUE SAVED GAME'));
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 150)),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      final screen = tester.widget<GameScreen>(find.byType(GameScreen));
      expect(screen.controller.session.computerPlayerIds, {'p2'});
      expect(
        screen.controller.session.players.first.icon,
        PlayerIcon.secretAgent,
      );
      expect(find.text('Number of computer opponents'), findsNothing);
      await tester.pumpWidget(const SizedBox.shrink());
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
      expect(find.text('PASS & PLAY'), findsOneWidget);
      expect(find.byType(TextFormField), findsNothing);
      await tester.ensureVisible(find.text('PASS & PLAY'));
      await tester.tap(find.text('PASS & PLAY'));
      await tester.pumpAndSettle();
      expect(find.text('START GAME'), findsOneWidget);
      expect(find.byType(TextFormField), findsNWidgets(3));
      expect(tester.takeException(), isNull);
    });
  }
}
