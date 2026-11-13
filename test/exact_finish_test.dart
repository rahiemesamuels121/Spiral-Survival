import 'package:flutter_test/flutter_test.dart';
import 'package:spiral_pass_play/features/game/application/game_controller.dart';
import 'package:spiral_pass_play/features/game/domain/board_definition.dart';
import 'package:spiral_pass_play/features/game/domain/game_session.dart';

BoardDefinition board({int? cashAt, int? forwardAt}) => BoardDefinition([
  for (var i = 0; i <= 10; i++)
    BoardTile(
      index: i,
      x: i / 10,
      y: 0,
      type: i == 0
          ? TileType.start
          : i == 10
          ? TileType.finish
          : i == cashAt
          ? TileType.cash
          : i == forwardAt
          ? TileType.moveForward
          : TileType.normal,
      amount: i == cashAt
          ? 50
          : i == forwardAt
          ? 2
          : 0,
    ),
]);
GameController create(BoardDefinition board, int from, int dice) {
  final game = GameController.newGame(
    names: ['One', 'Two'],
    colors: [1, 2],
    board: board,
    diceRoller: () => dice,
  );
  game.session.currentPlayer.position = from;
  addTearDown(game.dispose);
  return game;
}

void main() {
  for (var remaining = 1; remaining <= 5; remaining++) {
    test(
      'Rolling 6 with $remaining spaces left does not move or retrigger the current tile',
      () {
        final game = create(board(cashAt: 10 - remaining), 10 - remaining, 6);
        final player = game.session.currentPlayer;
        final cash = player.cash;
        player.inventory.pewPews = 1;
        game.session.players[1].position = 9;
        game.roll();
        if (game.session.phase == TurnPhase.preMoveWeaponChoice) {
          game.chooseMovement();
        }
        final outcome = game.lastOutcome!;
        expect(outcome.path, isEmpty);
        expect(player.position, 10 - remaining);
        expect(player.cash, cash);
        expect(game.session.winnerId, isNull);
        game.finishAnimation();
        expect(game.session.phase, TurnPhase.handoff);
        final restored = GameSession.fromJson(game.session.toJson());
        expect(restored.players.first.position, 10 - remaining);
        expect(restored.winnerId, isNull);
        game.dismissTileSummary();
        expect(game.session.phase, TurnPhase.handoff);
      },
    );
  }
  for (var remaining = 1; remaining <= 6; remaining++) {
    test('Exact roll $remaining wins with $remaining spaces left', () {
      final game = create(board(), 10 - remaining, remaining);
      expect(game.roll()!.path.last, 10);
      expect(game.session.winnerId, 'p1');
      game.finishAnimation();
      expect(game.session.phase, TurnPhase.completed);
    });
  }
  test('A smaller roll advances normally without winning', () {
    final game = create(board(), 7, 2);
    expect(game.roll()!.path, [8, 9]);
    expect(game.session.currentPlayer.position, 9);
    expect(game.session.winnerId, isNull);
  });
  test('Forward tile cannot clamp an overshoot to FINISH', () {
    final game = create(board(forwardAt: 9), 8, 1);
    expect(game.roll()!.path, [9]);
    expect(game.session.currentPlayer.position, 9);
    expect(game.session.winnerId, isNull);
  });
  test('Forward event cannot clamp an overshoot to FINISH', () {
    final tiles = board().tiles.toList();
    tiles[8] = tiles[8].withChanges({'type': 'event'});
    final game = GameController.newGame(
      names: ['One', 'Two'],
      colors: [1, 2],
      board: BoardDefinition(tiles),
      diceRoller: () => 1,
      eventCardOrder: ['forward_3'],
    );
    addTearDown(game.dispose);
    game.session.currentPlayer.position = 7;
    expect(game.roll()!.path, [8]);
    expect(game.session.currentPlayer.position, 8);
    expect(game.session.winnerId, isNull);
    game.finishAnimation();
    expect(game.session.phase, TurnPhase.eventReveal);
  });
}
