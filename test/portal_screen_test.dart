import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';
import 'package:spiral_pass_play/features/game/application/game_controller.dart';
import 'package:spiral_pass_play/features/game/data/session_store.dart';
import 'package:spiral_pass_play/features/game/domain/board_definition.dart';
import 'package:spiral_pass_play/features/game/domain/game_session.dart';
import 'package:spiral_pass_play/features/game/presentation/game_screen.dart';

void main() {
  for (final cardIndex in [0, 1]) {
    testWidgets(
      'Mystery card $cardIndex stays hidden until tapped and then animates travel',
      (tester) async {
        tester.view.physicalSize = const Size(850, 400);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        SharedPreferencesAsyncPlatform.instance =
            InMemorySharedPreferencesAsync.empty();
        final board = BoardDefinition([
          for (var i = 0; i <= 12; i++)
            BoardTile(
              index: i,
              x: (i + .5) / 13,
              y: .5,
              type: i == 0
                  ? TileType.start
                  : i == 12
                  ? TileType.finish
                  : [2, 6, 10].contains(i)
                  ? TileType.portal
                  : TileType.normal,
            ),
        ]);
        final original = GameController.newGame(
          names: ['One', 'Two'],
          colors: [1, 2],
          board: board,
          diceRoller: () => 1,
        );
        original.session.currentPlayer.position = 5;
        original.roll();
        original.finishAnimation();
        final order = original.session.portalCardDirections.toList();
        final game = GameController(
          session: GameSession.fromJson(original.session.toJson()),
          board: board,
        );
        original.dispose();
        await tester.runAsync(() async {
          await tester.pumpWidget(
            MaterialApp(home: GameScreen(controller: game)),
          );
          await Future<void>.delayed(const Duration(milliseconds: 100));
        });
        await tester.pump();
        expect(find.text('MYSTERY PORTAL'), findsOneWidget);
        expect(find.byKey(const ValueKey('portal-card-0')), findsOneWidget);
        expect(find.byKey(const ValueKey('portal-card-1')), findsOneWidget);
        expect(find.text('BACKWARDS'), findsNothing);
        expect(find.text('FORWARDS'), findsNothing);
        final saved = await tester.runAsync(() => SessionStore().load());
        expect(saved!.phase, TurnPhase.portalChoice);
        expect(saved.portalCardDirections, order);
        await tester.tap(find.byKey(ValueKey('portal-card-$cardIndex')));
        await tester.pump();
        expect(
          game.session.currentPlayer.position,
          order[cardIndex] < 0 ? 2 : 10,
        );
        final committed = await tester.runAsync(() async {
          await Future<void>.delayed(Duration.zero);
          return SessionStore().load();
        });
        expect(committed!.phase, TurnPhase.specialReview);
        expect(committed.currentPlayer.position, order[cardIndex] < 0 ? 2 : 10);
        for (var i = 0; i < 30; i++) {
          await tester.pump(const Duration(milliseconds: 100));
        }
        expect(game.session.phase, TurnPhase.specialReview);
        expect(game.session.pendingPortalTile, isNull);
        expect(find.text('MYSTERY PORTAL'), findsNothing);
        await tester.ensureVisible(find.text('CONTINUE'));
        await tester.tap(find.text('CONTINUE'));
        await tester.pump();
        expect(game.session.phase, TurnPhase.handoff);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
        game.dispose();
      },
    );
  }
}
