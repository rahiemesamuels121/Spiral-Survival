import 'package:flutter_test/flutter_test.dart';
import 'package:spiral_pass_play/features/game/data/board_repository.dart';
import 'package:spiral_pass_play/features/game/application/game_controller.dart';
import 'package:spiral_pass_play/features/game/domain/board_definition.dart';
import 'package:spiral_pass_play/features/game/domain/game_session.dart';

BoardDefinition _board({
  List<int> portals = const [2, 6, 10],
  int? police,
  int? jail,
  int? event,
}) => BoardDefinition([
  for (var i = 0; i <= 12; i++)
    BoardTile(
      index: i,
      x: i / 12,
      y: 0,
      type: i == 0
          ? TileType.start
          : i == 12
          ? TileType.finish
          : portals.contains(i)
          ? TileType.portal
          : i == police
          ? TileType.police
          : i == jail
          ? TileType.jail
          : i == event
          ? TileType.event
          : TileType.normal,
    ),
]);
GameController _game(BoardDefinition board, int from, {List<String>? deck}) {
  final game = GameController.newGame(
    names: ['One', 'Two'],
    colors: [1, 2],
    board: board,
    diceRoller: () => 1,
    eventCardOrder: deck,
  );
  game.session.currentPlayer.position = from;
  addTearDown(game.dispose);
  return game;
}

