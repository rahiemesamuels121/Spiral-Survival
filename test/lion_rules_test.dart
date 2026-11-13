import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';
import 'package:spiral_pass_play/features/game/application/game_controller.dart';
import 'package:spiral_pass_play/features/game/data/board_repository.dart';
import 'package:spiral_pass_play/features/game/domain/board_definition.dart';
import 'package:spiral_pass_play/features/game/domain/game_session.dart';
import 'package:spiral_pass_play/features/game/domain/player_inventory.dart';
import 'package:spiral_pass_play/features/game/vector/board_artwork.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  Future<GameController> gameAt(int position) async {
    final board = await const BoardRepository().loadReferenceBoard();
    final game = GameController.newGame(
      names: ['One', 'Two'],
      colors: [1, 2],
      board: board,
      diceRoller: () => 1,
    );
    game.session.players.first.position = position;
    addTearDown(game.dispose);
    return game;
  }

  test(
    'Tile 78 collects raw meat, persists it, and preserves confusion at 102',
    () async {
      final game = await gameAt(77);
      expect(game.board.tiles[78].type, TileType.rawMeat);
      expect(game.board.tiles[102].type, TileType.confusion);
      game.roll();
      expect(game.session.players.first.inventory.rawMeat, 1);
      game.finishAnimation();
      expect(game.session.phase, TurnPhase.specialReview);
      final restored = GameSession.fromJson(game.session.toJson());
      expect(restored.players.first.inventory.rawMeat, 1);
      expect(
        game.session.tileSummary!.changes,
        contains('Raw meat: +1 (0 → 1)'),
      );
    },
  );
  for (final lion in [103, 104, 105, 106, 107]) {
    test('Lion $lion sends a player without meat to hospital', () async {
      final game = await gameAt(lion - 1);
      game.session.players.first.cash = 50;
      final outcome = game.roll()!;
      expect(game.board.tiles[lion].type, TileType.lion);
      expect(outcome.path, [lion, 62]);
      expect(game.session.players.first.position, 62);
      expect(game.session.players.first.skipTurns, 0);
      expect(game.session.players.first.cash, 50);
      expect(game.session.tileSummary!.message, contains('HOSPITAL'));
    });
    test('Lion $lion consumes one meat and lets the player stay', () async {
      final game = await gameAt(lion - 1);
      game.session.players.first.inventory.rawMeat = 2;
      expect(game.roll()!.path, [lion]);
      expect(game.session.players.first.position, lion);
      expect(game.session.players.first.inventory.rawMeat, 1);
    });
  }
  test('A forced landing on a lion also applies the hospital rule', () async {
    final game = await gameAt(100);
    final tiles = game.board.tiles.toList();
    tiles[101] = tiles[101].withChanges({'type': 'moveForward', 'amount': 2});
    final forced = GameController(
      session: game.session,
      board: BoardDefinition(tiles, id: game.board.id),
      diceRoller: () => 1,
    );
    addTearDown(forced.dispose);
    expect(forced.roll()!.path, [101, 103, 62]);
  });
  test('Legacy inventory has no meat and negative meat is rejected', () {
    expect(PlayerInventory.fromJson({}).rawMeat, 0);
    expect(() => PlayerInventory(rawMeat: -1), throwsArgumentError);
  });
  test(
    'Every tile uses equal square geometry including legacy custom sizes',
    () async {
      final board = await const BoardRepository().loadReferenceBoard();
      for (final tile in board.tiles) {
        expect(BoardArtwork.tileSize(tile), const Size.square(50));
        expect(
          BoardArtwork.tileSize(
            tile.withChanges({'width': .12, 'height': .04}),
          ),
          const Size.square(50),
        );
      }
    },
  );
  test(
    'Saved boards receive lion rules once and preserve subsequent edits',
    () async {
      SharedPreferencesAsyncPlatform.instance =
          InMemorySharedPreferencesAsync.empty();
      const repository = BoardRepository();
      final board = await repository.loadReferenceBoard();
      final tiles = board.tiles.toList();
      tiles[78] = tiles[78].withChanges({'type': 'normal', 'label': ''});
      for (var i = 103; i <= 107; i++) {
        tiles[i] = tiles[i].withChanges({
          'type': 'normal',
          'destination': null,
        });
      }
      final raw = jsonEncode({
        ...BoardDefinition(tiles).toJson(),
        'hospitalRulesRevision': 1,
        'confusionRulesRevision': 1,
      });
      final preferences = SharedPreferencesAsync();
      await preferences.setString(BoardRepository.customBoardKey, raw);
      final upgraded = await repository.loadBoard();
      expect(upgraded.tiles[78].type, TileType.rawMeat);
      expect(upgraded.tiles[103].type, TileType.lion);
      expect(
        await preferences.getString(BoardRepository.lionRulesBackupKey),
        raw,
      );
      final edited = upgraded.tiles.toList();
      edited[78] = edited[78].withChanges({'type': 'normal'});
      await repository.saveBoard(BoardDefinition(edited));
      expect((await repository.loadBoard()).tiles[78].type, TileType.normal);
    },
  );
}
