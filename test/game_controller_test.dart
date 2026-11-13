import 'package:flutter_test/flutter_test.dart';
import 'package:spiral_pass_play/features/game/application/game_controller.dart';
import 'package:spiral_pass_play/features/game/domain/board_definition.dart';
import 'package:spiral_pass_play/features/game/domain/game_session.dart';

final sampleBoard = BoardDefinition([
  const BoardTile(index: 0, x: 0.0, y: 0.0, type: TileType.start),
  const BoardTile(index: 1, x: 0.1, y: 0.0),
  const BoardTile(index: 2, x: 0.2, y: 0.0, type: TileType.jail),
  const BoardTile(index: 3, x: 0.3, y: 0.0, type: TileType.cash, amount: 50),
  const BoardTile(index: 4, x: 0.4, y: 0.0),
  const BoardTile(index: 5, x: 0.5, y: 0.0, type: TileType.finish),
]);

final eventBoard = BoardDefinition([
  const BoardTile(index: 0, x: 0.0, y: 0.0, type: TileType.start),
  const BoardTile(index: 1, x: 0.1, y: 0.0, type: TileType.event),
  const BoardTile(index: 2, x: 0.2, y: 0.0),
  const BoardTile(index: 3, x: 0.3, y: 0.0),
  const BoardTile(index: 4, x: 0.4, y: 0.0, type: TileType.finish),
]);

GameController makeController(
  int Function() roller, {
  BoardDefinition? board,
  List<String>? deck,
}) => GameController.newGame(
  names: ['Player 1', 'Player 2', 'Player 3'],
  colors: [0xFFEF5350, 0xFF42A5F5, 0xFF66BB6A],
  board: board ?? sampleBoard,
  diceRoller: roller,
  eventCardOrder: deck,
);

void nextTurn(GameController game) {
  finishAndReview(game);
  if (game.session.phase == TurnPhase.handoff) game.acknowledgeHandoff();
}

// Existing turn-flow tests acknowledge the new special-tile explanation.
void finishAndReview(GameController game) {
  game.finishAnimation();
  if (game.session.phase == TurnPhase.specialReview) game.dismissTileSummary();
}

