import 'package:flame/game.dart' show GameWidget;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';
import 'package:spiral_pass_play/features/game/application/game_controller.dart';
import 'package:spiral_pass_play/features/game/data/session_store.dart';
import 'package:spiral_pass_play/features/game/domain/board_definition.dart';
import 'package:spiral_pass_play/features/game/domain/game_session.dart';
import 'package:spiral_pass_play/features/game/flame/spiral_board_game.dart';
import 'package:spiral_pass_play/features/game/presentation/game_screen.dart';

BoardDefinition _board() => BoardDefinition([
  for (var i = 0; i < 50; i++)
    BoardTile(
      index: i,
      x: (i % 10 + .5) / 10,
      y: (i ~/ 10 + .5) / 5,
      type: i == 0
          ? TileType.start
          : i == 49
          ? TileType.finish
          : i == 10
          ? TileType.shop
          : TileType.normal,
    ),
]);
Future<void> _showGame(WidgetTester tester, GameController game) async {
  tester.view.physicalSize = const Size(1200, 900);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  SharedPreferencesAsyncPlatform.instance =
      InMemorySharedPreferencesAsync.empty();
  await tester.runAsync(() async {
    await tester.pumpWidget(MaterialApp(home: GameScreen(controller: game)));
    await Future<void>.delayed(const Duration(milliseconds: 100));
  });
  await tester.pump();
}

void main() {
  testWidgets('Same-tile choice offers movement or one target before moving', (
    tester,
  ) async {
    final game = GameController.newGame(
      names: ['One', 'Two'],
      colors: [1, 2],
      board: _board(),
      diceRoller: () => 4,
    );
    game.session.players.first.position = 20;
    game.session.players[1].position = 20;
    game.session.players.first.inventory.stabbers = 1;
    game.roll();
    await _showGame(tester, game);
    expect(find.text('MOVE OR ATTACK'), findsOneWidget);
    expect(find.text('MOVE 4 SPACES'), findsOneWidget);
    expect(find.text('Use Stabber on Two (0 spaces)'), findsOneWidget);
    expect(game.session.players.first.position, 20);
    await tester.tap(find.text('MOVE 4 SPACES'));
    await tester.pump();
    expect(game.session.players.first.position, 24);
    expect(game.session.players[1].position, 20);
    expect(game.session.players.first.inventory.stabbers, 1);
    await tester.pumpWidget(const SizedBox.shrink());
    game.dispose();
  });

  testWidgets(
    'Shop shows real prices, updates inventory, and disables unaffordable purchases',
    (tester) async {
      final board = _board();
      final original = GameController.newGame(
        names: ['One', 'Two'],
        colors: [1, 2],
        board: board,
        diceRoller: () => 1,
      );
      original.session.players.first.position = 9;
      original.session.players.first.cash = 100;
      original.roll();
      original.finishAnimation();
      final game = GameController(
        session: GameSession.fromJson(original.session.toJson()),
        board: board,
      );
      original.dispose();
      await _showGame(tester, game);
      expect(find.text('WEAPON SHOP'), findsOneWidget);
      expect(find.text(r'BUY STABBER · $40'), findsOneWidget);
      expect(find.text(r'BUY PEW PEW · $95'), findsOneWidget);
      await tester.tap(find.text(r'BUY STABBER · $40'));
      await tester.pump();
      expect(game.session.players.first.cash, 60);
      final saved = await tester.runAsync(() async {
        await Future<void>.delayed(Duration.zero);
        return SessionStore().load();
      });
      expect(saved!.phase, TurnPhase.shopping);
      expect(saved.players.first.cash, 60);
      expect(saved.players.first.inventory.stabbers, 1);
      expect(find.text('Range 5 · Owned 1'), findsOneWidget);
      expect(
        tester
            .widget<OutlinedButton>(
              find.widgetWithText(OutlinedButton, r'BUY PEW PEW · $95'),
            )
            .onPressed,
        isNull,
      );
      await tester.tap(find.text('DONE SHOPPING'));
      await tester.pump();
      expect(game.session.phase, TurnPhase.specialReview);
      await tester.tap(find.text('CONTINUE'));
      await tester.pump();
      expect(game.session.phase, TurnPhase.handoff);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      game.dispose();
    },
  );

  testWidgets(
    'Weapon target selection animates the target to START and consumes one weapon',
    (tester) async {
      final board = _board();
      final original = GameController.newGame(
        names: ['One', 'Two', 'Three'],
        colors: [1, 2, 3],
        board: board,
        diceRoller: () => 6,
      );
      original.session.players.first.position = 10;
      original.session.players.first.inventory.stabbers = 1;
      original.session.players.first.inventory.pewPews = 1;
      original.session.players[1].position = 21;
      original.session.players[2].position = 25;
      original.roll();
      original.finishAnimation();
      final game = GameController(
        session: GameSession.fromJson(original.session.toJson()),
        board: board,
      );
      original.dispose();
      await _showGame(tester, game);
      expect(find.text('YOU ROLLED A 6'), findsOneWidget);
      expect(find.text('Use Stabber on Two (5 spaces)'), findsOneWidget);
      expect(find.text('Use Pew pew on Three (9 spaces)'), findsOneWidget);
      final flame = tester
          .widget<GameWidget<SpiralBoardGame>>(
            find.byWidgetPredicate(
              (widget) => widget is GameWidget<SpiralBoardGame>,
            ),
          )
          .game!;
      final targetToken = flame.world.children
          .whereType<PlayerToken>()
          .toList()[1];
      final before = targetToken.position.clone();
      await tester.tap(find.text('Use Stabber on Two (5 spaces)'));
      await tester.pump();
      for (var i = 0; i < 20; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      expect(game.session.players[1].position, 0);
      expect(game.session.players[2].position, 25);
      expect(game.session.players.first.inventory.stabbers, 0);
      expect(game.session.players.first.inventory.pewPews, 1);
      expect(targetToken.position.distanceTo(before), greaterThan(1));
      expect(game.session.phase, TurnPhase.specialReview);
      await tester.tap(find.text('CONTINUE'));
      await tester.pump();
      expect(game.session.phase, TurnPhase.handoff);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      game.dispose();
    },
  );
}
