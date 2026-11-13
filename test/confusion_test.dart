import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';
import 'package:spiral_pass_play/features/game/application/game_controller.dart';
import 'package:spiral_pass_play/features/game/data/board_repository.dart';
import 'package:spiral_pass_play/features/game/domain/board_definition.dart';
import 'package:spiral_pass_play/features/game/domain/game_session.dart';
import 'package:spiral_pass_play/features/game/domain/player_state.dart';

BoardDefinition _board({int? confusion, int? sea, int finish = 100}) =>
    BoardDefinition([
      for (var i = 0; i <= finish; i++)
        BoardTile(
          index: i,
          x: i / finish,
          y: 0,
          type: i == 0
              ? TileType.start
              : i == finish
              ? TileType.finish
              : i == confusion
              ? TileType.confusion
              : i == sea
              ? TileType.sea
              : TileType.normal,
        ),
    ]);
GameController _game(BoardDefinition board, int from, List<int> rolls) {
  var index = 0;
  final game = GameController.newGame(
    names: ['One', 'Two'],
    colors: [1, 2],
    board: board,
    diceRoller: () => rolls[index++],
  );
  game.session.players.first.position = from;
  addTearDown(game.dispose);
  return game;
}

void _next(GameController game) {
  game.finishAnimation();
  if (game.session.phase == TurnPhase.specialReview) game.dismissTileSummary();
  game.acknowledgeHandoff();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('Former MOVE 2 tile gives confusion near the finish', () async {
    final board = await const BoardRepository().loadReferenceBoard();
    final game = _game(board, 117, [1]);
    expect(game.roll()!.path, [118]);
    expect(board.tiles[118].type, TileType.confusion);
    expect(board.tiles[118].label, 'CONFUSION');
    expect(game.session.currentPlayer.reverseNextMove, isTrue);
    expect(game.session.winnerId, isNull);
  });
  test('Tile 33 gives confusion instead of drawing a card', () async {
    final board = await const BoardRepository().loadReferenceBoard();
    final game = _game(board, 32, [1]);
    final deck = game.session.eventDrawPile.toList();
    expect(game.roll()!.path, [33]);
    expect(board.tiles[33].type, TileType.confusion);
    expect(board.tiles[33].label, 'CONFUSION');
    expect(game.session.players.first.reverseNextMove, isTrue);
    expect(game.session.pendingCardId, isNull);
    expect(game.session.eventDrawPile, deck);
    game.finishAnimation();
    expect(game.session.phase, TurnPhase.specialReview);
    expect(game.session.tileSummary!.changes, contains('Next move: BACKWARDS'));
  });
  test(
    'Only the affected player moves backwards next turn, then forwards again',
    () {
      final game = _game(_board(confusion: 87), 86, [1, 1, 3, 1, 2]);
      game.roll();
      _next(game);
      expect(game.session.currentPlayerIndex, 1);
      expect(game.roll()!.path, [1]);
      _next(game);
      expect(game.roll()!.path, [86, 85, 84]);
      expect(game.session.players.first.reverseNextMove, isFalse);
      _next(game);
      game.roll();
      _next(game);
      expect(game.roll()!.path, [85, 86]);
    },
  );
  test('Confusion persists across save/resume', () {
    final game = _game(_board(confusion: 87), 86, [1]);
    game.roll();
    game.finishAnimation();
    final restored = GameSession.fromJson(game.session.toJson());
    expect(restored.players.first.reverseNextMove, isTrue);
    expect(restored.phase, TurnPhase.specialReview);
    expect(
      PlayerState.fromJson({
        'id': 'old',
        'name': 'Old',
        'colorValue': 1,
      }).reverseNextMove,
      isFalse,
    );
  });
  test('Backwards movement still resolves a sea landing', () {
    final game = _game(_board(sea: 5, finish: 10), 8, [3]);
    game.session.currentPlayer.reverseNextMove = true;
    expect(game.roll()!.path, [7, 6, 5, 0]);
    expect(game.session.currentPlayer.position, 0);
    expect(game.session.currentPlayer.reverseNextMove, isFalse);
  });
  test(
    'Confusion near FINISH goes backwards even when roll exceeds remaining distance',
    () {
      final game = _game(_board(finish: 10), 9, [6]);
      game.session.currentPlayer.reverseNextMove = true;
      expect(game.roll()!.path, [8, 7, 6, 5, 4, 3]);
      expect(game.session.currentPlayer.position, 3);
      expect(game.session.winnerId, isNull);
    },
  );
  test('Backwards movement stops at START instead of going below zero', () {
    final game = _game(_board(finish: 10), 2, [6]);
    game.session.currentPlayer.reverseNextMove = true;
    expect(game.roll()!.path, [1, 0]);
    expect(game.session.currentPlayer.position, 0);
  });
  test('Landing on confusion again re-arms the effect', () {
    final game = _game(_board(confusion: 87), 90, [3]);
    game.session.currentPlayer.reverseNextMove = true;
    expect(game.roll()!.path, [89, 88, 87]);
    expect(game.session.currentPlayer.reverseNextMove, isTrue);
  });
  test('A missed turn does not consume the pending backwards move', () {
    final game = _game(_board(), 80, [1, 1, 2]);
    game.session.currentPlayerIndex = 1;
    game.session.players.first.reverseNextMove = true;
    game.session.players.first.skipTurns = 1;
    game.roll();
    _next(game);
    expect(game.session.currentPlayerIndex, 1);
    expect(game.session.players.first.reverseNextMove, isTrue);
    game.roll();
    _next(game);
    expect(game.session.currentPlayerIndex, 0);
    expect(game.roll()!.path, [79, 78]);
  });
  test(
    'Older saved boards migrate confusion to tile 102 once and preserve later edits',
    () async {
      SharedPreferencesAsyncPlatform.instance =
          InMemorySharedPreferencesAsync.empty();
      const repository = BoardRepository();
      final original = await repository.loadReferenceBoard();
      final tiles = original.tiles.toList();
      tiles[87] = tiles[87].withChanges({
        'type': 'event',
        'label': 'RAW DEAL',
        'artwork': 'dice',
        'fillColor': 0xFF123456,
      });
      final raw = jsonEncode({
        ...BoardDefinition(tiles, id: 'custom-old').toJson(),
        'hospitalRulesRevision': 1,
      });
      final preferences = SharedPreferencesAsync();
      await preferences.setString(BoardRepository.customBoardKey, raw);
      final upgraded = await repository.loadBoard();
      expect(upgraded.id, 'custom-old');
      expect(upgraded.tiles[102].type, TileType.confusion);
      expect(upgraded.tiles[102].label, 'CONFUSION');
      expect(upgraded.tiles[87].fillColor, 0xFF123456);
      expect(
        await preferences.getString(BoardRepository.confusionRulesBackupKey),
        raw,
      );
      final edited = upgraded.tiles.toList();
      edited[87] = edited[87].withChanges({
        'type': 'normal',
        'label': 'MY EDIT',
      });
      await repository.saveBoard(BoardDefinition(edited));
      expect((await repository.loadBoard()).tiles[87].type, TileType.normal);
    },
  );
}
