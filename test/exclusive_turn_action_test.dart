import 'package:flutter_test/flutter_test.dart';
import 'package:spiral_pass_play/features/game/application/game_controller.dart';
import 'package:spiral_pass_play/features/game/domain/board_definition.dart';
import 'package:spiral_pass_play/features/game/domain/game_session.dart';
import 'package:spiral_pass_play/features/game/domain/weapon.dart';

BoardDefinition _board({TileType landing = TileType.normal}) =>
    BoardDefinition([
      for (var i = 0; i < 60; i++)
        BoardTile(
          index: i,
          x: .1 + (i % 10) * .08,
          y: .1 + (i ~/ 10) * .12,
          type: i == 0
              ? TileType.start
              : i == 59
              ? TileType.finish
              : i == 16
              ? landing
              : TileType.normal,
        ),
    ]);
GameController _game({TileType landing = TileType.normal}) {
  final game = GameController.newGame(
    names: ['One', 'Two'],
    colors: [1, 2],
    board: _board(landing: landing),
    diceRoller: () => 6,
  );
  game.session.currentPlayer.position = 10;
  return game;
}

void main() {
  for (final type in WeaponType.values) {
    test(
      '${type.name}: attack uses the roll, stays put and remains spent after resume',
      () {
        final game = _game();
        addTearDown(game.dispose);
        game.session.currentPlayer.inventory.stabbers = 1;
        game.session.currentPlayer.inventory.pewPews = 1;
        game.session.players[1].position = 15;
        game.roll();
        expect(game.session.phase, TurnPhase.preMoveWeaponChoice);
        expect(game.session.currentPlayer.position, 10);
        expect(game.useWeapon(type, 1), isTrue);
        expect(game.session.players.first.position, 10);
        expect(game.session.players[1].position, 0);
        game.chooseMovement();
        expect(game.session.players.first.position, 10);
        expect(game.beginDiceRoll(), isNull);
        final restored = GameController(
          session: GameSession.fromJson(game.session.toJson()),
          board: game.board,
        );
        addTearDown(restored.dispose);
        expect(restored.session.phase, TurnPhase.specialReview);
        expect(restored.beginDiceRoll(), isNull);
        restored.chooseMovement();
        expect(restored.session.players.first.position, 10);
        expect(restored.useWeapon(type, 1), isFalse);
        restored.dismissTileSummary();
        expect(restored.session.currentPlayerIndex, 1);
        expect(restored.session.phase, TurnPhase.handoff);
      },
    );

    test(
      '${type.name}: choosing movement prevents attacking even if the target remains in range',
      () {
        final game = _game();
        addTearDown(game.dispose);
        game.session.currentPlayer.inventory.stabbers = 1;
        game.session.currentPlayer.inventory.pewPews = 1;
        game.session.players[1].position = 15;
        game.roll();
        game.chooseMovement();
        expect(game.session.players.first.position, 16);
        expect(game.weaponTargets(type), isEmpty);
        expect(game.useWeapon(type, 1), isFalse);
        game.finishAnimation();
        expect(game.session.tileSummary, isNull);
        expect(game.session.phase, TurnPhase.handoff);
        expect(game.session.players[1].position, 15);
      },
    );
  }

  test('A player entering range only after movement cannot attack', () {
    final game = _game();
    addTearDown(game.dispose);
    game.session.currentPlayer.inventory.stabbers = 1;
    game.session.players[1].position = 20;
    game.roll();
    expect(game.session.players.first.position, 16);
    game.finishAnimation();
    expect(game.session.phase, TurnPhase.handoff);
    expect(game.useWeapon(WeaponType.stabber, 1), isFalse);
    expect(game.session.players[1].position, 20);
  });

  test('A weapon purchased after moving cannot attack using that roll', () {
    final game = _game(landing: TileType.shop);
    addTearDown(game.dispose);
    game.session.currentPlayer.cash = 100;
    game.session.players[1].position = 20;
    game.roll();
    game.finishAnimation();
    expect(game.buyWeapon(WeaponType.stabber), isTrue);
    game.finishShopping();
    game.dismissTileSummary();
    expect(game.session.phase, TurnPhase.handoff);
    expect(game.useWeapon(WeaponType.stabber, 1), isFalse);
    expect(game.session.players.first.inventory.stabbers, 1);
  });

  test(
    'Hitman attack replaces movement, ends the turn and survives interrupted animation',
    () {
      final game = _game();
      addTearDown(game.dispose);
      game.session.hitmanHired = true;
      game.session.hitmanOwnerId = 'p1';
      game.session.hitmanTile = 25;
      game.session.players[1].position = 25;
      expect(game.useHitman(1), isTrue);
      expect(game.session.players.first.position, 10);
      expect(game.session.players[1].position, 0);
      expect(game.beginDiceRoll(), isNull);
      final restored = GameController(
        session: GameSession.fromJson(game.session.toJson()),
        board: game.board,
      );
      addTearDown(restored.dispose);
      expect(restored.session.phase, TurnPhase.specialReview);
      expect(restored.beginDiceRoll(), isNull);
      restored.dismissTileSummary();
      expect(restored.session.currentPlayerIndex, 1);
      expect(restored.session.hitmanHired, isFalse);
      expect(restored.session.players.first.position, 10);
    },
  );

  test('Moving to Secret Society cannot be followed by a hitman attack', () {
    final game = _game(landing: TileType.secretSociety);
    addTearDown(game.dispose);
    game.session.hitmanHired = true;
    game.session.hitmanOwnerId = 'p1';
    game.session.hitmanTile = 25;
    game.session.players[1].position = 25;
    game.roll();
    game.finishAnimation();
    expect(game.session.phase, TurnPhase.shopping);
    expect(game.hitmanTargets, isEmpty);
    expect(game.useHitman(1), isFalse);
    expect(game.session.hitmanHired, isTrue);
    game.finishShopping();
    game.dismissTileSummary();
    expect(game.session.currentPlayerIndex, 1);
    expect(game.session.players[1].position, 25);
  });

  test('Old after-movement attack states cannot be used to attack again', () {
    final game = _game();
    addTearDown(game.dispose);
    game.session.currentPlayer.inventory.stabbers = 1;
    game.session.players[1].position = 15;
    game.session.lastDice = 6;
    game.session.phase = TurnPhase.weaponAction;
    expect(game.weaponTargets(WeaponType.stabber), isEmpty);
    expect(game.useWeapon(WeaponType.stabber, 1), isFalse);
    game.skipWeaponAction();
    expect(game.session.currentPlayerIndex, 1);
  });
}
