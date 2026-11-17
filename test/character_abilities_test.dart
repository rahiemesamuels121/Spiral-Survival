import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';
import 'package:spiral_pass_play/features/game/presentation/game_screen.dart';
import 'package:spiral_pass_play/features/game/application/game_controller.dart';
import 'package:spiral_pass_play/features/game/domain/board_definition.dart';
import 'package:spiral_pass_play/features/game/domain/game_session.dart';
import 'package:spiral_pass_play/features/game/domain/player_icon.dart';
import 'package:spiral_pass_play/features/game/domain/weapon.dart';
import 'package:spiral_pass_play/features/multiplayer/domain/room_protocol.dart';

BoardDefinition _board() => BoardDefinition([
  for (var i = 0; i < 50; i++)
    BoardTile(
      index: i,
      x: .1 + (i % 10) * .08,
      y: .1 + (i ~/ 10) * .16,
      type: switch (i) {
        0 => TileType.start,
        1 => TileType.sea,
        2 => TileType.surf,
        3 => TileType.lion,
        4 => TileType.secretSociety,
        5 => TileType.hospital,
        6 => TileType.shop,
        49 => TileType.finish,
        _ => TileType.normal,
      },
      destination: i == 3 ? 5 : null,
    ),
]);
GameController _game(PlayerIcon icon) => GameController.newGame(
  names: ['One', 'Two'],
  colors: [1, 2],
  board: _board(),
  diceRoller: () => 1,
  icons: [icon, PlayerIcon.paw],
);
OnlineRoom _room(GameSession session) => OnlineRoom(
  code: 'ABCDEFGH',
  hostId: 'u1',
  members: const {'u1': 'One', 'u2': 'Two'},
  playerOrder: const ['u1', 'u2'],
  status: 'playing',
  revision: 1,
  state: jsonEncode(session.toJson()),
  outcome: '',
  lastRequestId: '',
  lastError: '',
  hostSeen: DateTime.now(),
  expiresAt: DateTime.now().add(const Duration(hours: 1)),
);

