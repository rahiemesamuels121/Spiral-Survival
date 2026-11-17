import 'package:flame/game.dart' show GameWidget;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';
import 'package:spiral_pass_play/app/theme.dart';
import 'package:spiral_pass_play/features/game/application/game_controller.dart';
import 'package:spiral_pass_play/features/game/data/session_store.dart';
import 'package:spiral_pass_play/features/game/domain/board_definition.dart';
import 'package:spiral_pass_play/features/game/domain/game_session.dart';
import 'package:spiral_pass_play/features/game/flame/spiral_board_game.dart';
import 'package:spiral_pass_play/features/game/presentation/game_screen.dart';

BoardDefinition _board({int? hospital, int? fire}) => BoardDefinition([
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
          : i == hospital
          ? TileType.hospital
          : i == fire
          ? TileType.fire
          : TileType.normal,
      destination: i == fire ? hospital : null,
    ),
]);
Future<void> _showGame(
  WidgetTester tester,
  GameController game, {
  Size size = const Size(1200, 900),
  double textScale = 1,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  SharedPreferencesAsyncPlatform.instance =
      InMemorySharedPreferencesAsync.empty();
  await tester.runAsync(() async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: TextScaler.linear(textScale)),
          child: child!,
        ),
        home: GameScreen(controller: game),
      ),
    );
    await Future<void>.delayed(const Duration(milliseconds: 100));
  });
  await tester.pump();
}

