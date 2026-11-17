import 'package:flame/game.dart' show GameWidget;
import 'package:flame/components.dart' show Vector2;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:spiral_pass_play/app/platform/game_screen_awake.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';
import 'package:spiral_pass_play/features/game/application/game_controller.dart';
import 'package:spiral_pass_play/features/game/data/board_repository.dart';
import 'package:spiral_pass_play/features/game/domain/game_session.dart';
import 'package:spiral_pass_play/features/game/flame/spiral_board_game.dart';
import 'package:spiral_pass_play/features/game/presentation/game_screen.dart';
import 'package:spiral_pass_play/features/game/presentation/turn_result_visual.dart';

void main() {
  for (final online in [false, true]) {
    testWidgets('Portrait controls and rotation work (online: $online)', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(320, 640);
      tester.view.devicePixelRatio = 1;
      tester.platformDispatcher.textScaleFactorTestValue = 1.25;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      SharedPreferencesAsyncPlatform.instance =
          InMemorySharedPreferencesAsync.empty();
      final awakeCalls = <bool>[];
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        GameScreenAwake.channel,
        (call) async {
          awakeCalls.add(call.arguments as bool);
          return null;
        },
      );
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          GameScreenAwake.channel,
          null,
        ),
      );
      final orientationCalls = <MethodCall>[];
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (call) async {
          if (call.method == 'SystemChrome.setPreferredOrientations') {
            orientationCalls.add(call);
          }
          return null;
        },
      );
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.platform,
          null,
        ),
      );
      final board = (await tester.runAsync(
        () => const BoardRepository().loadReferenceBoard(),
      ))!;
      final controller = GameController.newGame(
        names: ['A player with a long name', 'Two'],
        colors: [0xFFFF0000, 0xFF00FF00],
        board: board,
      );
      controller.session.currentPlayer.reverseNextMove = true;
      await tester.runAsync(() async {
        await tester.pumpWidget(
          MaterialApp(
            home: GameScreen(
              controller: controller,
              online: online,
              onlineStatus: () => 'Connected · Waiting for another player',
            ),
          ),
        );
        await Future<void>.delayed(const Duration(milliseconds: 100));
      });
      await tester.pump();
      for (final size in [
        const Size(320, 640),
        const Size(800, 360),
        const Size(390, 844),
      ]) {
        tester.view.physicalSize = size;
        await tester.pump();
        await tester.pump();
        for (final tooltip in [
          'Focus current player',
          'Character abilities',
          'Players and inventory',
          'Exit game',
          'Zoom in',
          'Zoom out',
          'Fit board to width',
        ]) {
          expect(find.byTooltip(tooltip).hitTestable(), findsOneWidget);
        }
        expect(find.text('ROLL BACKWARDS').hitTestable(), findsOneWidget);
        expect(tester.takeException(), isNull);
        expect(controller.session.currentPlayer.reverseNextMove, isTrue);
      }
      expect(orientationCalls, isEmpty);
      await tester.tap(find.byTooltip('Zoom in'));
      await tester.pump();
      await tester.tap(find.byTooltip('Fit board to width'));
      await tester.pump();
      await tester.tap(find.byTooltip('Players and inventory'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.text('PLAYERS & INVENTORY'), findsOneWidget);
      expect(tester.takeException(), isNull);
      expect(awakeCalls, [true]);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
      expect(awakeCalls, [true, false]);
      controller.dispose();
    });
  }

  for (final payFine in [true, false]) {
    testWidgets(
      'Police dialog offers the ${payFine ? 'payment' : 'missed turn'} choice after resume',
      (tester) async {
        tester.view.physicalSize = const Size(1200, 800);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        SharedPreferencesAsyncPlatform.instance =
            InMemorySharedPreferencesAsync.empty();
        final board = (await tester.runAsync(
          () => const BoardRepository().loadReferenceBoard(),
        ))!;
        final original = GameController.newGame(
          names: ['One', 'Two'],
          colors: [1, 2],
          board: board,
          diceRoller: () => 1,
        );
        original.session.players.first.position = 15;
        original.session.players.first.cash = payFine ? 100 : 5;
        original.roll();
        original.finishAnimation();
        final controller = GameController(
          session: GameSession.fromJson(original.session.toJson()),
          board: board,
        );
        original.dispose();
        await tester.runAsync(() async {
          await tester.pumpWidget(
            MaterialApp(home: GameScreen(controller: controller)),
          );
          await Future<void>.delayed(const Duration(milliseconds: 100));
        });
        await tester.pump();
        expect(find.text('POLICE · CHOOSE YOUR PENALTY'), findsOneWidget);
        expect(controller.session.currentPlayer.position, 16);
        expect(find.text('JAIL'), findsNothing);
        expect(find.text('POLICE STOP'), findsOneWidget);
        final pay = find.widgetWithText(FilledButton, r'BRIBE $20');
        expect(tester.widget<FilledButton>(pay).onPressed != null, payFine);
        expect(find.text('GO TO JAIL'), findsOneWidget);
        await tester.tap(payFine ? pay : find.text('GO TO JAIL'));
        await tester.pump();
        if (!payFine) {
          for (var i = 0; i < 30; i++) {
            await tester.pump(const Duration(milliseconds: 100));
          }
        }
        expect(controller.session.phase, TurnPhase.specialReview);
        expect(controller.session.currentPlayer.position, payFine ? 16 : 13);
        expect(controller.session.players.first.cash, payFine ? 80 : 5);
        expect(controller.session.players.first.skipTurns, payFine ? 0 : 1);
        expect(find.text(payFine ? 'STAY HERE' : 'JAIL'), findsOneWidget);
        await tester.tap(find.text('CONTINUE'));
        await tester.pump();
        expect(find.text('PASS THE DEVICE'), findsOneWidget);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
        controller.dispose();
      },
    );
  }

  testWidgets(
    'Width-fit board scrolls and focuses on the active player before and after movement',
    (tester) async {
      tester.view.physicalSize = const Size(600, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      SharedPreferencesAsyncPlatform.instance =
          InMemorySharedPreferencesAsync.empty();
      final board = (await tester.runAsync(
        () => const BoardRepository().loadReferenceBoard(),
      ))!;
      final controller = GameController.newGame(
        names: ['One', 'Two'],
        colors: [0xFFFF0000, 0xFF00FF00],
        board: board,
        diceRoller: () => 2,
      );
      controller.session.players[1].position = 26;
      await tester.runAsync(() async {
        await tester.pumpWidget(
          MaterialApp(home: GameScreen(controller: controller)),
        );
        await Future<void>.delayed(const Duration(milliseconds: 500));
      });
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
      final token = game.world.children.whereType<PlayerToken>().first;
      final start = token.position.clone();
      tester.view.physicalSize = const Size(1200, 800);
      await tester.pump();
      await tester.pump();
      expect(
        tester.getSize(
          find.byWidgetPredicate(
            (widget) => widget is GameWidget<SpiralBoardGame>,
          ),
        ),
        const Size(1200, 800),
      );
      final overviewZoom = game.camera.viewfinder.zoom;
      expect(overviewZoom, closeTo(1.2, .001));
      final focusedY = game.camera.viewfinder.position.y;
      await tester.tap(find.byTooltip('Zoom in'));
      await tester.pump();
      expect(game.camera.viewfinder.zoom, greaterThan(overviewZoom));
      final chosenZoom = game.camera.viewfinder.zoom;
      await tester.tap(find.byTooltip('Focus current player'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 450));
      expect(game.camera.viewfinder.zoom, closeTo(chosenZoom, .001));
      await tester.tap(find.byTooltip('Zoom out'));
      await tester.pump();
      expect(game.camera.viewfinder.zoom, closeTo(overviewZoom, .001));
      game.zoomBoard(100);
      expect(game.camera.viewfinder.zoom, closeTo(overviewZoom * 4, .001));
      game.zoomBoard(.0001);
      expect(game.camera.viewfinder.zoom, closeTo(.8, .001));
      game.fitBoardWidth();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 450));
      final firstFinger = await tester.createGesture(pointer: 1);
      final secondFinger = await tester.createGesture(pointer: 2);
      await firstFinger.down(const Offset(550, 400));
      await secondFinger.down(const Offset(650, 400));
      await tester.pump();
      await firstFinger.moveTo(const Offset(500, 400));
      await secondFinger.moveTo(const Offset(700, 400));
      await tester.pump();
      await firstFinger.up();
      await secondFinger.up();
      expect(game.camera.viewfinder.zoom, greaterThan(overviewZoom));
      await tester.tap(find.byTooltip('Fit board to width'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 450));
      expect(game.camera.viewfinder.zoom, closeTo(overviewZoom, .001));
      await tester.dragFrom(const Offset(600, 400), const Offset(0, -220));
      await tester.pump();
      expect(game.camera.viewfinder.position.y, greaterThan(focusedY));
      await tester.tap(find.byTooltip('Focus current player'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 450));
      expect(game.camera.viewfinder.position.y, closeTo(focusedY, .001));
      await tester.tap(find.text('ROLL DICE'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 1100));
      expect(controller.session.phase, TurnPhase.rolling);
      expect(controller.session.players.first.position, 0);
      await tester.pump(const Duration(milliseconds: 450));
      expect(find.text('YOU ROLLED'), findsOneWidget);
      expect(find.text('2'), findsOneWidget);
      expect(controller.session.phase, TurnPhase.rolling);
      expect(controller.session.players.first.position, 0);
      await tester.pump(const Duration(milliseconds: 650));
      for (var i = 0; i < 4; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      expect(game.camera.viewfinder.zoom, greaterThan(overviewZoom * 2));
      expect(
        game.camera.viewfinder.position.distanceTo(start),
        lessThan(game.camera.viewfinder.position.distanceTo(Vector2.all(500))),
      );
      for (var i = 0; i < 40; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      expect(token.position.distanceTo(start), greaterThan(1));
      expect(controller.session.phase, TurnPhase.specialReview);
      expect(find.text('SPECIAL TILE'), findsNothing);
      expect(game.paused, isTrue);
      expect(find.text('Collected 1 boat(s).'), findsOneWidget);
      expect(find.byType(TurnResultVisual), findsOneWidget);
      expect(find.text('Boats: +1 (0 → 1)'), findsNothing);
      expect(find.text('Boats: 0 + 1'), findsOneWidget);
      expect(find.text('Landed on tile 2'), findsNothing);
      expect(find.text('Now at tile 2'), findsNothing);
      expect(controller.beginDiceRoll(), isNull);
      await tester.tap(find.text('CONTINUE'));
      await tester.pump();
      expect(controller.session.phase, TurnPhase.handoff);
      expect(game.paused, isTrue);
      expect(game.camera.viewfinder.zoom, closeTo(overviewZoom, .001));
      expect(game.camera.viewfinder.position.x, closeTo(500, .001));
      expect(game.camera.viewfinder.position.y, closeTo(focusedY, .001));
      await tester.tap(find.text("I'M READY — SHOW BOARD"));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 450));
      expect(game.camera.viewfinder.position.y, greaterThan(500));
      await tester.tap(find.byTooltip('Players and inventory'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.text('PLAYERS & INVENTORY'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      controller.dispose();
    },
  );
}
