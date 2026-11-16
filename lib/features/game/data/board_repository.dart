import 'dart:convert';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../domain/board_definition.dart';

class BoardRepository {
  const BoardRepository({this.bundle});
  final AssetBundle? bundle;

  static const assetPath = 'assets/boards/spiral_board_map.json';
  static const customBoardKey = 'spiral_custom_vector_board_v1';
  static const hospitalRulesBackupKey =
      'spiral_custom_board_before_hospital_rules';
  static const confusionRulesBackupKey =
      'spiral_custom_board_before_confusion_rules';

  static const lionRulesBackupKey = 'spiral_custom_board_before_lion_rules';
  static const lionMineBalanceBackupKey =
      'spiral_custom_board_before_lion_mine_balance';

  static const _revisions = {
    'hospitalRulesRevision': 1,
    'confusionRulesRevision': 1,
    'lionRulesRevision': 1,
    'lateTrapsRevision': 1,
    'carLotPortalRevision': 1,
    'layoutRevision': 1,
    'finishConfusionRevision': 1,
    'lastJailsRevision': 1,
    'mineSwapRevision': 1,
    'snakeStarRevision': 1,
    'lionMineBalanceRevision': 1,
    'mineColorsRevision': 2,
  };

  static String _encodeBoard(BoardDefinition board) =>
      jsonEncode({...board.toJson(), ..._revisions});

