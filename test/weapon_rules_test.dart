import 'package:flutter_test/flutter_test.dart';
import 'package:spiral_pass_play/features/game/application/game_controller.dart';
import 'package:spiral_pass_play/features/game/domain/board_definition.dart';
import 'package:spiral_pass_play/features/game/domain/game_session.dart';
import 'package:spiral_pass_play/features/game/domain/player_inventory.dart';
import 'package:spiral_pass_play/features/game/domain/weapon.dart';

BoardDefinition weaponBoard({
  int? shop,
  int? police,
  List<int> jails = const [],
}) => BoardDefinition([
  for (var i = 0; i <= 40; i++)
    BoardTile(
      index: i,
      x: (i % 10 + .5) / 10,
      y: (i ~/ 10 + .5) / 5,
      type: i == 0
          ? TileType.start
          : i == 40
          ? TileType.finish
          : i == shop
          ? TileType.shop
          : i == police
          ? TileType.police
          : jails.contains(i)
          ? TileType.jail
          : TileType.normal,
      amount: i == police ? 20 : 0,
    ),
]);
GameController weaponGame({
  BoardDefinition? board,
  int from = 10,
  int dice = 6,
}) {
  final game = GameController.newGame(
    names: ['One', 'Two', 'Three'],
    colors: [1, 2, 3],
    board: board ?? weaponBoard(),
    diceRoller: () => dice,
  );
  game.session.players.first.position = from;
  // Fund transaction fixtures independently of the game's $10 starting cash.
  game.session.players.first.cash = 100;
  addTearDown(game.dispose);
  return game;
}

