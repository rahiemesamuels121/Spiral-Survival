import 'package:flutter_test/flutter_test.dart';
import 'package:spiral_pass_play/features/game/application/game_controller.dart';
import 'package:spiral_pass_play/features/game/data/board_repository.dart';
import 'package:spiral_pass_play/features/game/domain/board_definition.dart';
import 'package:spiral_pass_play/features/game/domain/game_session.dart';
import 'package:spiral_pass_play/features/game/vector/board_artwork.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  for (final index in [109, 110]) {
    test(
      'Mine $index restarts the player without a loan or debt change',
      () async {
        final board = await const BoardRepository().loadReferenceBoard();
        final game = GameController.newGame(
          names: ['One', 'Two'],
          colors: [1, 2],
          board: board,
          diceRoller: () => 1,
        );
        addTearDown(game.dispose);
        final player = game.session.currentPlayer;
        player.position = index - 1;
        player.cash = 70;
        player.debt = 15;
        player.inventory.boats = 1;
        player.inventory.antidotes = 1;
        final outcome = game.roll()!;
        expect(board.tiles[index].type, TileType.mine);
        expect(board.tiles[index].label, 'MINE');
        expect(outcome.path, [index, 0]);
        expect(player.position, 0);
        expect(player.cash, 70);
        expect(player.debt, 15);
        expect(player.inventory.boats, 1);
        expect(player.inventory.antidotes, 1);
        game.finishAnimation();
        expect(game.session.phase, TurnPhase.specialReview);
        expect(game.session.tileSummary!.finalPosition, 0);
        expect(game.session.tileSummary!.message, contains('you died'));
        expect(game.session.tileSummary!.title, 'MINE · YOU DIED');
        final restored = GameSession.fromJson(game.session.toJson());
        expect(restored.currentPlayer.position, 0);
        game.dismissTileSummary();
        expect(game.session.phase, TurnPhase.handoff);
      },
    );
  }
  test('Old loan JSON converts to mines with mine artwork', () {
    final mine = BoardTile.fromJson({
      'index': 1,
      'x': .2,
      'y': .2,
      'type': 'loan',
      'label': 'LOAN',
      'amount': 50,
      'artwork': 'loan',
    });
    expect(mine.type, TileType.mine);
    expect(mine.label, 'MINE');
    expect(mine.amount, 0);
    expect(mine.toJson()['type'], 'mine');
    expect(BoardArtwork.symbolFor(mine), 'mine');
  });
  test('Landing on a mine after forced movement still restarts', () {
    final board = BoardDefinition([
      const BoardTile(index: 0, x: 0, y: 0, type: TileType.start),
      const BoardTile(
        index: 1,
        x: .3,
        y: 0,
        type: TileType.moveForward,
        amount: 1,
      ),
      const BoardTile(index: 2, x: .6, y: 0, type: TileType.mine),
      const BoardTile(index: 3, x: 1, y: 0, type: TileType.finish),
    ]);
    final game = GameController.newGame(
      names: ['One', 'Two'],
      colors: [1, 2],
      board: board,
      diceRoller: () => 1,
    );
    addTearDown(game.dispose);
    final outcome = game.roll()!;
    expect(outcome.path, [1, 2, 0]);
    expect(outcome.landedType, TileType.mine);
    expect(game.session.tileSummary!.landedIndex, 2);
    expect(game.session.tileSummary!.title, 'MINE · YOU DIED');
    expect(game.session.currentPlayer.position, 0);
  });
}
