import 'package:flutter_test/flutter_test.dart';
import 'package:spiral_pass_play/features/game/application/game_controller.dart';
import 'package:spiral_pass_play/features/game/data/board_repository.dart';
import 'package:spiral_pass_play/features/game/domain/board_definition.dart';
import 'package:spiral_pass_play/features/game/domain/game_session.dart';
import 'package:spiral_pass_play/features/game/domain/medical_item.dart';
import 'package:spiral_pass_play/features/game/domain/player_inventory.dart';
import 'package:spiral_pass_play/features/game/domain/weapon.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late BoardDefinition board;
  setUp(() async {
    board = await const BoardRepository().loadReferenceBoard();
  });

  GameController gameAt(int from) {
    final game = GameController.newGame(
      names: ['One', 'Two'],
      colors: [1, 2],
      board: board,
      diceRoller: () => 1,
    );
    game.session.currentPlayer.position = from;
    addTearDown(game.dispose);
    return game;
  }

  test('Healthy players can visit hospital with no cash and leave freely', () {
    final game = gameAt(61);
    final player = game.session.currentPlayer;
    player.cash = 0;
    game.roll();
    game.finishAnimation();
    expect(player.position, 62);
    expect(player.isInjured, isFalse);
    expect(player.cash, 0);
    expect(game.session.pendingHospital, isFalse);
    expect(game.session.phase, TurnPhase.shopping);
    expect(game.isHospitalShopping, isTrue);
    game.finishShopping();
    game.dismissTileSummary();
    expect(game.session.phase, TurnPhase.handoff);
    expect(player.position, 62);
    expect(player.debt, 0);
  });

  test('Hospital supplies have prices, persist, and never create debt', () {
    final game = gameAt(61);
    final player = game.session.currentPlayer;
    player.cash = 15;
    expect(game.buyMedicalItem(MedicalItem.healthPack), isFalse);
    game.roll();
    game.finishAnimation();
    expect(game.buyWeapon(WeaponType.stabber), isFalse);
    expect(game.buyMedicalItem(MedicalItem.healthPack), isTrue);
    expect(player.cash, 5);
    expect(player.inventory.healthPacks, 1);
    expect(game.buyMedicalItem(MedicalItem.healthPack), isFalse);
    expect(game.buyMedicalItem(MedicalItem.antidote), isTrue);
    expect(player.cash, 0);
    expect(player.inventory.antidotes, 1);
    expect(game.buyMedicalItem(MedicalItem.antidote), isFalse);
    expect(player.debt, 0);
    final resumed = GameController(
      session: GameSession.fromJson(game.session.toJson()),
      board: board,
    );
    addTearDown(resumed.dispose);
    expect(resumed.session.phase, TurnPhase.shopping);
    expect(resumed.isHospitalShopping, isTrue);
    expect(resumed.session.currentPlayer.inventory.healthPacks, 1);
    expect(resumed.session.currentPlayer.inventory.antidotes, 1);
    expect(resumed.session.currentPlayer.cash, 0);
    resumed.finishShopping();
    expect(resumed.buyMedicalItem(MedicalItem.antidote), isFalse);
  });

  test('Weapon shops cannot sell medical supplies', () {
    final shop = board.tiles.firstWhere((tile) => tile.type == TileType.shop);
    final game = gameAt(shop.index - 1);
    game.session.currentPlayer.cash = 100;
    game.roll();
    game.finishAnimation();
    expect(game.session.phase, TurnPhase.shopping);
    expect(game.isHospitalShopping, isFalse);
    expect(game.buyMedicalItem(MedicalItem.antidote), isFalse);
    expect(game.session.currentPlayer.cash, 100);
    expect(game.session.currentPlayer.inventory.antidotes, 0);
  });

  for (final injured in [false, true]) {
    test(
      'Event arrival at hospital resolves ${injured ? 'treatment' : 'supplies'} after card review',
      () {
        final tiles = board.tiles.toList();
        tiles[59] = tiles[59].withChanges({'type': 'event'});
        final game = GameController.newGame(
          names: ['One', 'Two'],
          colors: [1, 2],
          board: BoardDefinition(tiles, id: board.id),
          diceRoller: () => 1,
          eventCardOrder: ['forward_3'],
        );
        addTearDown(game.dispose);
        final player = game.session.currentPlayer;
        player.position = 58;
        player.isInjured = injured;
        expect(game.roll()!.path, [59, 62]);
        game.finishAnimation();
        expect(game.session.phase, TurnPhase.eventReveal);
        game.dismissEventCard();
        expect(
          game.session.phase,
          injured ? TurnPhase.hospitalChoice : TurnPhase.shopping,
        );
        expect(player.position, 62);
        expect(player.cash, 10);
        if (injured) {
          game.chooseHospitalTreatment(pay: true);
          expect(player.isInjured, isFalse);
          expect(game.session.phase, TurnPhase.shopping);
        }
        game.finishShopping();
        game.dismissTileSummary();
        expect(game.session.phase, TurnPhase.handoff);
      },
    );
  }

  for (final index in [65, 68, 70, 76, 103, 104, 105, 106, 112]) {
    test(
      'A health pack treats hazard $index in place exactly once and survives resume',
      () {
        final game = gameAt(index - 1);
        final player = game.session.currentPlayer;
        player.cash = 0;
        player.inventory.healthPacks = 2;
        player.inventory.antidotes = 1;
        player.inventory.boats = 1;
        final trap = board.tiles[index].type == TileType.trapDoor;
        expect(game.roll()!.path, [index]);
        expect(player.position, index);
        expect(player.isInjured, isFalse);
        expect(player.inventory.healthPacks, 1);
        expect(player.inventory.antidotes, 1);
        expect(player.inventory.boats, 1);
        expect(player.cash, 0);
        expect(player.debt, 0);
        expect(player.skipTurns, trap ? 1 : 0);
        expect(game.session.pendingHospital, isFalse);
        expect(game.session.pendingShopTile, isNull);
        game.finishAnimation();
        game.finishAnimation();
        expect(game.session.phase, TurnPhase.specialReview);
        expect(game.session.tileSummary!.finalPosition, index);
        expect(
          game.session.tileSummary!.changes,
          contains('Health packs: −1 (2 → 1)'),
        );
        final resumed = GameController(
          session: GameSession.fromJson(game.session.toJson()),
          board: board,
        );
        addTearDown(resumed.dispose);
        expect(resumed.session.phase, TurnPhase.specialReview);
        expect(resumed.session.currentPlayer.position, index);
        expect(resumed.session.currentPlayer.isInjured, isFalse);
        resumed.finishAnimation();
        resumed.useHealthPack();
        resumed.chooseHospitalTreatment(pay: true);
        resumed.dismissTileSummary();
        expect(resumed.session.phase, TurnPhase.handoff);
        expect(resumed.session.players.first.inventory.healthPacks, 1);
        expect(resumed.session.players.first.cash, 0);
        expect(resumed.session.players.first.position, index);
      },
    );
  }

  for (final index in [100, 107]) {
    test('Removed hazard $index is safe and consumes no supplies', () {
      final game = gameAt(index - 1);
      final player = game.session.currentPlayer;
      player.inventory
        ..healthPacks = 2
        ..rawMeat = 2
        ..antidotes = 2;
      expect(board.tiles[index].type, TileType.normal);
      expect(game.roll()!.path, [index]);
      expect(player.position, index);
      expect(player.isInjured, isFalse);
      expect(player.inventory.healthPacks, 2);
      expect(player.inventory.rawMeat, 2);
      expect(player.inventory.antidotes, 2);
      expect(player.cash, 10);
      expect(player.skipTurns, 0);
      expect(game.session.pendingHospital, isFalse);
      game.finishAnimation();
      expect(game.session.phase, TurnPhase.handoff);
      expect(game.session.tileSummary, isNull);
    });
  }

  for (final (index, effectIndex) in [(68, 66), (76, 74), (103, 101)]) {
    for (final event in [false, true]) {
      for (final protected in [false, true]) {
        test(
          '${event ? 'Event' : 'Forced'} landing on $index ${protected ? 'uses a pack in place' : 'sends the injured player to hospital'}',
          () {
            final tiles = board.tiles.toList();
            tiles[effectIndex] = tiles[effectIndex].withChanges({
              'type': event ? 'event' : 'moveForward',
              'amount': 2,
            });
            // The forward card moves three spaces; its starting tile is one
            // earlier than the corresponding two-space forced move.
            final startEffectIndex = event ? effectIndex - 1 : effectIndex;
            if (event) {
              tiles[startEffectIndex] = tiles[startEffectIndex].withChanges({
                'type': 'event',
              });
            }
            final game = GameController.newGame(
              names: ['One', 'Two'],
              colors: [1, 2],
              board: BoardDefinition(tiles, id: board.id),
              diceRoller: () => 1,
              eventCardOrder: ['forward_3'],
            );
            addTearDown(game.dispose);
            final player = game.session.currentPlayer;
            player.position = startEffectIndex - 1;
            player.cash = 20;
            player.inventory.healthPacks = protected ? 1 : 0;
            expect(
              game.roll()!.path,
              protected
                  ? [startEffectIndex, index]
                  : [startEffectIndex, index, 62],
            );
            expect(player.position, protected ? index : 62);
            expect(player.isInjured, !protected);
            expect(player.inventory.healthPacks, 0);
            expect(player.cash, 20);
            expect(player.skipTurns, index == 68 ? 1 : 0);
            game.finishAnimation();
            if (event) {
              expect(game.session.phase, TurnPhase.eventReveal);
              game.dismissEventCard();
            }
            expect(
              game.session.phase,
              protected
                  ? (event ? TurnPhase.handoff : TurnPhase.specialReview)
                  : TurnPhase.hospitalChoice,
            );
            if (protected) {
              expect(game.session.pendingHospital, isFalse);
              expect(game.session.pendingShopTile, isNull);
              game.dismissTileSummary();
              expect(game.session.players.first.inventory.healthPacks, 0);
              expect(game.session.players.first.position, index);
            }
          },
        );
      }
    }
  }

  test(
    'A hospital-bought health pack treats the next fire without a return trip',
    () {
      final game = gameAt(61);
      final player = game.session.currentPlayer;
      game.roll();
      game.finishAnimation();
      expect(game.buyMedicalItem(MedicalItem.healthPack), isTrue);
      game.finishShopping();
      game.dismissTileSummary();
      game.session.phase = TurnPhase.ready;
      game.session.currentPlayerIndex = 0;
      player.position = 75;
      expect(game.roll()!.path, [76]);
      expect(player.position, 76);
      expect(player.isInjured, isFalse);
      expect(player.cash, 0);
      expect(player.inventory.healthPacks, 0);
      expect(game.session.pendingHospital, isFalse);
      expect(game.session.pendingShopTile, isNull);
    },
  );

  test(
    'An already injured hospital visitor can use one saved health pack without paying',
    () {
      final game = gameAt(61);
      final player = game.session.currentPlayer;
      player.cash = 0;
      player.isInjured = true;
      player.inventory.healthPacks = 2;
      player.inventory.antidotes = 1;
      game.roll();
      game.finishAnimation();
      expect(game.session.phase, TurnPhase.hospitalChoice);
      expect(player.isInjured, isTrue);
      final resumed = GameController(
        session: GameSession.fromJson(game.session.toJson()),
        board: board,
      );
      addTearDown(resumed.dispose);
      final restoredPlayer = resumed.session.currentPlayer;
      resumed.chooseHospitalTreatment(pay: true);
      expect(resumed.session.phase, TurnPhase.hospitalChoice);
      resumed.useHealthPack();
      expect(restoredPlayer.position, 62);
      expect(restoredPlayer.cash, 0);
      expect(restoredPlayer.debt, 0);
      expect(restoredPlayer.isInjured, isFalse);
      expect(restoredPlayer.inventory.healthPacks, 1);
      expect(restoredPlayer.inventory.antidotes, 1);
      expect(resumed.session.pendingHospital, isFalse);
      expect(resumed.session.phase, TurnPhase.shopping);
      resumed.useHealthPack();
      resumed.chooseHospitalTreatment(pay: true);
      expect(restoredPlayer.inventory.healthPacks, 1);
      expect(restoredPlayer.cash, 0);
      resumed.finishShopping();
      resumed.dismissTileSummary();
      expect(resumed.session.phase, TurnPhase.handoff);
    },
  );

  test('A missing health pack cannot bypass hospital treatment', () {
    final game = gameAt(75);
    game.roll();
    game.finishAnimation();
    game.useHealthPack();
    expect(game.session.phase, TurnPhase.hospitalChoice);
    expect(game.session.currentPlayer.isInjured, isTrue);
    expect(game.session.currentPlayer.inventory.healthPacks, 0);
  });

  test('Purchased antidote protects a snake landing; health packs do not', () {
    final game = gameAt(61);
    final player = game.session.currentPlayer;
    game.roll();
    game.finishAnimation();
    expect(game.buyMedicalItem(MedicalItem.antidote), isTrue);
    game.finishShopping();
    game.dismissTileSummary();
    // Set up the next visit using the inventory actually purchased above.
    game.session.phase = TurnPhase.ready;
    game.session.currentPlayerIndex = 0;
    player.position = 86;
    expect(game.roll()!.path, [87]);
    expect(player.inventory.antidotes, 0);
    expect(player.isInjured, isFalse);

    final unprotected = gameAt(86);
    unprotected.session.currentPlayer.inventory.healthPacks = 1;
    expect(unprotected.roll()!.path, [87, 10]);
    expect(unprotected.session.currentPlayer.inventory.healthPacks, 1);
    expect(unprotected.session.currentPlayer.inventory.antidotes, 1);
    expect(unprotected.session.currentPlayer.isInjured, isFalse);
  });

  test('Legacy saves default healthy and retain an outstanding treatment', () {
    final game = gameAt(75);
    game.roll();
    game.finishAnimation();
    final saved = game.session.toJson();
    for (final player in saved['players'] as List) {
      (player as Map).remove('isInjured');
      (player['inventory'] as Map).remove('healthPacks');
    }
    final restored = GameSession.fromJson(saved);
    expect(restored.currentPlayer.isInjured, isTrue);
    expect(restored.currentPlayer.inventory.healthPacks, 0);
    expect(restored.players[1].isInjured, isFalse);
    expect(PlayerInventory.fromJson({}).healthPacks, 0);
    expect(() => PlayerInventory(healthPacks: -1), throwsArgumentError);
  });
}
