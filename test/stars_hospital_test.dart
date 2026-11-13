import 'package:flutter_test/flutter_test.dart';
import 'package:spiral_pass_play/features/game/application/game_controller.dart';
import 'package:spiral_pass_play/features/game/data/board_repository.dart';
import 'package:spiral_pass_play/features/game/domain/board_definition.dart';
import 'package:spiral_pass_play/features/game/domain/game_session.dart';
import 'package:spiral_pass_play/features/game/domain/player_inventory.dart';

BoardDefinition _policeBoard() => BoardDefinition([
  for (var i = 0; i <= 40; i++)
    BoardTile(
      index: i,
      x: i / 40,
      y: 0,
      type: i == 0
          ? TileType.start
          : i == 40
          ? TileType.finish
          : i == 20
          ? TileType.police
          : i == 10 || i == 30
          ? TileType.jail
          : TileType.normal,
    ),
]);
GameController _game(BoardDefinition board, int from, {int dice = 1}) {
  final game = GameController.newGame(
    names: ['One', 'Two'],
    colors: [1, 2],
    board: board,
    diceRoller: () => dice,
  );
  game.session.players.first.position = from;
  addTearDown(game.dispose);
  return game;
}

void _finish(GameController game) {
  game.finishAnimation();
  if (game.session.phase == TurnPhase.specialReview) game.dismissTileSummary();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  for (final stars in [1, 3]) {
    for (final from in [17, 23]) {
      test(
        '$stars stars at tile $from means $stars missed turns and cleared stars',
        () {
          final game = _game(_policeBoard(), from);
          final player = game.session.players.first;
          final cash = player.cash;
          player.inventory.stars = stars;
          expect(game.roll()!.path, [from, from == 17 ? 10 : 30]);
          expect(player.inventory.stars, 0);
          expect(player.skipTurns, stars);
          expect(player.cash, cash);
          expect(game.session.pendingPoliceFine, isNull);
          game.finishAnimation();
          game.finishAnimation();
          expect(game.session.phase, TurnPhase.specialReview);
          expect(player.skipTurns, stars);
          final restored = GameSession.fromJson(game.session.toJson());
          expect(restored.players.first.inventory.stars, 0);
          expect(restored.players.first.skipTurns, stars);
          game.dismissTileSummary();
          for (var i = 0; i < stars; i++) {
            expect(game.session.currentPlayerIndex, 1);
            game.acknowledgeHandoff();
            game.roll();
            _finish(game);
            expect(player.skipTurns, stars - i - 1);
          }
          // One more opponent turn reaches the now-eligible player.
          game.acknowledgeHandoff();
          game.roll();
          _finish(game);
          expect(game.session.currentPlayerIndex, 0);
        },
      );
    }
  }

  test(
    'Collecting a star near police immediately applies a one-turn sentence',
    () async {
      final board = await const BoardRepository().loadReferenceBoard();
      final game = _game(board, 35);
      final cash = game.session.currentPlayer.cash;
      expect(game.roll()!.path, [36, 39]);
      expect(game.session.currentPlayer.inventory.stars, 0);
      expect(game.session.currentPlayer.skipTurns, 1);
      expect(game.session.currentPlayer.cash, cash + 25);
      expect(game.session.message, contains('Collected 1 star'));
      expect(game.session.message, contains('Stars cleared'));
      game.finishAnimation();
      expect(game.session.phase, TurnPhase.specialReview);
      expect(game.session.tileSummary!.finalPosition, 39);
    },
  );

  test(
    'Stars and weapons together give the star sentence and confiscate weapons',
    () {
      final game = _game(_policeBoard(), 17);
      final player = game.session.currentPlayer;
      player.inventory.stars = 2;
      player.inventory.stabbers = 1;
      player.inventory.pewPews = 2;
      game.roll();
      game.finishAnimation();
      expect(player.inventory.stars, 0);
      expect(player.inventory.hasWeapons, isFalse);
      expect(player.skipTurns, 2);
      expect(game.session.pendingPoliceFine, isNull);
      expect(game.session.phase, TurnPhase.specialReview);
    },
  );

  test('Stars accumulate away from police and are preserved in saves', () {
    final original = _policeBoard();
    final tiles = original.tiles.toList();
    tiles[5] = tiles[5].withChanges({'type': 'star', 'amount': 2});
    final game = _game(BoardDefinition(tiles), 4);
    game.session.currentPlayer.inventory.stars = 1;
    game.roll();
    expect(game.session.currentPlayer.inventory.stars, 3);
    final restored = GameSession.fromJson(game.session.toJson());
    expect(restored.currentPlayer.inventory.stars, 3);
    expect(PlayerInventory.fromJson({'cash': 10}).stars, 0);
    expect(() => PlayerInventory(stars: -1), throwsArgumentError);
  });

  test('Star holders stop on entering police range during dice movement', () {
    final game = _game(_policeBoard(), 14, dice: 6);
    game.session.currentPlayer.inventory.stars = 2;
    expect(game.roll()!.path, [15, 16, 17, 10]);
    expect(game.session.currentPlayer.skipTurns, 2);
  });

  for (final index in [65, 68, 70]) {
    test(
      'Trap door $index sends to hospital 62 and adds exactly one missed turn',
      () async {
        final board = await const BoardRepository().loadReferenceBoard();
        final game = _game(board, index - 1);
        final player = game.session.currentPlayer;
        player.skipTurns = 2;
        expect(board.tiles[index].type, TileType.trapDoor);
        expect(game.roll()!.path, [index, 62]);
        expect(player.position, 62);
        expect(player.skipTurns, 3);
        game.finishAnimation();
        game.finishAnimation();
        expect(player.skipTurns, 3);
        expect(game.session.phase, TurnPhase.hospitalChoice);
        final saved = GameSession.fromJson(game.session.toJson());
        expect(saved.currentPlayer.position, 62);
        expect(saved.currentPlayer.skipTurns, 3);
      },
    );
  }

  test(
    'Fire 76 goes straight to hospital without another skipped turn',
    () async {
      final board = await const BoardRepository().loadReferenceBoard();
      final game = _game(board, 75);
      final player = game.session.currentPlayer;
      player.skipTurns = 2;
      expect(board.tiles[76].type, TileType.fire);
      expect(game.roll()!.path, [76, 62]);
      expect(player.position, 62);
      expect(player.skipTurns, 2);
      expect(game.session.message, contains('FIRE'));
    },
  );

  test(
    'Hospital arrival preserves inventory while treatment is pending',
    () async {
      final board = await const BoardRepository().loadReferenceBoard();
      final game = _game(board, 61);
      final player = game.session.currentPlayer;
      player.inventory.stars = 2;
      player.inventory.boats = 1;
      player.skipTurns = 2;
      game.roll();
      expect(board.tiles[62].type, TileType.hospital);
      expect(player.position, 62);
      expect(player.skipTurns, 2);
      expect(player.inventory.stars, 2);
      expect(player.inventory.boats, 1);
    },
  );

  test(
    'Forced movement onto a trap door resolves hospital and its penalty once',
    () async {
      final original = await const BoardRepository().loadReferenceBoard();
      final tiles = original.tiles.toList();
      tiles[66] = tiles[66].withChanges({'type': 'setBack', 'amount': 1});
      final game = _game(BoardDefinition(tiles), 65);
      expect(game.roll()!.path, [66, 65, 62]);
      expect(game.session.currentPlayer.position, 62);
      expect(game.session.currentPlayer.skipTurns, 1);
    },
  );

  for (final pay in [true, false]) {
    test(
      'Hospital choice survives resume and ${pay ? 'charges exactly ten coins' : 'allows a free restart'}',
      () async {
        final board = await const BoardRepository().loadReferenceBoard();
        final game = _game(board, 61);
        game.session.currentPlayer.cash = 15;
        game.roll();
        game.finishAnimation();
        expect(game.session.phase, TurnPhase.hospitalChoice);
        expect(game.session.currentPlayer.cash, 15);
        final resumed = GameController(
          session: GameSession.fromJson(game.session.toJson()),
          board: board,
        );
        addTearDown(resumed.dispose);
        resumed.chooseHospitalTreatment(pay: pay);
        expect(resumed.session.currentPlayer.cash, pay ? 5 : 15);
        expect(resumed.session.currentPlayer.position, pay ? 62 : 0);
        expect(resumed.session.pendingHospital, isFalse);
        expect(resumed.session.phase, TurnPhase.specialReview);
        resumed.chooseHospitalTreatment(pay: true);
        expect(resumed.session.currentPlayer.cash, pay ? 5 : 15);
        resumed.dismissTileSummary();
        expect(resumed.session.phase, TurnPhase.handoff);
      },
    );
  }
  for (final from in [61, 64, 75, 102]) {
    test(
      'Hospital restarts an unaffordable arrival from $from without debt',
      () async {
        final board = await const BoardRepository().loadReferenceBoard();
        final game = _game(board, from);
        game.session.currentPlayer.cash = 9;
        game.roll();
        game.finishAnimation();
        expect(game.session.currentPlayer.position, 0);
        expect(game.session.currentPlayer.cash, 9);
        expect(game.session.currentPlayer.debt, 0);
        expect(game.session.pendingHospital, isFalse);
        expect(game.session.phase, TurnPhase.specialReview);
        expect(game.session.message, contains('not have enough coins'));
      },
    );
  }

  test('Fire and trap door destinations must be hospitals', () async {
    final original = await const BoardRepository().loadReferenceBoard();
    for (final index in [65, 76]) {
      final tiles = original.tiles.toList();
      tiles[index] = tiles[index].withChanges({'destination': 1});
      expect(() => BoardDefinition(tiles), throwsArgumentError);
    }
  });
}
