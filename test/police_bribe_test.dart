import 'package:flutter_test/flutter_test.dart';
import 'package:spiral_pass_play/features/game/application/game_controller.dart';
import 'package:spiral_pass_play/features/game/domain/board_definition.dart';
import 'package:spiral_pass_play/features/game/domain/game_session.dart';
import 'package:spiral_pass_play/features/game/domain/weapon.dart';

BoardDefinition _board() => BoardDefinition([
  for (var i = 0; i <= 40; i++)
    BoardTile(
      index: i,
      x: i / 40,
      y: .5,
      type: switch (i) {
        0 => TileType.start,
        5 || 23 => TileType.portal,
        10 || 30 => TileType.jail,
        17 => TileType.shop,
        20 => TileType.police,
        40 => TileType.finish,
        _ => TileType.normal,
      },
      amount: i == 20
          ? 20
          : i == 10 || i == 30
          ? 4
          : 0,
    ),
]);

GameController _game({int from = 19, int dice = 1, BoardDefinition? board}) {
  final game = GameController.newGame(
    names: ['One', 'Two'],
    colors: [1, 2],
    board: board ?? _board(),
    diceRoller: () => dice,
    eventCardOrder: ['forward_3'],
  );
  game.session.currentPlayer
    ..position = from
    ..cash = 70;
  addTearDown(game.dispose);
  return game;
}

