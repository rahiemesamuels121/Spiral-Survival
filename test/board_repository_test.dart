import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';
import 'package:spiral_pass_play/features/game/data/board_repository.dart';
import 'package:spiral_pass_play/features/game/domain/board_definition.dart';
import 'package:spiral_pass_play/features/game/vector/board_artwork.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() {
    SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.empty();
  });
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
      for (final index in [62, 65, 68, 70, 76, 103, 104, 105, 106, 107]) {
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
}