void main() {
  test(
    'Go-to-jail tiles move to the configured jail and apply its penalty',
    () {
      final board = BoardDefinition([
        const BoardTile(index: 0, x: 0, y: 0, type: TileType.start),
        const BoardTile(
          index: 1,
          x: .2,
          y: 0,
          type: TileType.goToJail,
          destination: 3,
        ),
        const BoardTile(index: 2, x: .4, y: 0),
        const BoardTile(index: 3, x: .6, y: 0, type: TileType.jail, amount: 2),
        const BoardTile(index: 4, x: 1, y: 0, type: TileType.finish),
      ]);
      final game = makeController(() => 1, board: board);
      addTearDown(game.dispose);
      final action = game.roll()!;
      expect(action.path, [1, 3]);
      expect(game.session.players.first.position, 3);
      expect(game.session.players.first.skipTurns, 2);
      finishAndReview(game);
      expect(game.session.currentPlayerIndex, 1);
      expect(game.session.phase, TurnPhase.handoff);
    },
  );

  test('Go-to-jail destinations must be jail tiles', () {
    expect(
      () => BoardDefinition([
        const BoardTile(index: 0, x: 0, y: 0, type: TileType.start),
        const BoardTile(
          index: 1,
          x: .5,
          y: 0,
          type: TileType.goToJail,
          destination: 2,
        ),
        const BoardTile(index: 2, x: 1, y: 0, type: TileType.finish),
      ]),
      throwsArgumentError,
    );
  });

  for (final spaces in [2, 4]) {
    test('Setback moves $spaces spaces and resolves the sea destination', () {
      final board = BoardDefinition([
        for (var i = 0; i < 7; i++)
          BoardTile(
            index: i,
            x: i / 6,
            y: 0,
            type: i == 0
                ? TileType.start
                : i == 6
                ? TileType.finish
                : i == 5
                ? TileType.setBack
                : TileType.sea,
            amount: i == 5 ? spaces : 0,
          ),
      ]);
      final game = makeController(() => 1, board: board);
      addTearDown(game.dispose);
      game.session.players.first.position = 4;
      final action = game.roll()!;
      expect(action.path, [5, 5 - spaces, 0]);
      expect(game.session.players.first.position, 0);
      finishAndReview(game);
      expect(game.session.phase, TurnPhase.handoff);
    });
  }

  test('Starts with 3 local players, ready to roll', () {
    final game = makeController(() => 1);
    expect(game.session.players.length, 3);
    expect(game.session.currentPlayer.name, 'Player 1');
    expect(game.session.currentPlayer.cash, 10);
    expect(game.session.phase, TurnPhase.ready);
  });

  test('Dice animation locks turns before movement is resolved', () {
    final game = makeController(() => 3);
    expect(game.beginDiceRoll(), 3);
    expect(game.session.phase, TurnPhase.rolling);
    expect(game.session.players.first.position, 0);
    expect(game.beginDiceRoll(), isNull);
    final outcome = game.resolveDiceRoll()!;
    expect(outcome.dice, 3);
    expect(outcome.path, [1, 2, 3]);
    expect(game.session.players.first.position, 3);
    expect(game.session.players.first.cash, 60);
    expect(game.session.phase, TurnPhase.animating);
    expect(game.roll(), isNull);
  });

  test('Finishing animation requests hand-off, not an immediate new roll', () {
    final game = makeController(() => 1);
    game.roll();
    finishAndReview(game);
    expect(game.session.phase, TurnPhase.handoff);
    expect(game.session.currentPlayerIndex, 1);
    expect(game.beginDiceRoll(), isNull);
    game.acknowledgeHandoff();
    expect(game.session.phase, TurnPhase.ready);
    expect(game.session.currentPlayer.name, 'Player 2');
  });

  test('Jail skips affected player exactly once on their next turn', () {
    final game = makeController(() => 2);
    game.roll(); // Player 1 lands on JAIL.
    expect(game.session.players[0].skipTurns, 1);
    nextTurn(game); // Player 2.
    game.roll(); // Player 2 lands on JAIL.
    nextTurn(game); // Player 3.
    game.roll(); // Player 3 lands on JAIL.
    finishAndReview(game); // All forfeits are consumed, back to P1.
    expect(game.session.players.every((p) => p.skipTurns == 0), isTrue);
    expect(game.session.phase, TurnPhase.handoff);
    expect(game.session.currentPlayerIndex, 0);
    expect(game.session.handoffMessage, contains('missed a turn'));
  });

  test('Event card is revealed after movement, then hand-off is required', () {
    final game = makeController(() => 1, board: eventBoard, deck: ['cash_30']);
    final action = game.roll()!;
    expect(action.eventCardId, 'cash_30');
    expect(game.session.players.first.cash, 40);
    expect(game.session.pendingCardId, 'cash_30');
    finishAndReview(game);
    expect(game.session.phase, TurnPhase.eventReveal);
    expect(
      game.session.tileSummary!.changes,
      contains('Cash: +\$30 (10 → 40)'),
    );
    expect(game.beginDiceRoll(), isNull);
    game.dismissEventCard();
    expect(game.session.pendingCardId, isNull);
    expect(game.session.phase, TurnPhase.handoff);
  });

  test('Event card movement can reach the finish', () {
    final game = makeController(
      () => 1,
      board: eventBoard,
      deck: ['forward_3'],
    );
    final action = game.roll()!;
    expect(action.path, [1, 4]);
    expect(game.session.winnerId, 'p1');
    finishAndReview(game);
    expect(game.session.phase, TurnPhase.eventReveal);
    game.dismissEventCard();
    expect(game.session.phase, TurnPhase.completed);
    expect(game.beginDiceRoll(), isNull);
  });

  test('Event draw pile and pending reveal persist across save/reload', () {
    final game = makeController(
      () => 1,
      board: eventBoard,
      deck: ['fine_20', 'cash_30'],
    );
    game.roll();
    finishAndReview(game);
    final saved = GameSession.fromJson(game.session.toJson());
    expect(saved.phase, TurnPhase.eventReveal);
    expect(saved.pendingCardId, 'cash_30');
    expect(saved.eventDrawPile, ['fine_20']);
    expect(saved.eventDiscardPile, ['cash_30']);
    final restored = GameController(session: saved, board: eventBoard);
    restored.dismissEventCard();
    expect(restored.session.phase, TurnPhase.handoff);
  });

  test('Saved hand-off cannot be bypassed on resume', () {
    final game = makeController(() => 1);
    game.roll();
    finishAndReview(game);
    final saved = GameSession.fromJson(game.session.toJson());
    final restored = GameController(
      session: saved,
      board: sampleBoard,
      diceRoller: () => 1,
    );
    expect(restored.session.phase, TurnPhase.handoff);
    expect(restored.beginDiceRoll(), isNull);
    restored.acknowledgeHandoff();
    expect(restored.beginDiceRoll(), 1);
  });

  test('Fines use available cash and convert the rest to debt', () {
    final board = BoardDefinition([
      const BoardTile(index: 0, x: 0, y: 0, type: TileType.start),
      const BoardTile(index: 1, x: .5, y: 0, type: TileType.fine, amount: 120),
      const BoardTile(index: 2, x: 1, y: 0, type: TileType.finish),
    ]);
    final game = makeController(() => 1, board: board);
    game.roll();
    expect(game.session.players.first.cash, 0);
    expect(game.session.players.first.debt, 110);
  });

  test('Only one pending event card can be revealed for a turn', () {
    final game = makeController(
      () => 1,
      board: eventBoard,
      deck: ['cash_30', 'fine_20'],
    );
    game.roll();
    expect(game.session.pendingCardId, 'fine_20');
    finishAndReview(game);
    expect(game.session.eventDrawPile, ['cash_30']);
    finishAndReview(game); // Duplicate renderer callback is harmless.
    expect(game.session.eventDiscardPile, ['fine_20']);
    game.dismissEventCard();
    game.dismissEventCard(); // Duplicate button tap cannot draw more cards.
    expect(game.session.eventDiscardPile, ['fine_20']);
    expect(game.session.phase, TurnPhase.handoff);
  });

  test('First to final tile wins and further rolls are blocked', () {
    final game = makeController(() => 5);
    game.roll();
    finishAndReview(game);
    expect(game.session.winnerId, 'p1');
    expect(game.session.phase, TurnPhase.completed);
    expect(game.roll(), isNull);
  });

  test('Legacy v2 save can be loaded', () {
    final game = makeController(() => 1);
    final serialized = game.session.toJson();
    serialized['schemaVersion'] = 2;
    serialized.remove('pendingCardId');
    serialized.remove('eventDrawPile');
    serialized.remove('eventDiscardPile');
    final restored = GameSession.fromJson(serialized);
    expect(restored.phase, TurnPhase.ready);
    expect(restored.players.length, 3);
  });

  test('Cannot open save against a different board', () {
    final game = makeController(() => 1);
    expect(
      () => GameController(
        session: game.session,
        board: BoardDefinition(sampleBoard.tiles, id: 'different-map'),
      ),
      throwsStateError,
    );
  });

  test('Cannot create more than five players', () {
    expect(
      () => GameController.newGame(
        names: List.generate(6, (i) => 'Player $i'),
        colors: List.generate(6, (i) => 0xFFFFFFFF),
        board: sampleBoard,
      ),
      throwsArgumentError,
    );
  });
}
