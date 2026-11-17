import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:spiral_pass_play/features/game/application/computer_opponent.dart';
import 'package:spiral_pass_play/features/game/application/game_controller.dart';
import 'package:spiral_pass_play/features/game/domain/board_definition.dart';
import 'package:spiral_pass_play/features/game/domain/game_session.dart';

BoardDefinition _board() => BoardDefinition([
  for (var i = 0; i < 60; i++)
    BoardTile(
      index: i,
      x: .1 + (i % 10) * .08,
      y: .1 + (i ~/ 10) * .12,
      type: switch (i) {
        0 => TileType.start,
        2 => TileType.hospital,
        3 => TileType.shop,
        4 => TileType.secretSociety,
        5 => TileType.jail,
        6 => TileType.police,
        7 || 9 => TileType.portal,
        59 => TileType.finish,
        _ => TileType.normal,
      },
    ),
]);
GameController _game({int dice = 1}) => GameController.newGame(
  names: ['You', 'Computer 1'],
  colors: [1, 2],
  board: _board(),
  computerPlayerIds: {'p2'},
  diceRoller: () => dice,
);

void main() {
  test('Computer seats persist; legacy local saves remain pass and play', () {
    final game = _game();
    addTearDown(game.dispose);
    final saved =
        jsonDecode(jsonEncode(game.session.toJson())) as Map<String, dynamic>;
    final restored = GameController(
      session: GameSession.fromJson(saved),
      board: game.board,
    );
    addTearDown(restored.dispose);
    expect(restored.session.computerPlayerIds, {'p2'});
    expect(restored.localPlayerId, 'p1');
    saved.remove('computerPlayerIds');
    expect(GameSession.fromJson(saved).isComputerGame, isFalse);
    saved['computerPlayerIds'] = ['p1', 'p2'];
    expect(() => GameSession.fromJson(saved), throwsFormatException);
    saved['computerPlayerIds'] = ['unknown'];
    expect(() => GameSession.fromJson(saved), throwsFormatException);
  });

  test('Computer never takes the human turn and uses the normal die', () {
    final game = _game(dice: 2);
    addTearDown(game.dispose);
    final strategy = ComputerStrategy();
    strategy.takeAction(game);
    expect(game.session.phase, TurnPhase.ready);
    game.session.currentPlayerIndex = 1;
    strategy.takeAction(game);
    expect(game.session.lastDice, 2);
    expect(game.session.currentPlayer.position, 2);
    expect(game.session.phase, TurnPhase.animating);
    game.finishAnimation();
    expect(game.session.phase, TurnPhase.shopping);
    strategy.takeAction(game);
    expect(game.session.phase, TurnPhase.specialReview);
    strategy.takeAction(game);
    expect(game.session.currentPlayerIndex, 0);
    expect(game.session.phase, TurnPhase.ready);
    expect(game.session.isComputerTurn, isFalse);
  });

  for (final cash in [0, 10]) {
    test('Computer resolves hospital treatment with cash $cash', () {
      final game = _game();
      addTearDown(game.dispose);
      game.session.currentPlayerIndex = 1;
      final player = game.session.currentPlayer;
      player.position = 2;
      player.cash = cash;
      player.isInjured = true;
      game.session.pendingHospital = true;
      game.session.phase = TurnPhase.hospitalChoice;
      ComputerStrategy().takeAction(game);
      expect(player.isInjured, isFalse);
      expect(player.position, cash == 0 ? 0 : 2);
      expect(
        game.session.phase,
        cash == 0 ? TurnPhase.specialReview : TurnPhase.shopping,
      );
    });
  }

  test(
    'Computer uses a health kit and exits a sold-out hospital without waiting',
    () {
      final game = _game();
      addTearDown(game.dispose);
      game.session.currentPlayerIndex = 1;
      final player = game.session.currentPlayer;
      player.position = 2;
      player.cash = 100;
      player.isInjured = true;
      player.inventory.healthPacks = 1;
      game.session.pendingHospital = true;
      game.session.phase = TurnPhase.hospitalChoice;
      final strategy = ComputerStrategy();
      strategy.takeAction(game);
      expect(player.inventory.healthPacks, 0);
      game.session.hospitalStocks[2]!.kits = 0;
      strategy.takeAction(game);
      expect(player.inventory.healthPacks, 0);
      expect(player.inventory.antidotes, 1);
      expect(game.session.phase, TurnPhase.specialReview);
    },
  );

  test(
    'Computer hospital shopping respects stock and preserves treatment money',
    () {
      final game = _game();
      addTearDown(game.dispose);
      game.session.currentPlayerIndex = 1;
      final player = game.session.currentPlayer;
      player.position = 2;
      player.cash = 30;
      game.session.pendingShopTile = 2;
      game.session.phase = TurnPhase.shopping;
      ComputerStrategy().takeAction(game);
      expect(player.inventory.healthPacks, 2);
      expect(game.session.hospitalStocks[2]!.kits, 0);
      expect(player.cash, 10);
    },
  );

  test('Computer pays an affordable police bribe and takes jail otherwise', () {
    for (final cash in [0, 100]) {
      final game = _game();
      addTearDown(game.dispose);
      game.session.currentPlayerIndex = 1;
      game.session.currentPlayer.position = 6;
      game.session.currentPlayer.cash = cash;
      game.session.pendingPoliceFine = 20;
      game.session.pendingPoliceJail = 5;
      game.session.phase = TurnPhase.jailChoice;
      ComputerStrategy().takeAction(game);
      expect(game.session.currentPlayer.position, cash == 0 ? 5 : 6);
      expect(game.session.currentPlayer.cash, cash == 0 ? 0 : 80);
    }
  });

  test(
    'Computer chooses a portal card without inspecting its hidden direction',
    () {
      final game = _game();
      addTearDown(game.dispose);
      game.session.currentPlayerIndex = 1;
      game.session.currentPlayer.position = 7;
      game.session.pendingPortalTile = 7;
      game.session.portalCardDirections.addAll([-1, 1]);
      game.session.lastDice = 1;
      game.session.phase = TurnPhase.portalChoice;
      ComputerStrategy(
        chooseCard: (count) {
          expect(count, 2);
          return 1;
        },
      ).takeAction(game);
      expect(game.session.currentPlayer.position, 9);
      expect(game.session.phase, TurnPhase.portalTravel);
    },
  );

  test('Computer uses a legal weapon and returns play to the human', () {
    final game = _game(dice: 6);
    addTearDown(game.dispose);
    game.session.currentPlayerIndex = 1;
    final player = game.session.currentPlayer;
    player.position = 30;
    player.inventory.stabbers = 1;
    game.session.players[0].position = 32;
    game.session.lastDice = 6;
    game.session.phase = TurnPhase.preMoveWeaponChoice;
    final strategy = ComputerStrategy();
    strategy.takeAction(game);
    expect(game.session.players[0].position, 0);
    expect(player.inventory.stabbers, 0);
    expect(player.inventory.stars, 3);
    game.finishAnimation();
    strategy.takeAction(game);
    expect(game.session.phase, TurnPhase.ready);
    expect(game.session.currentPlayerIndex, 0);
  });

  test('Computer resolves event cards and declines unavailable attacks', () {
    final game = _game();
    addTearDown(game.dispose);
    game.session.currentPlayerIndex = 1;
    game.session.pendingCardId = 'cash_30';
    game.session.phase = TurnPhase.eventReveal;
    ComputerStrategy().takeAction(game);
    expect(game.session.pendingCardId, isNull);
    expect(game.session.phase, TurnPhase.ready);
    game.session.currentPlayerIndex = 1;
    game.session.phase = TurnPhase.weaponAction;
    ComputerStrategy().takeAction(game);
    expect(game.session.currentPlayerIndex, 0);
  });

  test('Computer can hire and release a hitman through normal rules', () {
    final game = _game();
    addTearDown(game.dispose);
    game.session.currentPlayerIndex = 1;
    game.session.currentPlayer.position = 4;
    game.session.currentPlayer.cash = 250;
    game.session.players[0].position = 40;
    game.session.pendingShopTile = 4;
    game.session.phase = TurnPhase.shopping;
    final strategy = ComputerStrategy();
    strategy.takeAction(game);
    expect(game.session.players[1].cash, 50);
    expect(game.session.players[0].position, 40);
    expect(game.session.hitmanHired, isTrue);
    game.session.currentPlayerIndex = 1;
    game.session.phase = TurnPhase.ready;
    strategy.takeAction(game);
    expect(game.beginDiceRoll(), isNull);
    expect(game.session.players[0].position, 0);
    game.finishAnimation();
    strategy.takeAction(game);
    expect(game.session.hitmanHired, isFalse);
    expect(game.session.phase, TurnPhase.ready);
    expect(game.session.currentPlayerIndex, 0);
  });

  testWidgets('Computer driver pauses, resumes and cancels when disposed', (
    tester,
  ) async {
    final game = _game();
    game.session.currentPlayerIndex = 1;
    var rolls = 0;
    final driver = ComputerTurnDriver(
      game: game,
      rollDice: () {
        rolls++;
        game.beginDiceRoll();
      },
    );
    driver.pause();
    await tester.pump(const Duration(seconds: 2));
    expect(rolls, 0);
    driver.resume();
    await tester.pump(const Duration(milliseconds: 800));
    expect(rolls, 1);
    game.session.phase = TurnPhase.ready;
    driver.resume();
    driver.dispose();
    await tester.pump(const Duration(seconds: 2));
    expect(rolls, 1);
    await tester.pumpWidget(const SizedBox.shrink());
    game.dispose();
  });
}
