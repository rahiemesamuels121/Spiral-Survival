import 'dart:convert';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:spiral_pass_play/features/game/application/game_controller.dart';
import 'package:spiral_pass_play/features/game/data/board_repository.dart';
import 'package:spiral_pass_play/features/game/domain/board_definition.dart';
import 'package:spiral_pass_play/features/game/domain/game_session.dart';

// Existing turn-flow tests acknowledge the new special-tile explanation.
void finishAndReview(GameController game) {
  game.finishAnimation();
  if (game.session.phase == TurnPhase.specialReview) game.dismissTileSummary();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<BoardDefinition> load() async {
    final source = await rootBundle.loadString(BoardRepository.assetPath);
    return BoardDefinition.fromJson(
      Map<String, dynamic>.from(jsonDecode(source) as Map),
    );
  }

  Future<GameController> gameAt(int position) async {
    final game = GameController.newGame(
      names: ['One', 'Two'],
      colors: [1, 2],
      board: await load(),
      diceRoller: () => 1,
    );
    game.session.players.first.position = position;
    addTearDown(game.dispose);
    return game;
  }

  test(
    'Special review blocks rolls and survives resume without repeating effects',
    () async {
      final game = await gameAt(30);
      game.session.players.first.cash = 5;
      game.roll();
      game.finishAnimation();
      expect(game.session.phase, TurnPhase.specialReview);
      expect(game.session.currentPlayerIndex, 0);
      expect(game.beginDiceRoll(), isNull);
      final summary = game.session.tileSummary!;
      expect(summary.landedIndex, 31);
      expect(summary.finalPosition, 31);
      expect(summary.changes, contains('Cash: −\$5 (5 → 0)'));
      expect(summary.changes, contains('Debt: +\$15 (0 → 15)'));
      game.finishAnimation(); // Duplicate animation callback cannot advance the turn.
      expect(game.session.phase, TurnPhase.specialReview);
      final restored = GameController(
        session: GameSession.fromJson(game.session.toJson()),
        board: game.board,
      );
      addTearDown(restored.dispose);
      expect(restored.session.phase, TurnPhase.specialReview);
      expect(restored.session.tileSummary!.changes, summary.changes);
      expect(restored.beginDiceRoll(), isNull);
      restored.dismissTileSummary();
      restored.dismissTileSummary();
      expect(restored.session.phase, TurnPhase.handoff);
      expect(restored.session.currentPlayerIndex, 1);
      expect(restored.session.players.first.debt, 15);
      expect(restored.session.players.first.skipTurns, 0);
      expect(restored.session.tileSummary, isNull);
    },
  );

  test(
    'Restart summary identifies the landed tile and return to start',
    () async {
      final game = await gameAt(3);
      game.roll();
      game.finishAnimation();
      expect(game.session.phase, TurnPhase.specialReview);
      expect(game.session.tileSummary!.landedIndex, 4);
      expect(game.session.tileSummary!.finalPosition, 0);
      expect(game.session.tileSummary!.message, contains('returned to START'));
      expect(
        game.session.tileSummary!.message,
        contains('No boat, you drowned.'),
      );
    },
  );

  test('Normal tiles proceed to handoff without a special review', () async {
    final game = await gameAt(0);
    game.roll();
    game.finishAnimation();
    expect(game.session.phase, TurnPhase.handoff);
    expect(game.session.tileSummary, isNull);
  });

  test('Boat pickup adds to only the active player inventory', () async {
    final game = await gameAt(1);
    game.roll();
    expect(game.session.players.first.inventory.boats, 1);
    expect(game.session.players.last.inventory.boats, 0);
  });

  test('Tile 10 adds an antidote instead of a loan', () async {
    final game = await gameAt(9);
    game.roll();
    expect(game.session.players.first.inventory.antidotes, 1);
    expect(game.session.players.first.cash, 10);
    expect(game.session.players.first.debt, 0);
  });

  test(
    'Snake consumes one antidote and leaves the player on the snake',
    () async {
      final game = await gameAt(19);
      final player = game.session.players.first;
      player.inventory.antidotes = 2;
      final action = game.roll()!;
      expect(action.path, [20]);
      expect(player.position, 20);
      expect(player.inventory.antidotes, 1);
      finishAndReview(game);
      expect(game.session.phase, TurnPhase.handoff);
    },
  );

  test(
    'Unprotected snake returns to tile 10 to collect an antidote once',
    () async {
      final game = await gameAt(19);
      final player = game.session.players.first;
      final action = game.roll()!;
      expect(action.path, [20, 10]);
      expect(player.position, 10);
      expect(player.inventory.antidotes, 1);
      expect(game.resolveDiceRoll(), isNull);
      expect(player.inventory.antidotes, 1);
    },
  );

  test(
    'Police sends to the closest jail and lets the player miss a turn instead of paying',
    () async {
      final game = await gameAt(15);
      final player = game.session.players.first;
      player.cash = 5;
      final action = game.roll()!;
      expect(action.path, [16, 13]);
      expect(player.position, 13);
      expect(player.cash, 5);
      expect(player.debt, 0);
      expect(player.skipTurns, 0);
      game.finishAnimation();
      expect(game.session.phase, TurnPhase.jailChoice);
      game.choosePolicePenalty(payFine: false);
      expect(player.skipTurns, 1);
      expect(player.cash, 5);
      game.dismissTileSummary();
      game.acknowledgeHandoff();
      game.roll();
      finishAndReview(game);
      expect(game.session.currentPlayerIndex, 1);
      expect(player.skipTurns, 0);
    },
  );

  test(
    'Inventory survives save and restore, including cash and penalties',
    () async {
      final game = await gameAt(19);
      final player = game.session.players.first;
      player.inventory.boats = 2;
      player.inventory.antidotes = 1;
      player.cash = 75;
      player.debt = 10;
      game.roll();
      finishAndReview(game);
      final restored = GameSession.fromJson(game.session.toJson());
      final inventory = restored.players.first.inventory;
      expect(inventory.boats, 2);
      expect(inventory.antidotes, 0);
      expect(inventory.cash, 75);
      expect(restored.players.first.debt, 10);
    },
  );

  test('Old saves keep cash and start with empty item inventory', () async {
    final game = await gameAt(0);
    game.session.players.first.cash = 42;
    final saved = game.session.toJson();
    for (final player in saved['players'] as List) {
      (player as Map).remove('inventory');
    }
    final restored = GameSession.fromJson(saved);
    expect(restored.players.first.cash, 42);
    expect(restored.players.first.inventory.boats, 0);
    expect(restored.players.first.inventory.antidotes, 0);
  });

  for (var index = 4; index <= 7; index++) {
    test(
      'A boat crosses sea tile $index to the first space after the sea',
      () async {
        final board = await load();
        final game = GameController.newGame(
          names: ['One', 'Two'],
          colors: [1, 2],
          board: board,
          diceRoller: () => index - 3,
        );
        addTearDown(game.dispose);
        final player = game.session.players.first;
        player.position = 3;
        player.inventory.boats = 1;
        final outcome = game.roll()!;
        expect(outcome.path, [4, 5, 6, 7, 8]);
        expect(outcome.landedType, TileType.sea);
        expect(player.position, 8);
        expect(player.inventory.boats, 1);
        expect(player.cash, 10);
        game.finishAnimation();
        expect(game.session.phase, TurnPhase.specialReview);
        expect(game.session.tileSummary!.landedIndex, index);
        expect(game.session.tileSummary!.finalPosition, 8);
        expect(
          game.session.tileSummary!.message,
          contains('safely to space 8'),
        );
        expect(game.beginDiceRoll(), isNull);
        final restored = GameSession.fromJson(game.session.toJson());
        expect(restored.players.first.inventory.boats, 1);
        expect(restored.players.first.position, 8);
        game.dismissTileSummary();
        expect(game.session.phase, TurnPhase.handoff);
      },
    );
    test(
      'Landing on sea tile $index returns to start and ends the turn',
      () async {
        final board = await load();
        final game = GameController.newGame(
          names: ['One', 'Two'],
          colors: [1, 2],
          board: board,
          diceRoller: () => index - 3,
        );
        addTearDown(game.dispose);
        final player = game.session.players.first;
        player.position = 3;
        player.debt = 20;
        final action = game.roll()!;
        expect(board.tiles[index].type, TileType.sea);
        expect(action.path, [...List.generate(index - 3, (i) => i + 4), 0]);
        expect(action.landedType, TileType.sea);
        expect(player.position, 0);
        expect(player.cash, 10);
        expect(player.debt, 20);
        finishAndReview(game);
        expect(game.session.phase, TurnPhase.handoff);
        expect(game.session.currentPlayerIndex, 1);
        final restored = GameSession.fromJson(game.session.toJson());
        expect(restored.players.first.position, 0);
        expect(restored.phase, TurnPhase.handoff);
      },
    );
  }

  test('Passing over sea tiles does not reset the player', () async {
    final board = await load();
    final game = GameController.newGame(
      names: ['One', 'Two'],
      colors: [1, 2],
      board: board,
      diceRoller: () => 5,
    );
    addTearDown(game.dispose);
    game.session.players.first.position = 3;
    game.roll();
    expect(game.session.players.first.position, 8);
  });

  test('Square spiral uses equal gaps and never overlaps tiles', () async {
    final board = await load();
    for (var i = 1; i < board.tiles.length; i++) {
      final a = board.tiles[i - 1];
      final b = board.tiles[i];
      final dx = (a.x - b.x).abs();
      final dy = (a.y - b.y).abs();
      expect(dx + dy, closeTo(.062, .000001));
      expect(dx < .000001 || dy < .000001, isTrue);
    }
    for (var i = 0; i < board.tiles.length; i++) {
      for (var j = i + 1; j < board.tiles.length; j++) {
        final a = board.tiles[i];
        final b = board.tiles[j];
        expect((a.x - b.x).abs() >= .05 || (a.y - b.y).abs() >= .05, isTrue);
      }
    }
    expect(
      board.tiles.map((t) => t.x).reduce((a, b) => a < b ? a : b) +
          board.tiles.map((t) => t.x).reduce((a, b) => a > b ? a : b),
      closeTo(1, .000001),
    );
  });

  test('Uploaded image board has 120 consecutive mapped tiles', () async {
    final board = await load();
    expect(board.tiles.length, 120);
    expect(board.tiles.first.type, TileType.start);
    expect(board.tiles.last.type, TileType.finish);
    expect(board.lastIndex, 119);
    expect(board.tiles.every((t) => t.x >= 0 && t.x <= 1), true);
    expect(board.tiles.every((t) => t.y >= 0 && t.y <= 1), true);
  });

  test(
    'All five portals use mystery cards instead of fixed destinations',
    () async {
      final board = await load();
      final portals = board.tiles.where((tile) => tile.type == TileType.portal);
      expect(portals.map((tile) => tile.index), [25, 55, 87, 108, 117]);
      for (final portal in portals) {
        expect(portal.destination, isNull);
      }
    },
  );

  test('Five local players are permitted with the mapped board', () async {
    final board = await load();
    final controller = GameController.newGame(
      names: ['One', 'Two', 'Three', 'Four', 'Five'],
      colors: [1, 2, 3, 4, 5],
      board: board,
      diceRoller: () => 1,
    );
    expect(controller.session.players.length, 5);
    expect(controller.session.boardId, board.id);
    controller.dispose();
  });

  test('Portal landing pauses for mystery cards instead of chaining', () async {
    final board = await load();
    final portal = board.tiles.firstWhere(
      (tile) => tile.type == TileType.portal,
    );
    final controller = GameController.newGame(
      names: ['One', 'Two'],
      colors: [1, 2],
      board: board,
      diceRoller: () => 1,
    );
    controller.session.players[0].position = portal.index - 1;
    final outcome = controller.roll()!;
    expect(outcome.path, [portal.index]);
    expect(controller.session.players[0].position, portal.index);
    controller.finishAnimation();
    expect(controller.session.phase, TurnPhase.portalChoice);
    expect(controller.session.winnerId, isNull);
    controller.dispose();
  });
}
