import 'package:flutter_test/flutter_test.dart';
import 'package:spiral_pass_play/features/game/application/game_controller.dart';
import 'package:spiral_pass_play/features/game/data/board_repository.dart';
import 'package:spiral_pass_play/features/game/domain/board_definition.dart';
import 'package:spiral_pass_play/features/game/domain/game_session.dart';

GameController createGame(
  BoardDefinition board, {
  int from = 0,
  List<String>? deck,
}) {
  final game = GameController.newGame(
    names: ['One', 'Two'],
    colors: [1, 2],
    board: board,
    diceRoller: () => 1,
    eventCardOrder: deck,
  );
  game.session.players.first.position = from;
  // Fund transaction fixtures independently of the game's $10 starting cash.
  game.session.players.first.cash = 100;
  addTearDown(game.dispose);
  return game;
}

BoardDefinition policeBoard(int police, List<int> jails) => BoardDefinition([
  for (var i = 0; i <= 10; i++)
    BoardTile(
      index: i,
      x: i / 10,
      y: 0,
      type: i == 0
          ? TileType.start
          : i == 10
          ? TileType.finish
          : i == police
          ? TileType.police
          : jails.contains(i)
          ? TileType.jail
          : TileType.normal,
      amount: i == police
          ? 20
          : jails.contains(i)
          ? 2
          : 0,
      // A stale explicit destination must never override the nearest-jail rule.
      destination: i == police ? jails.last : null,
    ),
]);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  for (final withBoat in [false, true]) {
    test('Go back 3 onto sea resolves the hazard (boat: $withBoat)', () async {
      final game = createGame(
        await const BoardRepository().loadReferenceBoard(),
        from: 8,
      );
      final player = game.session.players.first;
      player.inventory.boats = withBoat ? 1 : 0;
      final outcome = game.roll()!;
      expect(outcome.path, withBoat ? [9, 6, 7, 8] : [9, 6, 0]);
      expect(player.position, withBoat ? 8 : 0);
      expect(player.inventory.boats, withBoat ? 1 : 0);
      expect(outcome.description, contains('SEA:'));
      game.finishAnimation();
      expect(game.session.phase, TurnPhase.specialReview);
      expect(game.session.tileSummary!.finalPosition, player.position);
    });
  }

  for (final entry in [
    (2, [1, 8], 1),
    (6, [1, 8], 8),
    (4, [2, 6], 2),
  ]) {
    test('Police at ${entry.$1} selects nearest jail ${entry.$3}', () {
      final game = createGame(
        policeBoard(entry.$1, entry.$2),
        from: entry.$1 - 1,
      );
      final outcome = game.roll()!;
      expect(outcome.path, [entry.$1]);
      expect(game.session.players.first.position, entry.$1);
      expect(game.session.pendingPoliceJail, entry.$3);
      expect(game.session.players.first.cash, 100);
      expect(game.session.players.first.skipTurns, 0);
      game.finishAnimation();
      expect(game.session.phase, TurnPhase.jailChoice);
      expect(game.session.pendingPoliceFine, 20);
      expect(game.beginDiceRoll(), isNull);
      game.dismissTileSummary();
      game.acknowledgeHandoff();
      expect(game.session.phase, TurnPhase.jailChoice);
    });
  }

  test('Paying the police fine charges once and never skips a turn', () {
    final game = createGame(policeBoard(2, [1, 8]), from: 1);
    game.session.players.first.cash = 20;
    game.roll();
    game.choosePolicePenalty(
      payFine: true,
    ); // Still moving: ignore premature choice.
    expect(game.session.players.first.cash, 20);
    game.finishAnimation();
    game.choosePolicePenalty(payFine: true);
    game.choosePolicePenalty(payFine: true);
    final player = game.session.players.first;
    expect(player.position, 2);
    expect(player.cash, 0);
    expect(game.session.pendingPoliceJail, isNull);
    expect(player.debt, 0);
    expect(player.skipTurns, 0);
    expect(game.session.pendingPoliceFine, isNull);
    expect(game.session.phase, TurnPhase.specialReview);
    expect(game.session.tileSummary!.changes, contains('Cash: −\$20 (20 → 0)'));
    game.dismissTileSummary();
    expect(game.session.currentPlayerIndex, 1);
  });

  test('Insufficient cash cannot pay; missing a turn never charges a fine', () {
    final game = createGame(policeBoard(2, [1, 8]), from: 1);
    final player = game.session.players.first;
    player.cash = 5;
    player.debt = 7;
    game.roll();
    game.finishAnimation();
    game.choosePolicePenalty(payFine: true);
    expect(game.session.phase, TurnPhase.jailChoice);
    expect(player.cash, 5);
    expect(player.debt, 7);
    game.choosePolicePenalty(payFine: false);
    game.choosePolicePenalty(payFine: false);
    expect(player.position, 1);
    expect(game.session.phase, TurnPhase.animating);
    expect(game.lastOutcome!.path, [1]);
    game.finishAnimation();
    expect(player.cash, 5);
    expect(player.debt, 7);
    expect(
      player.skipTurns,
      1,
    ); // Exactly one, even if the jail normally costs two.
    game.dismissTileSummary();
    game.acknowledgeHandoff();
    game.roll(); // Player Two advances from START to jail.
    game.finishAnimation();
    game.dismissTileSummary();
    expect(player.skipTurns, 0);
  });

  test(
    'Unresolved police choice and the chosen penalty both survive resume',
    () {
      final game = createGame(policeBoard(2, [1, 8]), from: 1);
      game.roll();
      game.finishAnimation();
      final restored = GameController(
        session: GameSession.fromJson(game.session.toJson()),
        board: game.board,
      );
      addTearDown(restored.dispose);
      expect(restored.session.phase, TurnPhase.jailChoice);
      expect(restored.session.pendingPoliceFine, 20);
      expect(restored.session.pendingPoliceJail, 1);
      expect(restored.session.players.first.position, 2);
      expect(restored.beginDiceRoll(), isNull);
      restored.choosePolicePenalty(payFine: true);
      final again = GameController(
        session: GameSession.fromJson(restored.session.toJson()),
        board: game.board,
      );
      addTearDown(again.dispose);
      expect(again.session.phase, TurnPhase.specialReview);
      again.choosePolicePenalty(payFine: true);
      expect(again.session.players.first.cash, 80);
      expect(again.session.players.first.position, 2);
      expect(again.session.pendingPoliceJail, isNull);
      expect(again.session.players.first.skipTurns, 0);
      again.dismissTileSummary();
      expect(again.session.phase, TurnPhase.handoff);
    },
  );

  test(
    'A portal card travels once without reopening cards at the arrival portal',
    () {
      final board = BoardDefinition([
        const BoardTile(index: 0, x: 0, y: 0, type: TileType.start),
        const BoardTile(
          index: 1,
          x: .3,
          y: 0,
          type: TileType.portal,
          destination: 2,
        ),
        const BoardTile(
          index: 2,
          x: .6,
          y: 0,
          type: TileType.portal,
          destination: 1,
        ),
        const BoardTile(index: 3, x: 1, y: 0, type: TileType.finish),
      ]);
      final game = createGame(board);
      expect(game.roll()!.path, [1]);
      game.finishAnimation();
      expect(game.session.phase, TurnPhase.portalChoice);
      game.choosePortalCard(game.session.portalCardDirections.indexOf(1));
      expect(game.session.currentPlayer.position, 2);
      game.finishAnimation();
      expect(game.session.phase, TurnPhase.specialReview);
      expect(game.session.pendingPortalTile, isNull);
    },
  );

  test('Forward movement applies the destination cash pickup exactly once', () {
    final board = BoardDefinition([
      const BoardTile(index: 0, x: 0, y: 0, type: TileType.start),
      const BoardTile(
        index: 1,
        x: .25,
        y: 0,
        type: TileType.moveForward,
        amount: 2,
      ),
      const BoardTile(index: 2, x: .5, y: 0, type: TileType.fine, amount: 99),
      const BoardTile(index: 3, x: .75, y: 0, type: TileType.cash, amount: 50),
      const BoardTile(index: 4, x: 1, y: 0, type: TileType.finish),
    ]);
    final game = createGame(board);
    expect(game.roll()!.path, [1, 3]);
    expect(game.session.players.first.cash, 150);
    game.finishAnimation();
    game.finishAnimation();
    expect(game.session.players.first.cash, 150);
  });

  test(
    'Moving onto a second event tile does not draw another pending card',
    () {
      final board = BoardDefinition([
        for (var i = 0; i <= 5; i++)
          BoardTile(
            index: i,
            x: i / 5,
            y: 0,
            type: i == 0
                ? TileType.start
                : i == 5
                ? TileType.finish
                : i == 1 || i == 4
                ? TileType.event
                : TileType.normal,
          ),
      ]);
      final game = createGame(board, deck: ['cash_30', 'forward_3']);
      expect(game.roll()!.path, [1, 4]);
      expect(game.session.eventDrawPile, ['cash_30']);
      expect(game.session.pendingCardId, 'forward_3');
      expect(game.session.players.first.cash, 100);
      game.finishAnimation();
      game.dismissEventCard();
      expect(game.session.phase, TurnPhase.handoff);
    },
  );

  for (final police in [false, true]) {
    test(
      'Event movement resolves ${police ? 'police before a saved choice' : 'sea restart'}',
      () {
        final board = BoardDefinition([
          for (var i = 0; i <= 5; i++)
            BoardTile(
              index: i,
              x: i / 5,
              y: 0,
              type: i == 0
                  ? TileType.start
                  : i == 5
                  ? TileType.finish
                  : i == 1
                  ? TileType.jail
                  : i == 2
                  ? (police ? TileType.police : TileType.sea)
                  : i == 4
                  ? TileType.event
                  : TileType.normal,
            ),
        ]);
        final game = createGame(board, from: 3, deck: ['backward_2']);
        final outcome = game.roll()!;
        expect(outcome.path, police ? [4, 2] : [4, 2, 0]);
        game.finishAnimation();
        expect(game.session.phase, TurnPhase.eventReveal);
        if (police) {
          final restored = GameController(
            session: GameSession.fromJson(game.session.toJson()),
            board: board,
          );
          addTearDown(restored.dispose);
          restored.dismissEventCard();
          expect(restored.session.phase, TurnPhase.jailChoice);
          restored.choosePolicePenalty(payFine: true);
          expect(restored.session.players.first.cash, 80);
          expect(restored.session.players.first.position, 2);
        } else {
          expect(game.session.players.first.position, 0);
          game.dismissEventCard();
          expect(game.session.phase, TurnPhase.handoff);
        }
      },
    );
  }
}