void main() {
  for (final weapon in WeaponType.values) {
    for (var roll = 1; roll <= 6; roll++) {
      test(
        '${weapon.label}: same-tile attack needs a roll above 3 ($roll)',
        () {
          final game = weaponGame(from: 10, dice: roll);
          final player = game.session.players.first;
          final cash = player.cash;
          player.inventory.stabbers = weapon == WeaponType.stabber ? 1 : 0;
          player.inventory.pewPews = weapon == WeaponType.pewPew ? 1 : 0;
          game.session.players[1].position = 10;
          game.session.players[2].position = 11;
          game.roll();
          game.finishAnimation();
          if (roll <= 3) {
            expect(game.session.phase, TurnPhase.handoff);
            expect(game.session.players[1].position, 10);
          } else {
            expect(game.session.phase, TurnPhase.preMoveWeaponChoice);
            expect(player.position, 10);
            expect(game.weaponTargets(weapon), [1]);
            expect(game.useWeapon(weapon, 1), isTrue);
            expect(game.session.players[1].position, 0);
            expect(game.weaponCount(weapon), 0);
            expect(player.position, 10);
            expect(player.inventory.stars, 3);
            expect(player.cash, cash);
            expect(game.useWeapon(weapon, 1), isFalse);
            expect(player.inventory.stars, 3);
            game.finishAnimation();
            game.dismissTileSummary();
            expect(game.session.phase, TurnPhase.handoff);
          }
        },
      );
    }
  }

  for (var roll = 4; roll <= 6; roll++) {
    test(
      'Choose movement instead of same-tile attack on $roll, including resume',
      () {
        final game = weaponGame(from: 10, dice: roll);
        game.session.players.first.inventory.stabbers = 1;
        game.session.players[1].position = 10;
        game.roll();
        final restored = GameController(
          session: GameSession.fromJson(game.session.toJson()),
          board: game.board,
        );
        addTearDown(restored.dispose);
        expect(restored.session.phase, TurnPhase.preMoveWeaponChoice);
        restored.chooseMovement();
        expect(restored.session.players.first.position, 10 + roll);
        expect(restored.session.players[1].position, 10);
        expect(restored.session.players.first.inventory.stabbers, 1);
        expect(restored.session.phase, TurnPhase.animating);
      },
    );
  }

  test('Shop entry is optional and purchases cost exactly 40 and 95', () {
    final game = weaponGame(board: weaponBoard(shop: 10), from: 9, dice: 1);
    final player = game.session.players.first;
    player.cash = 200;
    game.roll();
    game.finishAnimation();
    expect(game.session.phase, TurnPhase.shopping);
    expect(player.cash, 200);
    expect(game.buyWeapon(WeaponType.stabber), isTrue);
    expect(player.cash, 160);
    expect(player.inventory.stabbers, 1);
    expect(game.buyWeapon(WeaponType.pewPew), isTrue);
    expect(player.cash, 65);
    expect(player.inventory.pewPews, 1);
    expect(game.buyWeapon(WeaponType.pewPew), isFalse);
    expect(player.cash, 65);
    game.finishShopping();
    game.dismissTileSummary();
    expect(game.session.phase, TurnPhase.handoff);
    expect(game.buyWeapon(WeaponType.stabber), isFalse);
    expect(player.cash, 65);
  });

  test('Leaving a shop without buying charges nothing', () {
    final game = weaponGame(board: weaponBoard(shop: 10), from: 9, dice: 1);
    game.roll();
    game.finishAnimation();
    game.finishShopping();
    game.dismissTileSummary();
    expect(game.session.players.first.cash, 100);
    expect(game.session.players.first.inventory.hasWeapons, isFalse);
    expect(game.session.phase, TurnPhase.handoff);
  });

  test('Shop purchases and pending shopping survive resume', () {
    final game = weaponGame(board: weaponBoard(shop: 10), from: 9, dice: 1);
    game.roll();
    game.finishAnimation();
    game.buyWeapon(WeaponType.stabber);
    final restored = GameController(
      session: GameSession.fromJson(game.session.toJson()),
      board: game.board,
    );
    addTearDown(restored.dispose);
    expect(restored.session.phase, TurnPhase.shopping);
    expect(restored.session.players.first.cash, 60);
    expect(restored.weaponCount(WeaponType.stabber), 1);
    expect(restored.session.weaponRules.price(WeaponType.pewPew), 95);
    expect(restored.beginDiceRoll(), isNull);
  });

  for (final type in WeaponType.values) {
    for (final direction in [-1, 1]) {
      test(
        '${type.label} can reach exactly ${type.range} spaces in direction $direction',
        () {
          final game = weaponGame();
          final attacker = game.session.players.first;
          attacker.inventory.stabbers = 1;
          attacker.inventory.pewPews = 1;
          final target = game.session.players[1];
          target.position = 16 + direction * type.range;
          target.cash = 70;
          target.inventory.antidotes = 1;
          game.roll();
          game.finishAnimation();
          expect(game.session.phase, TurnPhase.weaponAction);
          expect(game.weaponTargets(type), contains(1));
          final restored = GameController(
            session: GameSession.fromJson(game.session.toJson()),
            board: game.board,
          );
          addTearDown(restored.dispose);
          expect(restored.useWeapon(type, 1), isTrue);
          expect(restored.session.players[1].position, 0);
          expect(restored.session.players[1].cash, 70);
          expect(restored.session.players[1].inventory.antidotes, 1);
          expect(restored.weaponCount(type), 0);
          expect(restored.session.players.first.inventory.stars, 3);
          expect(restored.session.players.first.cash, 100);
          expect(
            restored.weaponCount(
              type == WeaponType.stabber
                  ? WeaponType.pewPew
                  : WeaponType.stabber,
            ),
            1,
          );
          expect(restored.useWeapon(type, 1), isFalse);
          expect(restored.session.players.first.inventory.stars, 3);
          restored.finishAnimation();
          restored.dismissTileSummary();
          expect(restored.session.phase, TurnPhase.handoff);
        },
      );
    }
    test(
      '${type.label} rejects targets outside range, self, and unowned weapons',
      () {
        final game = weaponGame();
        game.session.players.first.inventory.stabbers = 1;
        game.session.players.first.inventory.pewPews = 1;
        game.session.players[1].position = 16 + type.range + 1;
        game.session.players[2].position = 17;
        game.roll();
        game.finishAnimation();
        expect(game.useWeapon(type, 0), isFalse);
        expect(game.useWeapon(type, 1), isFalse);
        expect(game.useWeapon(type, 99), isFalse);
        if (type == WeaponType.stabber) {
          game.session.players.first.inventory.stabbers = 0;
        } else {
          game.session.players.first.inventory.pewPews = 0;
        }
        expect(game.useWeapon(type, 2), isFalse);
      },
    );
    test('${type.label} requires rolling a 6', () {
      final game = weaponGame(dice: 5);
      game.session.players.first.inventory.stabbers = 1;
      game.session.players.first.inventory.pewPews = 1;
      game.session.players[1].position = 16;
      game.roll();
      game.finishAnimation();
      expect(game.session.phase, TurnPhase.handoff);
      expect(game.useWeapon(type, 1), isFalse);
      expect(game.session.players[1].position, 16);
    });
  }

  test('An optional attack can be skipped without consuming a weapon', () {
    final game = weaponGame();
    game.session.players.first.inventory.pewPews = 1;
    game.session.players[1].position = 20;
    game.roll();
    game.finishAnimation();
    expect(game.session.phase, TurnPhase.weaponAction);
    game.skipWeaponAction();
    expect(game.session.phase, TurnPhase.handoff);
    expect(game.session.players.first.inventory.pewPews, 1);
    expect(game.session.players[1].position, 20);
    expect(game.session.players.first.inventory.stars, 0);
  });

  test('Kills add three stars to existing stars across turns without cash', () {
    final game = weaponGame();
    final attacker = game.session.players.first;
    attacker.inventory
      ..stabbers = 2
      ..stars = 2;
    game.session.players[1].position = 17;
    game.roll();
    game.finishAnimation();
    expect(game.useWeapon(WeaponType.stabber, 1), isTrue);
    expect(attacker.inventory.stars, 5);
    expect(attacker.cash, 100);
    game.finishAnimation();
    game.dismissTileSummary();
    for (var opponent = 1; opponent <= 2; opponent++) {
      expect(game.session.currentPlayerIndex, opponent);
      game.acknowledgeHandoff();
      game.roll();
      game.finishAnimation();
    }
    game.acknowledgeHandoff();
    expect(game.session.currentPlayerIndex, 0);
    game.session.players[1].position = 23;
    game.roll();
    game.finishAnimation();
    expect(game.useWeapon(WeaponType.stabber, 1), isTrue);
    expect(attacker.inventory.stars, 8);
    expect(attacker.inventory.stabbers, 0);
    expect(attacker.cash, 100);
    final restored = GameController(
      session: GameSession.fromJson(game.session.toJson()),
      board: game.board,
    );
    addTearDown(restored.dispose);
    expect(restored.session.players.first.inventory.stars, 8);
    expect(restored.useWeapon(WeaponType.stabber, 1), isFalse);
    expect(restored.session.players.first.inventory.stars, 8);
    expect(restored.session.players.first.cash, 100);
  });

  test(
    'Kill stars cause a full sentence on the next move into police range',
    () {
      final game = weaponGame(
        board: weaponBoard(police: 20, jails: [10, 30]),
        from: 16,
        dice: 4,
      );
      final attacker = game.session.players.first;
      attacker.inventory
        ..stabbers = 1
        ..stars = 1;
      game.session.players[1].position = 16;
      game.roll();
      expect(game.session.phase, TurnPhase.preMoveWeaponChoice);
      expect(game.useWeapon(WeaponType.stabber, 1), isTrue);
      expect(attacker.inventory.stars, 4);
      expect(attacker.inventory.hasWeapons, isFalse);
      expect(attacker.cash, 100);
      game.finishAnimation();
      game.dismissTileSummary();
      for (var opponent = 1; opponent <= 2; opponent++) {
        game.acknowledgeHandoff();
        game.roll();
        game.finishAnimation();
      }
      game.acknowledgeHandoff();
      expect(game.session.currentPlayerIndex, 0);
      expect(game.roll()!.path, [17, 10]);
      expect(attacker.position, 10);
      expect(attacker.inventory.stars, 0);
      expect(attacker.skipTurns, 4);
      expect(attacker.cash, 100);
      expect(game.session.pendingPoliceFine, isNull);
      game.finishAnimation();
      expect(game.session.phase, TurnPhase.specialReview);
    },
  );

  for (final position in [17, 23]) {
    test(
      'Weapons at position $position cause arrest within 3 spaces of police 20',
      () {
        final game = weaponGame(
          board: weaponBoard(police: 20, jails: [10, 30]),
          from: position,
        );
        final player = game.session.players.first;
        player.inventory.stabbers = 2;
        player.inventory.pewPews = 1;
        player.inventory.boats = 1;
        player.inventory.antidotes = 1;
        game.session.players[1].position = 25;
        final result = game.roll()!;
        expect(result.path, [position]);
        expect(player.position, position);
        expect(game.session.pendingPoliceJail, position == 17 ? 10 : 30);
        expect(player.inventory.stabbers, 0);
        expect(player.inventory.pewPews, 0);
        expect(player.inventory.boats, 1);
        expect(player.inventory.antidotes, 1);
        expect(player.cash, 100);
        game.finishAnimation();
        expect(game.session.phase, TurnPhase.jailChoice);
        expect(game.useWeapon(WeaponType.pewPew, 1), isFalse);
      },
    );
  }

  test(
    'Carrying a weapon stops dice movement on first entry into police range',
    () {
      final game = weaponGame(
        board: weaponBoard(police: 20, jails: [10, 30]),
        from: 14,
      );
      game.session.players.first.inventory.pewPews = 1;
      expect(game.roll()!.path, [15, 16, 17]);
      expect(game.session.players.first.position, 17);
      expect(game.session.pendingPoliceJail, 10);
      expect(game.session.players.first.inventory.hasWeapons, isFalse);
    },
  );

  test('Four spaces from police is safe when moving away', () {
    final game = weaponGame(
      board: weaponBoard(police: 20, jails: [10, 35]),
      from: 24,
      dice: 1,
    );
    game.session.players.first.inventory.stabbers = 1;
    expect(game.roll()!.path, [25]);
    expect(game.session.players.first.inventory.stabbers, 1);
    expect(game.session.pendingPoliceFine, isNull);
  });

  test(
    'Buying a weapon near police immediately confiscates it and starts an arrest',
    () {
      final game = weaponGame(
        board: weaponBoard(shop: 7, police: 10, jails: [3, 19]),
        from: 6,
        dice: 1,
      );
      game.roll();
      game.finishAnimation();
      expect(game.session.phase, TurnPhase.shopping);
      expect(game.buyWeapon(WeaponType.stabber), isTrue);
      expect(game.session.players.first.cash, 60);
      expect(game.session.players.first.inventory.stabbers, 0);
      expect(game.session.players.first.position, 7);
      expect(game.session.pendingPoliceJail, 3);
      expect(game.session.pendingShopTile, isNull);
      expect(game.session.phase, TurnPhase.animating);
      game.finishAnimation();
      expect(game.session.phase, TurnPhase.jailChoice);
      game.choosePolicePenalty(payFine: false);
      expect(game.session.players.first.position, 3);
      expect(game.session.phase, TurnPhase.animating);
      game.finishAnimation();
      game.dismissTileSummary();
      expect(game.session.phase, TurnPhase.handoff);
      expect(game.session.players.first.skipTurns, 1);
    },
  );

  test('A long forced move cannot pass through police range with weapons', () {
    final original = weaponBoard(police: 20, jails: [10, 35]);
    final tiles = original.tiles.toList();
    tiles[12] = tiles[12].withChanges({'type': 'moveForward', 'amount': 15});
    final game = weaponGame(board: BoardDefinition(tiles), from: 11, dice: 1);
    game.session.players.first.inventory.stabbers = 1;
    final action = game.roll()!;
    expect(action.path, [12, 13, 14, 15, 16, 17]);
    expect(game.session.players.first.inventory.stabbers, 0);
    expect(game.session.players.first.position, 17);
    expect(game.session.pendingPoliceJail, 10);
    game.finishAnimation();
    expect(game.session.phase, TurnPhase.jailChoice);
  });

  test('An arrest with confiscation resumes without restoring weapons', () {
    final game = weaponGame(
      board: weaponBoard(police: 20, jails: [10, 30]),
      from: 17,
    );
    game.session.players.first.inventory.stabbers = 1;
    game.session.players.first.inventory.pewPews = 2;
    game.roll();
    game.finishAnimation();
    final restored = GameController(
      session: GameSession.fromJson(game.session.toJson()),
      board: game.board,
    );
    addTearDown(restored.dispose);
    expect(restored.session.phase, TurnPhase.jailChoice);
    expect(restored.session.players.first.inventory.hasWeapons, isFalse);
    expect(restored.session.players.first.position, 17);
    expect(restored.session.pendingPoliceJail, 10);
    restored.choosePolicePenalty(payFine: true);
    restored.dismissTileSummary();
    expect(restored.session.phase, TurnPhase.handoff);
    expect(restored.session.players.first.cash, 80);
    expect(restored.session.players.first.position, 17);
    expect(restored.session.players.first.skipTurns, 0);
  });

  test(
    'Older inventories start with no weapons and new prices default correctly',
    () {
      final inventory = PlayerInventory.fromJson({'cash': 75, 'boats': 1});
      expect(inventory.stabbers, 0);
      expect(inventory.pewPews, 0);
      expect(const WeaponRules().price(WeaponType.stabber), 40);
      expect(const WeaponRules().price(WeaponType.pewPew), 95);
      expect(() => PlayerInventory(stabbers: -1), throwsArgumentError);
    },
  );
}
