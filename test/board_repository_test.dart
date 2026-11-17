import 'dart:convert';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';
import 'package:spiral_pass_play/features/game/application/game_controller.dart';
import 'package:spiral_pass_play/features/game/data/board_repository.dart';
import 'package:spiral_pass_play/features/game/domain/board_definition.dart';
import 'package:spiral_pass_play/features/game/domain/game_session.dart';
import 'package:spiral_pass_play/features/game/vector/board_artwork.dart';

class _BoardBundle extends CachingAssetBundle {
  _BoardBundle(this.board);
  final Map<String, dynamic> board;
  @override
  Future<ByteData> load(String key) async =>
      ByteData.sublistView(Uint8List.fromList(utf8.encode(jsonEncode(board))));
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() {
    SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.empty();
  });
  for (final customized in [false, true]) {
    test(
      'Secret Society migration preserves customized spaces ($customized)',
      () async {
        final data =
            jsonDecode(await rootBundle.loadString(BoardRepository.assetPath))
                as Map<String, dynamic>;
        data.remove('secretSocietyRevision');
        (data['tiles'] as List)[60]['type'] = customized ? 'cash' : 'normal';
        (data['tiles'] as List)[60]['label'] = customized ? 'CUSTOM CASH' : '';
        (data['tiles'] as List)[60]['amount'] = customized ? 75 : 0;
        final prefs = SharedPreferencesAsync();
        await prefs.setString(BoardRepository.customBoardKey, jsonEncode(data));
        final board = await const BoardRepository().loadBoard();
        expect(
          board.tiles[60].type,
          customized ? TileType.cash : TileType.secretSociety,
        );
        expect(board.id, data['id']);
        expect(
          await prefs.getString('spiral_custom_board_before_secret_society'),
          isNotNull,
        );
        final saved = await prefs.getString(BoardRepository.customBoardKey);
        await const BoardRepository().loadBoard();
        expect(await prefs.getString(BoardRepository.customBoardKey), saved);
      },
    );
  }

  test(
    'Helper board revisions are used online while local saves keep their ID',
    () async {
      final reference = await const BoardRepository().loadReferenceBoard();
      final data = reference.toJson()
        ..['onlineBoardId'] = 'spiral-quest-board-abc123def456';
      final repository = BoardRepository(bundle: _BoardBundle(data));
      expect(
        (await repository.loadOnlineBoard()).id,
        'spiral-quest-board-abc123def456-characters-v3',
      );
      expect((await repository.loadReferenceBoard()).id, reference.id);
      final invalid = reference.toJson()
        ..['onlineBoardId'] = '../invalid revision';
      await expectLater(
        BoardRepository(bundle: _BoardBundle(invalid)).loadOnlineBoard(),
        throwsFormatException,
      );
    },
  );

  test(
    'Online board revisions keep offline save identities compatible',
    () async {
      const repository = BoardRepository();
      final local = await repository.loadReferenceBoard();
      final online = await repository.loadOnlineBoard();
      expect(local.id, 'survive-spiral-draft-v2');
      final source =
          jsonDecode(await rootBundle.loadString(BoardRepository.assetPath))
              as Map<String, dynamic>;
      expect(
        online.id,
        "${source['onlineBoardId'] ?? 'spiral-quest-board-v4'}-characters-v3",
      );
      expect(online.id, isNot(local.id));
      expect(online.tiles[85].type, TileType.mine);
      expect(online.tiles[110].type, TileType.normal);
    },
  );

  test(
    'Saved boards swap mine contents once and preserve tile positions',
    () async {
      const repository = BoardRepository();
      final reference = await repository.loadReferenceBoard();
      final saved = await repository.saveBoard(reference);
      final prefs = SharedPreferencesAsync();
      final data =
          jsonDecode((await prefs.getString(BoardRepository.customBoardKey))!)
              as Map<String, dynamic>;
      data.remove('mineSwapRevision');
      final tiles = data['tiles'] as List;
      tiles[85]['type'] = 'normal';
      tiles[85]['label'] = '';
      tiles[110]['type'] = 'mine';
      tiles[110]['label'] = 'MINE';
      await prefs.setString(BoardRepository.customBoardKey, jsonEncode(data));
      final upgraded = await repository.loadBoard();
      expect(upgraded.id, saved.id);
      expect(upgraded.tiles[85].type, TileType.mine);
      expect(upgraded.tiles[110].type, TileType.normal);
      expect(upgraded.tiles[85].x, reference.tiles[85].x);
      expect(upgraded.tiles[110].y, reference.tiles[110].y);
      final reloaded = await repository.loadBoard();
      expect(reloaded.tiles[85].type, TileType.mine);
      expect(reloaded.tiles[110].type, TileType.normal);
    },
  );

  test(
    'Saved board keeps artwork and rules and receives a new match identity',
    () async {
      const repository = BoardRepository();
      final original = await repository.loadBoard();
      final tiles = original.tiles.toList();
      tiles[10] = tiles[10].withChanges({
        'label': 'CURE & <GO>',
        'amount': 2,
        'fillColor': 0xFF123456,
        'artwork': 'antidote',
        'width': .067,
        'height': .063,
      });
      final saved = await repository.saveBoard(
        BoardDefinition(tiles, id: original.id),
      );
      final loaded = await repository.loadBoard();
      expect(saved.id, isNot(original.id));
      expect(loaded.id, saved.id);
      expect(loaded.tiles[10].toJson(), tiles[10].toJson());
      expect(loaded.tiles[10].type, TileType.antidote);
      final svg = BoardArtwork(loaded).scene.toSvg();
      expect(RegExp(r'<g id="tile-\d+">').allMatches(svg).length, 120);
      expect(svg, contains('#123456'));
      expect(svg, isNot(contains('<image')));
      expect(svg, isNot(contains('base64')));
      final normal = loaded.tiles[1].withChanges({'label': 'A & <B>'});
      final specialTiles = loaded.tiles.toList()..[1] = normal;
      expect(
        BoardArtwork(BoardDefinition(specialTiles)).scene.toSvg(),
        contains('A &amp; &lt;B&gt;'),
      );
      expect(
        BoardDefinition.fromJson(
          jsonDecode(jsonEncode(loaded.toJson())),
        ).tiles[10].amount,
        2,
      );
    },
  );

  test('Invalid edited links and sizes cannot be played or saved', () async {
    final board = await const BoardRepository().loadReferenceBoard();
    final tiles = board.tiles.toList();
    tiles[20] = tiles[20].withChanges({'destination': 1});
    expect(() => BoardDefinition(tiles), throwsArgumentError);
    tiles[20] = board.tiles[20].withChanges({'width': -1});
    expect(() => BoardDefinition(tiles), throwsArgumentError);
  });

  test('Legacy death tiles load as sea and export with the new type', () {
    final tile = BoardTile.fromJson({
      'index': 4,
      'x': .05,
      'y': .37,
      'type': 'death',
      'label': 'INSTANT DEATH · RETURN TO START',
    });
    expect(tile.type, TileType.sea);
    expect(tile.label, 'SEA');
    expect(tile.toJson()['type'], 'sea');
  });

  test(
    'Older saved designs receive hospital rules once without losing their layout',
    () async {
      const repository = BoardRepository();
      final reference = await repository.loadReferenceBoard();
      final tiles = reference.tiles.toList();
      for (final tile
          in tiles.where((tile) => tile.type == TileType.mine).toList()) {
        tiles[tile.index] = tile.withChanges({
          'mineColor': 'red',
          'destination': null,
        });
      }
      for (final index in [62, 65, 68, 70, 76, 103, 104, 105, 106, 107, 112]) {
        tiles[index] = tiles[index].withChanges({
          'type': 'normal',
          'destination': null,
          'label': 'OLD',
          'x': .4,
          'fillColor': 0xFF123456,
        });
      }
      final original = jsonEncode({
        ...BoardDefinition(tiles, id: 'saved-design').toJson(),
        'layoutRevision': 1,
      });
      final preferences = SharedPreferencesAsync();
      await preferences.setString(BoardRepository.customBoardKey, original);
      final upgraded = await repository.loadBoard();
      expect(upgraded.id, 'saved-design');
      expect(upgraded.tiles[62].type, TileType.hospital);
      expect(upgraded.tiles[65].type, TileType.trapDoor);
      expect(upgraded.tiles[76].type, TileType.fire);
      expect(upgraded.tiles[107].type, TileType.normal);
      expect(upgraded.tiles[100].type, TileType.normal);
      expect(upgraded.tiles[78].amount, 3);
      expect(upgraded.tiles[65].destination, 62);
      expect(upgraded.tiles[65].x, .4);
      expect(upgraded.tiles[65].fillColor, 0xFF123456);
      expect(
        await preferences.getString(BoardRepository.hospitalRulesBackupKey),
        original,
      );
      final revised = upgraded.tiles.toList();
      revised[65] = revised[65].withChanges({
        'type': 'normal',
        'label': 'MY EDIT',
        'destination': null,
      });
      await repository.saveBoard(BoardDefinition(revised));
      final reloaded = await repository.loadBoard();
      expect(reloaded.tiles[65].type, TileType.normal);
      expect(reloaded.tiles[65].label, 'MY EDIT');
    },
  );

  test(
    'Saved boards balance the final lion and snake mine once without changing layout',
    () async {
      const repository = BoardRepository();
      final reference = await repository.loadReferenceBoard();
      final saved = await repository.saveBoard(reference);
      final preferences = SharedPreferencesAsync();
      final data =
          jsonDecode(
                (await preferences.getString(BoardRepository.customBoardKey))!,
              )
              as Map<String, dynamic>;
      data.remove('lionMineBalanceRevision');
      final tiles = data['tiles'] as List;
      tiles[78]['amount'] = 1;
      tiles[107].addAll({
        'type': 'lion',
        'label': 'LION',
        'amount': 2,
        'destination': 62,
        'consumesAntidote': true,
        'artwork': 'lion',
        'x': .321,
        'y': .456,
        'width': .071,
        'height': .067,
        'segment': 'custom-leg',
        'fillColor': 0xFF123456,
        'textColor': 0xFFABCDEF,
      });
      tiles[100].addAll({
        'type': 'mine',
        'label': 'MINE',
        'amount': 4,
        'destination': 0,
        'consumesAntidote': true,
        'artwork': 'mine',
        'fillColor': 0xFF654321,
      });
      tiles[16]['label'] = 'MY UNRELATED TILE';
      final original = jsonEncode(data);
      await preferences.setString(BoardRepository.customBoardKey, original);
      final upgraded = await repository.loadBoard();
      expect(upgraded.id, saved.id);
      expect(upgraded.tiles[78].type, TileType.rawMeat);
      expect(upgraded.tiles[78].amount, 3);
      for (final index in [100, 107]) {
        final tile = upgraded.tiles[index];
        expect(tile.type, TileType.normal);
        expect(tile.label, '');
        expect(tile.amount, 0);
        expect(tile.destination, isNull);
        expect(tile.consumesAntidote, isFalse);
        expect(tile.artwork, isNull);
      }
      final moved = upgraded.tiles[107];
      expect(moved.x, .321);
      expect(moved.y, .456);
      expect(moved.width, .071);
      expect(moved.height, .067);
      expect(moved.segment, 'custom-leg');
      expect(moved.fillColor, 0xFF123456);
      expect(moved.textColor, 0xFFABCDEF);
      expect(upgraded.tiles[100].fillColor, 0xFF654321);
      expect(upgraded.tiles[16].label, 'MY UNRELATED TILE');
      expect(
        await preferences.getString(BoardRepository.lionMineBalanceBackupKey),
        original,
      );
      final migrated =
          jsonDecode(
                (await preferences.getString(BoardRepository.customBoardKey))!,
              )
              as Map<String, dynamic>;
      expect(migrated['lionMineBalanceRevision'], 1);
      final reloaded = await repository.loadBoard();
      expect(reloaded.toJson(), upgraded.toJson());
      expect(
        await preferences.getString(BoardRepository.lionMineBalanceBackupKey),
        original,
      );

      // New editor saves carry the revision even when the user deliberately
      // restores one of these hazards or changes the collection amount again.
      final edited = upgraded.tiles.toList();
      edited[107] = edited[107].withChanges({
        'type': 'lion',
        'label': 'MY LION',
        'destination': 62,
      });
      edited[100] = edited[100].withChanges({
        'type': 'mine',
        'label': 'MY MINE',
      });
      edited[78] = edited[78].withChanges({'amount': 9});
      final editorSave = await repository.saveBoard(BoardDefinition(edited));
      final afterEdit = await repository.loadBoard();
      expect(afterEdit.id, editorSave.id);
      expect(afterEdit.tiles[107].label, 'MY LION');
      expect(afterEdit.tiles[107].type, TileType.lion);
      expect(afterEdit.tiles[100].type, TileType.mine);
      expect(afterEdit.tiles[78].amount, 9);
      expect(
        await preferences.getString(BoardRepository.lionMineBalanceBackupKey),
        original,
      );
    },
  );

  test(
    'The balance migration respects tiles already replaced by custom rules',
    () async {
      const repository = BoardRepository();
      final reference = await repository.loadReferenceBoard();
      final changed = reference.tiles.toList();
      changed[107] = changed[107].withChanges({
        'type': 'cash',
        'label': 'MY BONUS',
        'amount': 37,
        'destination': null,
      });
      changed[100] = changed[100].withChanges({
        'type': 'normal',
        'label': 'MY SAFE SPACE',
        'artwork': 'boat',
      });
      changed[78] = changed[78].withChanges({
        'type': 'cash',
        'label': 'MY CASH',
        'amount': 17,
      });
      await repository.saveBoard(BoardDefinition(changed));
      final preferences = SharedPreferencesAsync();
      final data =
          jsonDecode(
                (await preferences.getString(BoardRepository.customBoardKey))!,
              )
              as Map<String, dynamic>;
      data.remove('lionMineBalanceRevision');
      await preferences.setString(
        BoardRepository.customBoardKey,
        jsonEncode(data),
      );
      final loaded = await repository.loadBoard();
      for (final index in [78, 100, 107]) {
        expect(loaded.tiles[index].toJson(), changed[index].toJson());
      }
    },
  );

  test(
    'Balanced normal spaces do not move players and meat grants three portions',
    () async {
      const repository = BoardRepository();
      final reference = await repository.loadReferenceBoard();
      final oldTiles = reference.tiles.toList();
      oldTiles[107] = oldTiles[107].withChanges({
        'type': 'lion',
        'label': 'LION',
        'destination': 62,
      });
      oldTiles[100] = oldTiles[100].withChanges({
        'type': 'mine',
        'label': 'MINE',
      });
      oldTiles[78] = oldTiles[78].withChanges({'amount': 1});
      await repository.saveBoard(BoardDefinition(oldTiles));
      final preferences = SharedPreferencesAsync();
      final data =
          jsonDecode(
                (await preferences.getString(BoardRepository.customBoardKey))!,
              )
              as Map<String, dynamic>;
      data.remove('lionMineBalanceRevision');
      await preferences.setString(
        BoardRepository.customBoardKey,
        jsonEncode(data),
      );
      final board = await repository.loadBoard();
      for (final index in [78, 100, 107]) {
        final game = GameController.newGame(
          names: ['One', 'Two'],
          colors: [1, 2],
          board: board,
          diceRoller: () => 1,
        );
        addTearDown(game.dispose);
        final player = game.session.currentPlayer;
        player.position = index - 1;
        expect(game.roll()!.path, [index]);
        expect(player.position, index);
        expect(player.isInjured, isFalse);
        expect(player.inventory.rawMeat, index == 78 ? 3 : 0);
        game.finishAnimation();
        if (index == 78) game.dismissTileSummary();
        expect(game.session.phase, TurnPhase.handoff);
      }
    },
  );
  test('Saved mine colors swap once and preserve subsequent edits', () async {
    const repository = BoardRepository();
    final reference = await repository.loadReferenceBoard();
    await repository.saveBoard(reference);
    final prefs = SharedPreferencesAsync();
    final data =
        jsonDecode((await prefs.getString(BoardRepository.customBoardKey))!)
            as Map<String, dynamic>;
    data['mineColorsRevision'] = 1;
    data['tiles'][85]['mineColor'] = 'blue';
    data['tiles'][98]['mineColor'] = 'green';
    await prefs.setString(BoardRepository.customBoardKey, jsonEncode(data));
    final upgraded = await repository.loadBoard();
    expect(upgraded.tiles[85].mineColor, MineColor.green);
    expect(upgraded.tiles[98].mineColor, MineColor.blue);
    expect(upgraded.tiles[109].mineColor, MineColor.red);
    final tiles = upgraded.tiles.toList();
    tiles[85] = tiles[85].withChanges({'mineColor': 'red'});
    await repository.saveBoard(BoardDefinition(tiles, id: upgraded.id));
    expect((await repository.loadBoard()).tiles[85].mineColor, MineColor.red);
  });
}
