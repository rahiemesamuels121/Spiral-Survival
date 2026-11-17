import 'package:flame/game.dart' show GameWidget;
import 'package:flutter/material.dart';
import 'package:spiral_pass_play/app/platform/game_screen_awake.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';
import 'package:spiral_pass_play/features/game/application/game_controller.dart';
import 'package:spiral_pass_play/features/game/domain/board_definition.dart';
import 'package:spiral_pass_play/features/game/domain/game_session.dart';
import 'package:spiral_pass_play/features/game/flame/spiral_board_game.dart';
import 'package:spiral_pass_play/features/game/presentation/game_screen.dart';
import 'package:spiral_pass_play/features/help/help_screen.dart';

void main() {
  testWidgets(
    'Resumed computer turn animates automatically and returns control to the human',
    (tester) async {
      final awake = <bool>[];
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        GameScreenAwake.channel,
        (call) async {
          expect(call.method, 'setKeepScreenOn');
          awake.add(call.arguments as bool);
          return null;
        },
      );
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          GameScreenAwake.channel,
          null,
        ),
      );
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      SharedPreferencesAsyncPlatform.instance =
          InMemorySharedPreferencesAsync.empty();
      final board = BoardDefinition([
        for (var i = 0; i < 30; i++)
          BoardTile(
            index: i,
            x: .1 + (i % 5) * .15,
            y: .1 + (i ~/ 5) * .15,
            type: i == 0
                ? TileType.start
                : i == 29
                ? TileType.finish
                : TileType.normal,
          ),
      ]);
      final original = GameController.newGame(
        names: ['You', 'Computer'],
        colors: [1, 2],
        board: board,
        computerPlayerIds: {'p2'},
      );
      original.session.currentPlayerIndex = 1;
      final controller = GameController(
        session: GameSession.fromJson(original.session.toJson()),
        board: board,
        diceRoller: () => 1,
      );
      original.dispose();
      await tester.pumpWidget(
        MaterialApp(home: GameScreen(controller: controller)),
      );
      await tester.pump();
      final game =
          tester
                  .widget<GameWidget<SpiralBoardGame>>(
                    find.byWidgetPredicate(
                      (widget) => widget is GameWidget<SpiralBoardGame>,
                    ),
                  )
                  .game
              as SpiralBoardGame;
      await tester.runAsync(() async => game.toBeLoaded());
      await tester.pump();
      expect(find.text('Computer is taking its turn…'), findsOneWidget);
      expect(
        tester
            .widget<FilledButton>(
              find.widgetWithText(FilledButton, 'COMPUTER TURN'),
            )
            .onPressed,
        isNull,
      );
      await tester.pump(const Duration(milliseconds: 800));
      expect(controller.session.phase, TurnPhase.rolling);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 1550));
      expect(find.text('YOU ROLLED'), findsOneWidget);
      await tester.pump(const Duration(milliseconds: 650));
      for (var i = 0; i < 40; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      expect(controller.session.players[1].position, 1);
      expect(controller.session.currentPlayerIndex, 0);
      expect(controller.session.phase, TurnPhase.ready);
      expect(find.text('PASS THE DEVICE'), findsNothing);
      expect(
        tester
            .widget<FilledButton>(
              find.widgetWithText(FilledButton, 'ROLL DICE'),
            )
            .onPressed,
        isNotNull,
      );
      await tester.tap(find.byTooltip('Players and inventory'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      await tester.tap(find.text('HOW TO PLAY & TILE GUIDE'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.byType(HelpScreen), findsOneWidget);
      expect(game.paused, isTrue);
      expect(awake, [true]); // In-game Help still belongs to the open match.
      await tester.pageBack();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(game.paused, isTrue); // A still board no longer burns frames.
      final zoom = game.camera.viewfinder.zoom;
      game.zoomBoard(1.2);
      expect(game.paused, isFalse);
      await tester.pump();
      await tester.pump();
      expect(game.camera.viewfinder.zoom, greaterThan(zoom));
      expect(game.paused, isTrue);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
      expect(awake, [true, false]);
      controller.dispose();
    },
  );
}