void main() {
  testWidgets(
    'Only a nearby Secret Agent gets the remote hiring button and discounted price',
    (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      SharedPreferencesAsyncPlatform.instance =
          InMemorySharedPreferencesAsync.empty();
      for (final icon in PlayerIcon.selectable) {
        final g = _game(icon);
        g.session.currentPlayer.position = 7;
        g.session.currentPlayer.cash = 150;
        await tester.runAsync(() async {
          await tester.pumpWidget(MaterialApp(home: GameScreen(controller: g)));
          await Future<void>.delayed(const Duration(milliseconds: 100));
        });
        await tester.pump();
        if (icon == PlayerIcon.secretAgent) {
          expect(find.byTooltip('Secret Society'), findsOneWidget);
          await tester.tap(find.byTooltip('Secret Society'));
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 400));
          final hire = find.text(r'HIRE HITMAN · $150');
          await tester.ensureVisible(hire);
          await tester.tap(hire);
          await tester.pump();
          expect(g.session.currentPlayer.cash, 0);
          expect(g.session.hitmanTile, 7);
          expect(g.session.phase, TurnPhase.ready);
          await tester.tap(find.text('CLOSE'));
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 400));
          expect(find.byTooltip('Hitman contract'), findsOneWidget);
        } else {
          expect(find.byTooltip('Secret Society'), findsNothing);
          expect(g.canHireHitman, isFalse);
        }
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
        g.dispose();
      }
    },
  );

  test(
    'Only Secret Agents can hire from up to three spaces either side of Secret Society',
    () {
      for (final icon in PlayerIcon.selectable) {
        for (final position in [0, 1, 2, 3, 4, 5, 6, 7, 8]) {
          final g = _game(icon);
          addTearDown(g.dispose);
          g.session.currentPlayer.position = position;
          g.session.currentPlayer.cash = 300;
          final allowed =
              position == 4 ||
              icon == PlayerIcon.secretAgent && (position - 4).abs() <= 3;
          expect(
            g.canAccessSecretSociety,
            allowed,
            reason: '$icon at $position',
          );
          expect(g.hireHitman(20), allowed, reason: '$icon at $position');
          expect(
            g.session.currentPlayer.cash,
            allowed ? (icon == PlayerIcon.secretAgent ? 150 : 100) : 300,
          );
        }
      }
    },
  );

  test(
    'Remote Secret Society access rejects inactive turn phases',
    () {
      final g = _game(PlayerIcon.secretAgent);
      addTearDown(g.dispose);
      g.session.currentPlayer.position = 7;
      g.session.currentPlayer.cash = 200;
      for (final phase in [
        TurnPhase.rolling,
        TurnPhase.animating,
        TurnPhase.handoff,
        TurnPhase.specialReview,
        TurnPhase.hospitalChoice,
      ]) {
        g.session.phase = phase;
        expect(g.canHireHitman, isFalse);
      }
      g.session.phase = TurnPhase.ready;
      final result = executeRoomCommand(
        room: _room(g.session),
        senderId: 'u1',
        expectedRevision: 1,
        action: 'hitmanHire',
        args: {'tile': 30},
        board: g.board,
      );
      final next = GameSession.fromJson(jsonDecode(result.state));
      expect(next.hitmanOwnerId, 'p1');
      expect(next.hitmanTile, 30);
      expect(next.players.first.cash, 50);
      g.session.currentPlayer.position = 8;
      expect(
        () => executeRoomCommand(
          room: _room(g.session),
          senderId: 'u1',
          expectedRevision: 1,
          action: 'hitmanHire',
          args: {'tile': 30},
          board: g.board,
        ),
        throwsStateError,
      );
    },
  );

  test('Only the three character classes can be selected in new matches', () {
    expect(PlayerIcon.selectable, [
      PlayerIcon.paw,
      PlayerIcon.secretAgent,
      PlayerIcon.swimmer,
    ]);
    expect(
      () => GameController.newGame(
        names: ['One', 'Two'],
        colors: [1, 2],
        board: _board(),
        icons: [PlayerIcon.number, PlayerIcon.star],
      ),
      throwsArgumentError,
    );
  });

  test(
    'Cat Whisperer passes a lion without meat, injury or consuming supplies',
    () {
      final g = _game(PlayerIcon.paw);
      addTearDown(g.dispose);
      g.session.currentPlayer.position = 2;
      final items = g.session.currentPlayer.inventory;
      items.rawMeat = 2;
      items.healthPacks = 1;
      g.roll();
      expect(g.session.currentPlayer.position, 3);
      expect(g.session.currentPlayer.isInjured, isFalse);
      expect(items.rawMeat, 2);
      expect(items.healthPacks, 1);
      expect(g.session.pendingHospital, isFalse);
      expect(g.session.message, contains('CAT WHISPERER'));
    },
  );

  test('Other characters still need raw meat or a health kit at lions', () {
    final g = _game(PlayerIcon.secretAgent);
    addTearDown(g.dispose);
    g.session.currentPlayer.position = 2;
    g.roll();
    expect(g.session.currentPlayer.position, 5);
    expect(g.session.currentPlayer.isInjured, isTrue);
    expect(g.session.pendingHospital, isTrue);
  });

  test('Swimmer crosses consecutive sea and surf without a boat', () {
    final g = _game(PlayerIcon.swimmer);
    addTearDown(g.dispose);
    // Land on water; swimming reaches the lion, which consumes the carried meat.
    g.session.currentPlayer.inventory.rawMeat = 1;
    g.roll();
    expect(g.session.currentPlayer.position, 3);
    expect(g.session.currentPlayer.inventory.boats, 0);
    expect(g.session.currentPlayer.isInjured, isFalse);
    expect(g.session.message, contains('SWIMMER'));
    expect(g.session.currentPlayer.inventory.rawMeat, 0);
  });

  for (final icon in [PlayerIcon.paw, PlayerIcon.secretAgent]) {
    test('$icon still requires a boat at surf', () {
      final g = _game(icon);
      addTearDown(g.dispose);
      g.session.currentPlayer.position = 1;
      g.roll();
      expect(g.session.currentPlayer.position, 0);
      expect(g.session.message, contains('drowned'));
    });
  }

  test('Legacy SURF spaces load as a water hazard', () {
    final legacy = _board().toJson();
    final tile = (legacy['tiles'] as List)[2] as Map;
    tile['type'] = 'normal';
    tile['label'] = 'SURF';
    final board = BoardDefinition.fromJson(legacy);
    expect(board.tiles[2].type, TileType.surf);
    expect(board.tiles[2].isWater, isTrue);
  });

  test('Secret Agent adds exactly three route spaces to both weapons', () {
    final g = _game(PlayerIcon.secretAgent);
    addTearDown(g.dispose);
    g.session.currentPlayer.position = 20;
    g.session.currentPlayer.inventory.stabbers = 1;
    g.session.currentPlayer.inventory.pewPews = 1;
    g.session.lastDice = 6;
    g.session.phase = TurnPhase.preMoveWeaponChoice;
    expect(g.weaponRange(WeaponType.stabber), 8);
    expect(g.weaponRange(WeaponType.pewPew), 13);
    g.session.players[1].position = 28;
    expect(g.weaponTargets(WeaponType.stabber), [1]);
    g.session.players[1].position = 29;
    expect(g.weaponTargets(WeaponType.stabber), isEmpty);
    g.session.players[1].position = 33;
    expect(g.weaponTargets(WeaponType.pewPew), [1]);
    g.session.players[1].position = 34;
    expect(g.weaponTargets(WeaponType.pewPew), isEmpty);
    g.session.players[1].position = 28;
    expect(g.useWeapon(WeaponType.stabber, 1), isTrue);
    expect(g.session.players[1].position, 0);
  });

  test('Other classes keep standard weapon ranges', () {
    for (final icon in [PlayerIcon.paw, PlayerIcon.swimmer]) {
      final g = _game(icon);
      addTearDown(g.dispose);
      expect(g.weaponRange(WeaponType.stabber), 5);
      expect(g.weaponRange(WeaponType.pewPew), 10);
    }
  });

  test('Secret Agent pays 150 for hitman and cannot hire with 149', () {
    final g = _game(PlayerIcon.secretAgent);
    addTearDown(g.dispose);
    g.session.currentPlayer.position = 4;
    g.session.pendingShopTile = 4;
    g.session.phase = TurnPhase.shopping;
    g.session.currentPlayer.cash = 149;
    expect(g.hitmanHirePrice, 150);
    expect(g.hireHitman(20), isFalse);
    g.session.currentPlayer.cash = 150;
    expect(g.hireHitman(20), isTrue);
    expect(g.session.currentPlayer.cash, 0);
    expect(
      GameSession.fromJson(g.session.toJson()).players.first.icon,
      PlayerIcon.secretAgent,
    );
    expect(PlayerIcon.secretAgent.secretSocietyPrice(20), 0);
    expect(PlayerIcon.secretAgent.secretSocietyPrice(95), 45);
  });

  test('Other characters pay full Secret Society prices', () {
    final g = _game(PlayerIcon.swimmer);
    addTearDown(g.dispose);
    expect(g.hitmanHirePrice, 200);
    expect(g.session.currentPlayer.icon.secretSocietyPrice(20), 20);
  });

  test('Secret Agent discount does not apply to ordinary weapon shops', () {
    final g = _game(PlayerIcon.secretAgent);
    addTearDown(g.dispose);
    g.session.currentPlayer.position = 6;
    g.session.pendingShopTile = 6;
    g.session.phase = TurnPhase.shopping;
    g.session.currentPlayer.cash = 100;
    expect(g.buyWeapon(WeaponType.stabber), isTrue);
    expect(g.session.currentPlayer.cash, 60);
  });

  test(
    'Online authoritative rules apply the selected class and reject switching',
    () {
      final g = _game(PlayerIcon.paw);
      addTearDown(g.dispose);
      g.session.currentPlayer.position = 2;
      final result = executeRoomCommand(
        room: _room(g.session),
        senderId: 'u1',
        expectedRevision: 1,
        action: 'roll',
        args: {},
        board: g.board,
        diceRoller: () => 1,
      );
      final next = GameSession.fromJson(jsonDecode(result.state));
      expect(next.players.first.position, 3);
      expect(next.players.first.icon, PlayerIcon.paw);
      expect(next.players.first.isInjured, isFalse);
      expect(
        () => executeRoomCommand(
          room: _room(g.session),
          senderId: 'u1',
          expectedRevision: 1,
          action: 'playerIcon',
          args: {'icon': 'swimmer'},
          board: g.board,
        ),
        throwsStateError,
      );
      expect(
        () => executeRoomCommand(
          room: _room(g.session),
          senderId: 'u1',
          expectedRevision: 1,
          action: 'roll',
          args: {'icon': 'swimmer'},
          board: g.board,
        ),
        throwsStateError,
      );
      g.changePlayerIcon(PlayerIcon.swimmer);
      expect(g.session.currentPlayer.icon, PlayerIcon.paw);
    },
  );
}