void _choose(GameController game, int direction) =>
    game.choosePortalCard(game.session.portalCardDirections.indexOf(direction));
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'Former spiral at 25 offers mystery cards and is a portal destination',
    () async {
      final board = await const BoardRepository().loadReferenceBoard();
      final game = _game(board, 24);
      expect(board.tiles[25].type, TileType.portal);
      game.roll();
      game.finishAnimation();
      expect(game.session.phase, TurnPhase.portalChoice);
      expect(game.session.portalCardDirections, containsAll([-1, 1]));
      _choose(game, 1);
      expect(game.session.players.first.position, 55);
    },
  );
  test(
    'Legacy spiral labels, artwork, and types become portals; START stays START',
    () {
      for (final fields in [
        {'type': 'normal', 'label': 'SPIRAL'},
        {'type': 'normal', 'artwork': 'spiral'},
        {'type': 'spiral'},
      ]) {
        final tile = BoardTile.fromJson({
          'index': 1,
          'x': .5,
          'y': .5,
          'destination': 5,
          ...fields,
        });
        expect(tile.type, TileType.portal);
        expect(tile.label, 'PORTAL');
        expect(tile.artwork, 'portal');
        expect(tile.destination, isNull);
        expect(tile.toJson()['type'], 'portal');
      }
      expect(
        BoardTile.fromJson({
          'index': 0,
          'x': 0,
          'y': 0,
          'type': 'start',
          'label': 'START · SPIRAL',
        }).type,
        TileType.start,
      );
    },
  );

  for (final direction in [-1, 1]) {
    test(
      'Mystery card $direction travels to the closest portal in that direction',
      () {
        final game = _game(_board(), 5);
        expect(game.roll()!.path, [6]);
        expect(game.session.currentPlayer.position, 6);
        game.finishAnimation();
        expect(game.session.phase, TurnPhase.portalChoice);
        expect(game.session.portalCardDirections.toSet(), {-1, 1});
        expect(game.beginDiceRoll(), isNull);
        game.dismissTileSummary();
        expect(game.session.phase, TurnPhase.portalChoice);
        _choose(game, direction);
        final destination = direction < 0 ? 2 : 10;
        expect(game.session.currentPlayer.position, destination);
        expect(game.lastOutcome!.path, [destination]);
        game.choosePortalCard(0); // Ignore a second tap.
        expect(game.session.currentPlayer.position, destination);
        game.finishAnimation();
        expect(game.session.phase, TurnPhase.specialReview);
        expect(game.session.pendingPortalTile, isNull);
        game.dismissTileSummary();
        expect(game.session.phase, TurnPhase.handoff);
      },
    );
  }
  test('First portal backwards card falls back to forwards', () {
    final game = _game(_board(), 1);
    game.roll();
    game.finishAnimation();
    _choose(game, -1);
    expect(game.session.currentPlayer.position, 6);
    expect(game.session.message, contains('other direction'));
  });
  test('Last portal forwards card falls back to backwards', () {
    final game = _game(_board(), 9);
    game.roll();
    game.finishAnimation();
    _choose(game, 1);
    expect(game.session.currentPlayer.position, 6);
    expect(game.session.message, contains('other direction'));
  });
  test('The same hidden card order survives resume without reshuffling', () {
    final game = _game(_board(), 5);
    game.roll();
    game.finishAnimation();
    final order = game.session.portalCardDirections.toList();
    final restored = GameController(
      session: GameSession.fromJson(game.session.toJson()),
      board: game.board,
    );
    addTearDown(restored.dispose);
    expect(restored.session.phase, TurnPhase.portalChoice);
    expect(restored.session.portalCardDirections, order);
    restored.choosePortalCard(0);
    expect(restored.session.currentPlayer.position, order[0] == -1 ? 2 : 10);
  });

  test(
    'A selected card stays committed if travel animation is interrupted',
    () {
      final game = _game(_board(), 5);
      game.roll();
      game.finishAnimation();
      _choose(game, 1);
      expect(game.session.phase, TurnPhase.portalTravel);
      final restored = GameController(
        session: GameSession.fromJson(game.session.toJson()),
        board: game.board,
      );
      addTearDown(restored.dispose);
      expect(restored.session.phase, TurnPhase.specialReview);
      expect(restored.session.currentPlayer.position, 10);
      restored.choosePortalCard(0);
      expect(restored.session.currentPlayer.position, 10);
      expect(restored.session.pendingPortalTile, isNull);
    },
  );
  test(
    'A single-portal board safely stays in place after a card is selected',
    () {
      final game = _game(_board(portals: [6]), 5);
      game.roll();
      game.finishAnimation();
      _choose(game, 1);
      expect(game.session.currentPlayer.position, 6);
      expect(game.session.phase, TurnPhase.specialReview);
      game.dismissTileSummary();
      expect(game.session.phase, TurnPhase.handoff);
    },
  );
  test('Event movement reveals its event before offering portal cards', () {
    final game = _game(
      _board(portals: [2, 8], event: 5),
      4,
      deck: ['backward_2'],
    );
    // Change the move card destination to a portal at 3.
    final tiles = game.board.tiles.toList();
    tiles[3] = tiles[3].withChanges({'type': 'portal'});
    final eventGame = _game(BoardDefinition(tiles), 4, deck: ['backward_2']);
    eventGame.roll();
    eventGame.finishAnimation();
    expect(eventGame.session.phase, TurnPhase.eventReveal);
    final restored = GameController(
      session: GameSession.fromJson(eventGame.session.toJson()),
      board: eventGame.board,
    );
    addTearDown(restored.dispose);
    restored.dismissEventCard();
    expect(restored.session.phase, TurnPhase.portalChoice);
    _choose(restored, 1);
    expect(restored.session.currentPlayer.position, 8);
  });
  test(
    'A risky portal arrival still triggers police and animates through both destinations',
    () {
      final game = _game(_board(police: 11, jail: 9), 5);
      game.session.currentPlayer.inventory.stabbers = 1;
      game.roll();
      game.finishAnimation();
      expect(game.session.phase, TurnPhase.portalChoice);
      _choose(game, 1);
      expect(game.lastOutcome!.path, [10, 9]);
      expect(game.session.currentPlayer.inventory.hasWeapons, isFalse);
      expect(game.session.currentPlayer.position, 9);
      game.finishAnimation();
      expect(game.session.phase, TurnPhase.jailChoice);
    },
  );
  test('Invalid card indices and malformed saves cannot bypass the choice', () {
    final game = _game(_board(), 5);
    game.roll();
    game.finishAnimation();
    game.choosePortalCard(-1);
    game.choosePortalCard(2);
    expect(game.session.phase, TurnPhase.portalChoice);
    final bad = game.session.toJson();
    bad['portalCardDirections'] = [-1, -1];
    expect(() => GameSession.fromJson(bad), throwsFormatException);
  });
}