void main() {
  test('Police landing offers the bribe before any jail transfer', () {
    final game = _game();
    final result = game.roll()!;
    expect(result.path, [20]);
    expect(result.effectLabel, 'POLICE · BRIBE CHOICE');
    expect(game.session.currentPlayer.position, 20);
    expect(game.session.currentPlayer.skipTurns, 0);
    expect(game.session.currentPlayer.cash, 70);
    expect(game.session.pendingPoliceFine, 20);
    expect(game.session.pendingPoliceJail, 10);
    expect(game.session.message, isNot(contains('Moved to JAIL')));
    game.finishAnimation();
    expect(game.session.phase, TurnPhase.jailChoice);
    expect(game.session.tileSummary!.finalPosition, 20);
  });

  test('Paying the bribe keeps the police position without losing a turn', () {
    final game = _game();
    final player = game.session.currentPlayer;
    player.skipTurns = 2;
    game.roll();
    game.finishAnimation();
    game.choosePolicePenalty(payFine: true);
    expect(player.position, 20);
    expect(player.cash, 50);
    expect(player.debt, 0);
    expect(player.skipTurns, 2);
    expect(game.session.pendingPoliceFine, isNull);
    expect(game.session.pendingPoliceJail, isNull);
    expect(game.session.phase, TurnPhase.specialReview);
    game.choosePolicePenalty(payFine: true);
    game.choosePolicePenalty(payFine: false);
    expect(player.cash, 50);
    expect(player.position, 20);
    expect(player.skipTurns, 2);
  });

  test(
    'Refusal alone animates to jail and applies exactly one missed turn',
    () {
      final game = _game();
      final player = game.session.currentPlayer;
      game.roll();
      game.finishAnimation();
      game.choosePolicePenalty(payFine: false);
      expect(player.position, 10);
      expect(player.cash, 70);
      // The jail tile has a four-turn landing penalty; it must not run again.
      expect(player.skipTurns, 1);
      expect(game.session.phase, TurnPhase.animating);
      expect(game.lastOutcome!.path, [10]);
      expect(game.lastOutcome!.landedType, TileType.jail);
      expect(game.session.pendingPoliceFine, isNull);
      expect(game.session.pendingPoliceJail, isNull);
      game.choosePolicePenalty(payFine: false);
      game.choosePolicePenalty(payFine: true);
      game.finishAnimation();
      game.finishAnimation();
      expect(game.session.phase, TurnPhase.specialReview);
      expect(game.session.tileSummary!.finalPosition, 10);
      expect(player.skipTurns, 1);
      expect(player.cash, 70);
    },
  );

  test('Unaffordable bribe does not create debt or bypass the choice', () {
    final game = _game();
    final player = game.session.currentPlayer;
    player
      ..cash = 19
      ..debt = 7;
    game.roll();
    game.finishAnimation();
    game.choosePolicePenalty(payFine: true);
    expect(game.session.phase, TurnPhase.jailChoice);
    expect(player.position, 20);
    expect(player.cash, 19);
    expect(player.debt, 7);
    expect(player.skipTurns, 0);
    game.choosePolicePenalty(payFine: false);
    expect(player.position, 10);
    expect(player.cash, 19);
    expect(player.debt, 7);
    expect(player.skipTurns, 1);
  });

  for (final pay in [false, true]) {
    test(
      'A saved contraband interception ${pay ? 'accepts the bribe in place' : 'transfers only after refusal'}',
      () {
        final game = _game(from: 14, dice: 6);
        final player = game.session.currentPlayer;
        player.inventory.stabbers = 2;
        player.inventory.pewPews = 1;
        expect(game.roll()!.path, [15, 16, 17]);
        expect(player.position, 17);
        expect(player.inventory.hasWeapons, isFalse);
        expect(game.session.pendingShopTile, isNull);
        game.finishAnimation();
        final restored = GameController(
          session: GameSession.fromJson(game.session.toJson()),
          board: game.board,
        );
        addTearDown(restored.dispose);
        expect(restored.session.pendingPoliceJail, 10);
        expect(restored.session.currentPlayer.position, 17);
        restored.choosePolicePenalty(payFine: pay);
        expect(restored.session.currentPlayer.position, pay ? 17 : 10);
        expect(restored.session.currentPlayer.cash, pay ? 50 : 70);
        expect(restored.session.currentPlayer.skipTurns, pay ? 0 : 1);
        expect(restored.session.currentPlayer.inventory.hasWeapons, isFalse);
        if (!pay) restored.finishAnimation();
        restored.choosePolicePenalty(payFine: pay);
        expect(restored.session.currentPlayer.cash, pay ? 50 : 70);
        expect(restored.session.currentPlayer.skipTurns, pay ? 0 : 1);
      },
    );
  }

  test(
    'Buying a weapon near police stops at the shop until the bribe decision',
    () {
      final game = _game(from: 16);
      game.roll();
      game.finishAnimation();
      expect(game.session.phase, TurnPhase.shopping);
      expect(game.buyWeapon(WeaponType.stabber), isTrue);
      expect(game.session.currentPlayer.position, 17);
      expect(game.session.currentPlayer.inventory.stabbers, 0);
      expect(game.session.pendingShopTile, isNull);
      expect(game.session.pendingPoliceJail, 10);
      expect(game.lastOutcome!.path, isEmpty);
      game.finishAnimation();
      game.choosePolicePenalty(payFine: true);
      expect(game.session.currentPlayer.position, 17);
      expect(game.session.currentPlayer.cash, 10);
      expect(game.session.currentPlayer.skipTurns, 0);
    },
  );

  test('Forced police landing also delays the jail transfer', () {
    final tiles = _board().tiles.toList();
    tiles[15] = tiles[15].withChanges({'type': 'moveForward', 'amount': 5});
    final game = _game(from: 14, board: BoardDefinition(tiles));
    expect(game.roll()!.path, [15, 20]);
    expect(game.session.currentPlayer.position, 20);
    expect(game.session.pendingPoliceJail, 10);
    game.finishAnimation();
    game.choosePolicePenalty(payFine: true);
    expect(game.session.currentPlayer.position, 20);
  });

  test('Event arrival near police preserves the choice after card review', () {
    final tiles = _board().tiles.toList();
    tiles[14] = tiles[14].withChanges({'type': 'event'});
    final game = _game(from: 13, board: BoardDefinition(tiles));
    game.session.currentPlayer.inventory.pewPews = 1;
    expect(game.roll()!.path, [14, 15, 16, 17]);
    expect(game.session.currentPlayer.position, 17);
    expect(game.session.pendingPoliceJail, 10);
    game.finishAnimation();
    expect(game.session.phase, TurnPhase.eventReveal);
    game.dismissEventCard();
    expect(game.session.phase, TurnPhase.jailChoice);
    game.choosePolicePenalty(payFine: false);
    expect(game.lastOutcome!.path, [10]);
    game.finishAnimation();
    expect(game.session.phase, TurnPhase.specialReview);
    expect(game.session.currentPlayer.skipTurns, 1);
  });

  test('Stars still cause immediate jail and cannot be bribed away', () {
    final game = _game(from: 14, dice: 6);
    final player = game.session.currentPlayer;
    player.inventory.stars = 3;
    player.inventory.stabbers = 1;
    expect(game.roll()!.path, [15, 16, 17, 10]);
    expect(player.position, 10);
    expect(player.inventory.stars, 0);
    expect(player.inventory.hasWeapons, isFalse);
    expect(player.skipTurns, 3);
    expect(game.session.pendingPoliceFine, isNull);
    expect(game.session.pendingPoliceJail, isNull);
    game.finishAnimation();
    expect(game.session.phase, TurnPhase.specialReview);
    game.choosePolicePenalty(payFine: true);
    expect(player.cash, 70);
    expect(player.skipTurns, 3);
  });

  for (final pay in [false, true]) {
    test(
      'Legacy choice already at jail ${pay ? 'pays' : 'refuses'} without inventing an origin',
      () {
        final game = _game();
        game.roll();
        game.finishAnimation();
        final data = game.session.toJson();
        data.remove('pendingPoliceJail');
        (data['players'] as List).first['position'] = 10;
        (data['tileSummary'] as Map)['finalPosition'] = 10;
        final restored = GameController(
          session: GameSession.fromJson(data),
          board: game.board,
        );
        addTearDown(restored.dispose);
        expect(restored.session.pendingPoliceJail, 10);
        restored.choosePolicePenalty(payFine: pay);
        expect(restored.session.currentPlayer.position, 10);
        expect(restored.session.currentPlayer.cash, pay ? 50 : 70);
        expect(restored.session.currentPlayer.skipTurns, pay ? 0 : 1);
        expect(restored.session.phase, TurnPhase.specialReview);
      },
    );
  }

  test('Invalid bribe destinations and encounters are rejected on resume', () {
    final game = _game();
    game.roll();
    game.finishAnimation();
    for (final destination in [null, -1, 20, 41]) {
      final saved = game.session.toJson();
      saved['pendingPoliceJail'] = destination;
      expect(
        () => GameController(
          session: GameSession.fromJson(saved),
          board: game.board,
        ),
        throwsStateError,
      );
    }
    final saved = game.session.toJson();
    (saved['players'] as List).first['position'] = 1;
    expect(
      () => GameController(
        session: GameSession.fromJson(saved),
        board: game.board,
      ),
      throwsStateError,
    );
  });
}