  Future<BoardDefinition> loadBoard() async {
    final preferences = SharedPreferencesAsync();
    final saved = await preferences.getString(customBoardKey);
    if (saved != null) {
      final data = Map<String, dynamic>.from(jsonDecode(saved) as Map);
      var board = BoardDefinition.fromJson(data);
      var changed = false;
      if (data['hospitalRulesRevision'] == null && board.tiles.length == 120) {
        final tiles = board.tiles.toList();
        tiles[62] = tiles[62].withChanges({
          'type': 'hospital',
          'label': 'HOSPITAL',
          'amount': 0,
          'destination': null,
          'artwork': null,
        });
        for (final index in [65, 68, 70, 76]) {
          tiles[index] = tiles[index].withChanges({
            'type': index == 76 ? 'fire' : 'trapDoor',
            'label': index == 76 ? 'FIRE' : 'TRAP DOOR',
            'amount': 0,
            'destination': 62,
            'artwork': null,
          });
        }
        final hospitalBoard = BoardDefinition(tiles, id: board.id);
        if (await preferences.getString(hospitalRulesBackupKey) == null) {
          await preferences.setString(hospitalRulesBackupKey, saved);
        }
        changed = true;
        board = hospitalBoard;
        data['hospitalRulesRevision'] = 1;
      }
      if (data['confusionRulesRevision'] == null && board.tiles.length == 120) {
        final tiles = board.tiles.toList();
        tiles[87] = tiles[87].withChanges({
          'type': 'confusion',
          'label': 'CONFUSION',
          'amount': 0,
          'destination': null,
          'artwork': null,
        });
        board = BoardDefinition(tiles, id: board.id);
        if (await preferences.getString(confusionRulesBackupKey) == null) {
          await preferences.setString(confusionRulesBackupKey, saved);
        }
        changed = true;
      }
      if (data['lionRulesRevision'] == null && board.tiles.length == 120) {
        final tiles = board.tiles.toList();
        tiles[78] = tiles[78].withChanges({
          'type': 'rawMeat',
          'label': 'RAW MEAT',
          'amount': 1,
          'destination': null,
          'artwork': null,
        });
        for (var index = 103; index <= 107; index++) {
          tiles[index] = tiles[index].withChanges({
            'type': 'lion',
            'label': 'LION',
            'amount': 0,
            'destination': 62,
            'artwork': null,
          });
        }
        board = BoardDefinition(tiles, id: board.id);
        if (await preferences.getString(lionRulesBackupKey) == null) {
          await preferences.setString(lionRulesBackupKey, saved);
        }
        changed = true;
      }
      if (data['lateTrapsRevision'] == null && board.tiles.length == 120) {
        final tiles = board.tiles.toList();
        final at87 = tiles[87].toJson();
        final at102 = tiles[102].toJson();
        const contents = [
          'type',
          'label',
          'amount',
          'destination',
          'artwork',
          'consumesAntidote',
          'mineColor',
        ];
        tiles[87] = tiles[87].withChanges({
          for (final key in contents) key: at102[key],
        });
        tiles[102] = tiles[102].withChanges({
          for (final key in contents) key: at87[key],
        });
        for (final index in [33, 98, 99, 100, 101]) {
          tiles[index] = tiles[index].withChanges({
            'type': index == 33 ? 'confusion' : 'mine',
            'mineColor': 'red',
            'label': index == 33 ? 'CONFUSION' : 'MINE',
            'amount': 0,
            'destination': null,
            'artwork': null,
          });
        }
        board = BoardDefinition(tiles, id: board.id);
        if (await preferences.getString(
              'spiral_custom_board_before_late_traps',
            ) ==
            null) {
          await preferences.setString(
            'spiral_custom_board_before_late_traps',
            saved,
          );
        }
        changed = true;
      }
      if (data['carLotPortalRevision'] == null && board.tiles.length == 120) {
        final tiles = board.tiles.toList();
        tiles[55] = tiles[55].withChanges({
          'type': 'portal',
          'label': 'PORTAL',
          'amount': 0,
          'destination': null,
          'artwork': null,
        });
        board = BoardDefinition(tiles, id: board.id);
        if (await preferences.getString(
              'spiral_custom_board_before_car_lot_portal',
            ) ==
            null) {
          await preferences.setString(
            'spiral_custom_board_before_car_lot_portal',
            saved,
          );
        }
        changed = true;
      }
      if (data['layoutRevision'] == null && board.tiles.length == 120) {
        final reference = await loadReferenceBoard();
        final tiles = [
          for (var i = 0; i < board.tiles.length; i++)
            board.tiles[i].withChanges({
              'x': reference.tiles[i].x,
              'y': reference.tiles[i].y,
              'segment': reference.tiles[i].segment,
            }),
        ];
        board = BoardDefinition(tiles, id: board.id);
        if (await preferences.getString(
              'spiral_custom_board_before_grid_layout',
            ) ==
            null) {
          await preferences.setString(
            'spiral_custom_board_before_grid_layout',
            saved,
          );
        }
        changed = true;
      }
      if (data['finishConfusionRevision'] == null &&
          board.tiles.length == 120) {
        final tiles = board.tiles.toList();
        tiles[118] = tiles[118].withChanges({
          'type': 'confusion',
          'label': 'CONFUSION',
          'amount': 0,
          'destination': null,
          'artwork': null,
        });
        board = BoardDefinition(tiles, id: board.id);
        if (await preferences.getString(
              'spiral_custom_board_before_finish_confusion',
            ) ==
            null) {
          await preferences.setString(
            'spiral_custom_board_before_finish_confusion',
            saved,
          );
        }
        changed = true;
      }
      if (data['lastJailsRevision'] == null && board.tiles.length == 120) {
        final tiles = board.tiles.toList();
        for (final index in [111, 115]) {
          tiles[index] = tiles[index].withChanges({
            'type': 'normal',
            'label': '',
            'amount': 0,
            'destination': null,
            'artwork': null,
          });
        }
        board = BoardDefinition(tiles, id: board.id);
        if (await preferences.getString(
              'spiral_custom_board_before_last_jails',
            ) ==
            null) {
          await preferences.setString(
            'spiral_custom_board_before_last_jails',
            saved,
          );
        }
        changed = true;
      }
      if (data['mineSwapRevision'] == null && board.tiles.length == 120) {
        final tiles = board.tiles.toList();
        final old85 = tiles[85].toJson();
        final old110 = tiles[110].toJson();
        const contents = [
          'type',
          'label',
          'amount',
          'destination',
          'consumesAntidote',
          'artwork',
          'fillColor',
          'textColor',
        ];
        tiles[85] = tiles[85].withChanges({
          for (final key in contents) key: old110[key],
        });
        tiles[110] = tiles[110].withChanges({
          for (final key in contents) key: old85[key],
        });
        board = BoardDefinition(tiles, id: board.id);
        const backupKey = 'spiral_custom_board_before_mine_swap';
        if (await preferences.getString(backupKey) == null) {
          await preferences.setString(backupKey, saved);
        }
        changed = true;
      }
      if (data['snakeStarRevision'] == null && board.tiles.length == 120) {
        final tiles = board.tiles.toList();
        tiles[87] = tiles[87].withChanges({
          'type': 'snake',
          'label': 'SNAKE',
          'amount': 0,
          'destination': 10,
          'consumesAntidote': true,
          'artwork': null,
        });
        tiles[89] = tiles[89].withChanges({
          'type': 'star',
          'label': 'STAR',
          'amount': 1,
          'destination': null,
          'consumesAntidote': false,
          'artwork': null,
        });
        board = BoardDefinition(tiles, id: board.id);
        const backupKey = 'spiral_custom_board_before_snake_star';
        if (await preferences.getString(backupKey) == null) {
          await preferences.setString(backupKey, saved);
        }
        changed = true;
      }
      // Apply this after the older hazard migrations so they cannot restore
      // the final lion or the mine immediately after the last snake.
      if (data['lionMineBalanceRevision'] == null &&
          board.tiles.length == 120) {
        final tiles = board.tiles.toList();
        for (final (index, oldType) in [
          (107, TileType.lion),
          (100, TileType.mine),
        ]) {
          if (tiles[index].type != oldType) continue;
          tiles[index] = tiles[index].withChanges({
            'type': 'normal',
            'label': '',
            'amount': 0,
            'destination': null,
            'consumesAntidote': false,
            'artwork': null,
          });
        }
        if (tiles[78].type == TileType.rawMeat) {
          tiles[78] = tiles[78].withChanges({'amount': 3});
        }
        board = BoardDefinition(tiles, id: board.id);
        if (await preferences.getString(lionMineBalanceBackupKey) == null) {
          await preferences.setString(lionMineBalanceBackupKey, saved);
        }
        changed = true;
      }
      if (data['mineColorsRevision'] != 2 && board.tiles.length == 120) {
        final tiles = board.tiles.toList();
        final mines = tiles
            .where((tile) => tile.type == TileType.mine)
            .toList();
        for (var i = 0; i < mines.length; i++) {
          final tile = mines[i];
          final color = i == mines.length - 2
              ? 'blue'
              : i.isEven
              ? 'green'
              : 'red';
          // The final mine remains lethal.
          final selected = i == mines.length - 1 ? 'red' : color;
          tiles[tile.index] = tile.withChanges({
            'mineColor': selected,
            'destination': selected == 'red' ? null : 62,
            'fillColor': null,
          });
        }
        board = BoardDefinition(tiles, id: board.id);
        const backupKey = 'spiral_custom_board_before_mine_colors';
        if (await preferences.getString(backupKey) == null) {
          await preferences.setString(backupKey, saved);
        }
        changed = true;
      }
      if (changed) {
        await preferences.setString(customBoardKey, _encodeBoard(board));
      }
      return board;
    }
    return loadReferenceBoard();
  }