void main() {
  for (final beforeMoving in [true, false]) {
    for (final textScale in [1.0, 1.3]) {
      testWidgets(
        '${beforeMoving ? 'Same-tile' : 'Ranged'} Stabber is visible and usable on a phone at text scale $textScale',
        (tester) async {
          final game = GameController.newGame(
            names: ['One', 'Two', 'Three', 'Four', 'Five'],
            colors: [1, 2, 3, 4, 5],
            board: _board(),
            diceRoller: () => beforeMoving ? 4 : 6,
          );
          game.session.players.first.position = beforeMoving ? 20 : 16;
          game.session.players.first.inventory.stabbers = 1;
          game.session.players.first.inventory.pewPews = 1;
          for (var i = 1; i < game.session.players.length; i++) {
            game.session.players[i].position = beforeMoving ? 20 : 16 + i;
          }
          game.roll();
          if (!beforeMoving) game.finishAnimation();
          await _showGame(
            tester,
            game,
            size: const Size(640, 360),
            textScale: textScale,
          );
          final target = find.text(
            'Use Stabber on Two (${beforeMoving ? 0 : 1} spaces)',
          );
          expect(target.hitTestable(), findsOneWidget);
          final button = tester.widget<OutlinedButton>(
            find.ancestor(of: target, matching: find.byType(OutlinedButton)),
          );
          expect(button.onPressed, isNotNull);
          expect(button.style!.foregroundColor?.resolve({}), AppTheme.ink);
          final lastPewTarget = find.text(
            'Use Pew pew on Five (${beforeMoving ? 0 : 4} spaces)',
          );
          await tester.ensureVisible(lastPewTarget);
          expect(lastPewTarget.hitTestable(), findsOneWidget);
          final alternateAction = find.text(
            beforeMoving ? 'MOVE 4 SPACES' : 'MOVE 6 SPACES',
          );
          await tester.ensureVisible(alternateAction);
          expect(alternateAction.hitTestable(), findsOneWidget);
          await tester.ensureVisible(target);
          await tester.tap(target);
          await tester.pump();
          for (var i = 0; i < 25; i++) {
            await tester.pump(const Duration(milliseconds: 100));
          }
          expect(game.session.players.first.inventory.stabbers, 0);
          expect(game.session.players.first.inventory.pewPews, 1);
          expect(game.session.players[1].position, 0);
          expect(game.session.players.first.inventory.stars, 3);
          expect(game.session.players.first.cash, 10);
          expect(game.session.phase, TurnPhase.specialReview);
          expect(find.text('Stars: 0 + 3'), findsOneWidget);
          expect(tester.takeException(), isNull);
          await tester.pumpWidget(const SizedBox.shrink());
          game.dispose();
        },
      );
    }
  }

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
    'Both shop products are visible on a landscape phone with the dark theme',
    (tester) async {
      final game = GameController.newGame(
        names: ['One', 'Two'],
        colors: [1, 2],
        board: _board(),
        diceRoller: () => 1,
      );
      game.session.currentPlayer.position = 9;
      game.roll();
      game.finishAnimation();
      await _showGame(tester, game, size: const Size(640, 360));
      for (final label in [r'BUY STABBER · $40', r'BUY PEW PEW · $95']) {
        expect(find.text(label).hitTestable(), findsOneWidget);
        final button = tester.widget<OutlinedButton>(
          find.widgetWithText(OutlinedButton, label),
        );
        expect(button.onPressed, isNull);
        expect(
          button.style!.foregroundColor?.resolve({WidgetState.disabled}),
          isNot(AppTheme.ivory),
        );
      }
      await tester.ensureVisible(find.text('DONE SHOPPING'));
      await tester.tap(find.text('DONE SHOPPING'));
      await tester.pump();
      expect(game.session.phase, TurnPhase.specialReview);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      game.dispose();
    },
  );

  testWidgets(
    'Hospital sells health packs and antidotes without charging a healthy visitor',
    (tester) async {
      final game = GameController.newGame(
        names: ['One', 'Two'],
        colors: [1, 2],
        board: _board(hospital: 20),
        diceRoller: () => 1,
      );
      game.session.currentPlayer.position = 19;
      game.session.currentPlayer.cash = 25;
      game.roll();
      game.finishAnimation();
      await _showGame(tester, game, size: const Size(640, 360), textScale: 1.3);
      expect(find.text('HOSPITAL SHOP'), findsOneWidget);
      expect(
        find.textContaining('You are healthy; no treatment fee.'),
        findsOneWidget,
      );
      expect(find.text(r'BUY STABBER · $40'), findsNothing);
      expect(game.session.currentPlayer.cash, 25);
      await tester.ensureVisible(find.text(r'BUY HEALTH PACK · $10'));
      await tester.tap(find.text(r'BUY HEALTH PACK · $10'));
      await tester.pump();
      expect(game.session.currentPlayer.inventory.healthPacks, 1);
      expect(game.session.currentPlayer.cash, 15);
      expect(
        find.byKey(const ValueKey('medical-purchase-confirmation')),
        findsOneWidget,
      );
      await tester.ensureVisible(find.text(r'BUY ANTIDOTE · $5'));
      await tester.tap(find.text(r'BUY ANTIDOTE · $5'));
      await tester.pump();
      expect(game.session.currentPlayer.inventory.antidotes, 1);
      expect(game.session.currentPlayer.cash, 10);
      expect(find.text('Owned 1'), findsNWidgets(2));
      final saved = await tester.runAsync(() async {
        await Future<void>.delayed(Duration.zero);
        return SessionStore().load();
      });
      expect(saved!.currentPlayer.inventory.healthPacks, 1);
      expect(saved.currentPlayer.inventory.antidotes, 1);
      expect(saved.currentPlayer.isInjured, isFalse);
      await tester.ensureVisible(find.text('DONE SHOPPING'));
      await tester.tap(find.text('DONE SHOPPING'));
      await tester.pump();
      expect(find.text('Health pack: 0 + 1'), findsOneWidget);
      expect(find.text('Antidote: 0 + 1'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      game.dispose();
    },
  );

  testWidgets(
    'A carried health pack prevents fire from sending a player to hospital',
    (tester) async {
      final game = GameController.newGame(
        names: ['One', 'Two'],
        colors: [1, 2],
        board: _board(hospital: 20, fire: 22),
        diceRoller: () => 1,
      );
      game.session.currentPlayer.position = 21;
      game.session.currentPlayer.inventory.healthPacks = 1;
      game.session.currentPlayer.cash = 0;
      game.roll();
      game.finishAnimation();
      await _showGame(tester, game, size: const Size(640, 360));
      expect(game.session.phase, TurnPhase.specialReview);
      expect(game.session.currentPlayer.position, 22);
      expect(game.session.currentPlayer.isInjured, isFalse);
      expect(game.session.currentPlayer.inventory.healthPacks, 0);
      expect(game.session.currentPlayer.cash, 0);
      expect(find.text('INJURY TREATMENT'), findsNothing);
      expect(find.text('HOSPITAL SHOP'), findsNothing);
      expect(find.textContaining('health pack'), findsWidgets);
      expect(find.text('CONTINUE'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      game.dispose();
    },
  );

  testWidgets(
    'Injured players can use a health pack and then visit the hospital shop',
    (tester) async {
      final game = GameController.newGame(
        names: ['One', 'Two'],
        colors: [1, 2],
        board: _board(hospital: 20),
        diceRoller: () => 1,
      );
      game.session.currentPlayer.position = 19;
      game.session.currentPlayer.isInjured = true;
      game.session.currentPlayer.inventory.healthPacks = 1;
      game.session.currentPlayer.cash = 0;
      game.roll();
      game.finishAnimation();
      await _showGame(tester, game, size: const Size(640, 360));
      expect(find.text('INJURY TREATMENT'), findsOneWidget);
      expect(find.text('USE HEALTH PACK'), findsOneWidget);
      await tester.ensureVisible(find.text('USE HEALTH PACK'));
      await tester.tap(find.text('USE HEALTH PACK'));
      await tester.pump();
      expect(find.text('HOSPITAL SHOP'), findsOneWidget);
      expect(game.session.currentPlayer.isInjured, isFalse);
      expect(game.session.currentPlayer.inventory.healthPacks, 0);
      expect(game.session.currentPlayer.cash, 0);
      for (final label in [r'BUY HEALTH PACK · $10', r'BUY ANTIDOTE · $5']) {
        expect(
          tester
              .widget<OutlinedButton>(
                find.widgetWithText(OutlinedButton, label),
              )
              .onPressed,
          isNull,
        );
      }
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
      original.session.players.first.position = 16;
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
      expect(game.session.players.first.inventory.stars, 3);
      expect(game.session.players.first.cash, 10);
      expect(targetToken.position.distanceTo(before), greaterThan(1));
      expect(game.session.phase, TurnPhase.specialReview);
      expect(find.text('Stars: 0 + 3'), findsOneWidget);
      expect(find.textContaining('no cash'), findsWidgets);
      await tester.tap(find.text('CONTINUE'));
      await tester.pump();
      expect(game.session.phase, TurnPhase.handoff);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      game.dispose();
    },
  );
}