  Future<BoardDefinition> saveBoard(BoardDefinition board) async {
    final saved = BoardDefinition(
      board.tiles,
      id: 'custom-vector-${DateTime.now().microsecondsSinceEpoch}',
    );
    await SharedPreferencesAsync().setString(
      customBoardKey,
      _encodeBoard(saved),
    );
    return saved;
  }

  /// Online rooms need a rule revision so older clients cannot mix tile effects.
  /// Keep the local board identity stable so existing offline saves still load.
  Future<BoardDefinition> loadOnlineBoard() async {
    final source = await (bundle ?? rootBundle).loadString(assetPath);
    final data = Map<String, dynamic>.from(jsonDecode(source) as Map);
    final reference = BoardDefinition.fromJson(data);
    final revision = data['onlineBoardId'];
    if (revision != null &&
        (revision is! String ||
            !RegExp(r'^[A-Za-z0-9_-]{1,100}$').hasMatch(revision))) {
      throw const FormatException('Invalid online board revision.');
    }
    return BoardDefinition(
      reference.tiles,
      id: revision as String? ?? 'spiral-quest-board-v4',
    );
  }

  Future<BoardDefinition> loadReferenceBoard() async {
    final source = await (bundle ?? rootBundle).loadString(assetPath);
    return BoardDefinition.fromJson(
      Map<String, dynamic>.from(jsonDecode(source) as Map),
    );
  }
}
