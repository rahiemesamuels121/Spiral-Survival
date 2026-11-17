import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:spiral_pass_play/features/game/application/game_controller.dart';
import 'package:spiral_pass_play/features/game/domain/board_definition.dart';
import 'package:spiral_pass_play/features/game/domain/game_session.dart';
import 'package:spiral_pass_play/features/game/domain/medical_item.dart';
import 'package:spiral_pass_play/features/game/domain/weapon.dart';
import 'package:spiral_pass_play/features/game/flame/spiral_board_game.dart';
import 'package:spiral_pass_play/features/multiplayer/domain/private_room_state.dart';
import 'package:spiral_pass_play/features/multiplayer/data/room_service.dart';
import 'package:spiral_pass_play/features/multiplayer/application/online_game_controller.dart';
import 'package:spiral_pass_play/features/multiplayer/domain/room_protocol.dart';

BoardDefinition board() => BoardDefinition([
  for (var i = 0; i < 70; i++)
    BoardTile(
      index: i,
      x: .1 + (i % 10) * .08,
      y: .1 + (i ~/ 10) * .08,
      type: switch (i) {
        0 => TileType.start,
        2 || 3 => TileType.hospital,
        4 => TileType.secretSociety,
        69 => TileType.finish,
        _ => TileType.normal,
      },
    ),
]);

GameController game({DateTime Function()? clock}) => GameController.newGame(
  names: ['One', 'Two', 'Three'],
  colors: [1, 2, 3],
  board: board(),
  clock: clock,
);

void shop(GameController game, int tile) {
  game.session.currentPlayer.position = tile;
  game.session.currentPlayer.cash = 1000;
  game.session.pendingShopTile = tile;
  game.session.phase = TurnPhase.shopping;
}

OnlineRoom _roomSnapshot(
  GameController game, {
  int revision = 1,
  bool public = false,
}) => OnlineRoom(
  code: 'ABCDEFGH',
  hostId: 'u1',
  members: const {'u1': 'One', 'u2': 'Two', 'u3': 'Three'},
  playerOrder: const ['u1', 'u2', 'u3'],
  status: 'playing',
  revision: revision,
  state: jsonEncode(
    public ? publicSession(game.session.toJson()) : game.session.toJson(),
  ),
  outcome: '',
  lastRequestId: '',
  lastError: '',
  hostSeen: DateTime.now(),
  expiresAt: DateTime.now().add(const Duration(hours: 1)),
);

class _PrivateConnection extends RoomService {
  _PrivateConnection(super.board);
  int privateRevision = 1;
  Map<String, dynamic> private = {};
  final commands = <String>[];
  @override
  bool get privateViewReady => privateRevision == room!.revision;
  @override
  GameSession? get visibleSession => GameSession.fromJson(
    applyPrivateView(
      jsonDecode(room!.state) as Map<String, dynamic>,
      privateViewReady ? private : {},
    ),
  );
  @override
  Future<void> send(String action, Map<String, dynamic> args) async {
    commands.add(action);
  }

  void publish() => notifyListeners();
}

void main() {
  test(
    'Online clients wait for private revisions and restore only the viewer contract',
    () async {
      final g = game();
      addTearDown(g.dispose);
      shop(g, 4);
      final connection = _PrivateConnection(g.board)
        ..uid = 'u1'
        ..connected = true
        ..room = _roomSnapshot(g, public: true)
        ..private = privateSessionView(g.session.toJson(), 'p1');
      addTearDown(connection.dispose);
      final client = OnlineGameController(connection: connection);
      addTearDown(client.dispose);
      expect(client.canHireHitman, isTrue);
      expect(client.hireHitman(30), isTrue);
      await Future<void>.delayed(Duration.zero);
      expect(connection.commands, ['hitmanHire']);
      expect(client.session.hitmanOwnerId, isNull);
      g.hireHitman(30);
      connection.room = _roomSnapshot(g, revision: 2, public: true);
      connection.publish();
      expect(client.canAct, isFalse);
      expect(client.session.hitmanTile, isNull);
      connection.privateRevision = 2;
      connection.private = privateSessionView(g.session.toJson(), 'p1');
      connection.publish();
      expect(client.session.hitmanTile, 30);
      expect(client.session.currentPlayer.cash, 800);
      expect(client.canAct, isTrue);
      g.finishShopping();
      g.acknowledgeHandoff();
      connection.room = _roomSnapshot(g, revision: 3, public: true);
      connection.privateRevision = 3;
      connection.private = privateSessionView(g.session.toJson(), 'p1');
      connection.publish();
      expect(client.localPlayerId, 'p1');
      expect(client.canAct, isFalse);
      expect(client.session.hitmanTile, 30);
      expect(HitmanMarker(client).visibleToViewer, isTrue);
      final opponentConnection = _PrivateConnection(g.board)
        ..uid = 'u2'
        ..connected = true
        ..room = _roomSnapshot(g, public: true)
        ..private = privateSessionView(g.session.toJson(), 'p2');
      addTearDown(opponentConnection.dispose);
      final opponent = OnlineGameController(connection: opponentConnection);
      addTearDown(opponent.dispose);
      expect(opponent.session.hitmanHired, isTrue);
      expect(opponent.session.hitmanOwnerId, isNull);
      expect(opponent.session.hitmanTile, isNull);
      expect(HitmanMarker(opponent).visibleToViewer, isFalse);
      expect(opponent.session.players[0].cash, 0);
      expect(opponent.session.players[1].cash, 10);
    },
  );
  test(
    'Hospitals sell out independently and refill at exact five-minute boundaries',
    () {
      var now = DateTime.utc(2026, 11, 16);
      final g = game(clock: () => now);
      addTearDown(g.dispose);
      shop(g, 2);
      expect(g.hospitalKitsAvailable, 2);
      expect(g.buyMedicalItem(MedicalItem.healthPack), isTrue);
      expect(g.buyMedicalItem(MedicalItem.healthPack), isTrue);
      final cash = g.session.currentPlayer.cash;
      expect(g.buyMedicalItem(MedicalItem.healthPack), isFalse);
      expect(g.session.currentPlayer.cash, cash);
      expect(g.session.currentPlayer.inventory.healthPacks, 2);
      expect(g.buyMedicalItem(MedicalItem.antidote), isTrue);
      now = now.add(const Duration(minutes: 4, seconds: 59));
      expect(g.hospitalKitsAvailable, 0);
      now = now.add(const Duration(seconds: 1));
      expect(g.hospitalKitsAvailable, 1);
      expect(g.buyMedicalItem(MedicalItem.healthPack), isTrue);
      expect(g.hospitalKitsAvailable, 0);
      shop(g, 3);
      expect(g.hospitalKitsAvailable, 3);
      now = now.add(const Duration(minutes: 60));
      expect(g.hospitalKitsAvailable, 15);
      expect(g.session.hospitalStocks[2]!.available(now), 12);
    },
  );

  test(
    'Stock and refill remainder survive saves, offline time and clock rollback',
    () {
      var now = DateTime.utc(2026, 11, 16);
      final g = game(clock: () => now);
      addTearDown(g.dispose);
      shop(g, 2);
      g.buyMedicalItem(MedicalItem.healthPack);
      now = now.add(const Duration(minutes: 2));
      final saved =
          jsonDecode(jsonEncode(g.session.toJson())) as Map<String, dynamic>;
      now = now.add(const Duration(minutes: 18));
      final restored = GameController(
        session: GameSession.fromJson(saved),
        board: g.board,
        clock: () => now,
      );
      addTearDown(restored.dispose);
      expect(restored.hospitalKitsAvailable, 5);
      restored.buyMedicalItem(MedicalItem.healthPack);
      now = now.subtract(const Duration(minutes: 1));
      expect(restored.hospitalKitsAvailable, 4);
      expect(restored.hospitalRefillRemaining, const Duration(minutes: 5));
      now = now.add(const Duration(minutes: 6));
      expect(restored.hospitalKitsAvailable, 5);
    },
  );

  test('Legacy saves start with two kits per hospital', () {
    final g = game();
    addTearDown(g.dispose);
    final saved = g.session.toJson()..remove('hospitalStocks');
    final restored = GameController(
      session: GameSession.fromJson(saved),
      board: g.board,
    );
    addTearDown(restored.dispose);
    expect(restored.session.hospitalStocks.keys, unorderedEquals([2, 3]));
    expect(
      restored.session.hospitalStocks.values.map((s) => s.kits),
      everyElement(2),
    );
  });

  test(
    'Hiring requires Secret Society, sufficient cash and one available contract',
    () {
      final g = game();
      addTearDown(g.dispose);
      expect(g.hireHitman(30), isFalse);
      shop(g, 2);
      expect(g.hireHitman(30), isFalse);
      shop(g, 4);
      expect(g.buyWeapon(WeaponType.stabber), isFalse);
      g.session.currentPlayer.cash = 199;
      expect(g.hireHitman(30), isFalse);
      g.session.currentPlayer.cash = 200;
      expect(g.hireHitman(-1), isFalse);
      expect(g.hireHitman(70), isFalse);
      expect(g.hireHitman(30), isTrue);
      expect(g.session.currentPlayer.cash, 0);
      expect(g.session.hitmanTile, 30);
      expect(g.session.hitmanOwnerId, 'p1');
      expect(g.hireHitman(40), isFalse);
      g.session.currentPlayerIndex = 1;
      shop(g, 4);
      expect(g.hireHitman(40), isFalse);
      expect(g.session.currentPlayer.cash, 1000);
      expect(g.useHitman(0), isFalse);
    },
  );

  test(
    'Hitman kills one chosen opponent within inclusive range and becomes available',
    () {
      final g = game();
      addTearDown(g.dispose);
      shop(g, 4);
      g.session.players[1].position = 10;
      g.session.players[2].position = 51;
      g.hireHitman(30);
      expect(
        g.hitmanTargets,
        isEmpty,
      ); // Landing already used this turn to move.
      g.finishShopping();
      g.session.currentPlayerIndex = 0;
      g.session.phase = TurnPhase.ready;
      expect(g.hitmanTargets, [1]);
      expect(g.useHitman(0), isFalse);
      expect(g.useHitman(2), isFalse);
      g.session.players[2].position = 50;
      expect(g.hitmanTargets, [1, 2]);
      final stars = g.session.currentPlayer.inventory.stars;
      expect(g.useHitman(2), isTrue);
      expect(g.session.players[2].position, 0);
      expect(g.session.players[1].position, 10);
      expect(g.session.currentPlayer.inventory.stars, stars);
      expect(g.session.hitmanHired, isFalse);
      expect(g.session.hitmanOwnerId, isNull);
      expect(g.session.hitmanTile, isNull);
      expect(g.session.message, contains('anonymous'));
      expect(g.session.message, isNot(contains('One')));
      expect(g.useHitman(1), isFalse);
      expect(g.beginDiceRoll(), isNull);
      g.finishAnimation();
      g.dismissTileSummary();
      expect(g.session.currentPlayerIndex, 1);
      shop(g, 4);
      expect(g.hireHitman(0), isTrue);
    },
  );

  test(
    'Hitman contract persists across handoffs and resume; marker is private',
    () {
      final g = game();
      addTearDown(g.dispose);
      shop(g, 4);
      g.hireHitman(30);
      final restored = GameController(
        session: GameSession.fromJson(g.session.toJson()),
        board: g.board,
      );
      addTearDown(restored.dispose);
      restored.session.phase = TurnPhase.ready;
      final marker = HitmanMarker(restored);
      expect(marker.visibleToViewer, isTrue);
      restored.session.currentPlayerIndex = 1;
      expect(marker.visibleToViewer, isFalse);
      expect(restored.hitmanTargets, isEmpty);
      restored.session.currentPlayerIndex = 0;
      restored.session.phase = TurnPhase.handoff;
      expect(marker.visibleToViewer, isFalse);
    },
  );

  test('Public state and outcomes exclude contract details and finances', () {
    final g = game();
    addTearDown(g.dispose);
    shop(g, 4);
    g.hireHitman(30);
    final full = g.session.toJson();
    final public = publicSession(full);
    expect(public.containsKey('hitmanOwnerId'), isFalse);
    expect(public.containsKey('hitmanTile'), isFalse);
    for (final player in public['players'] as List) {
      expect(player['cash'], 0);
      expect(player['inventory'], {'cash': 0});
    }
    final owner = applyPrivateView(public, privateSessionView(full, 'p1'));
    expect(owner['hitmanOwnerId'], 'p1');
    expect(owner['hitmanTile'], 30);
    expect(owner['players'][0]['cash'], 800);
    final opponent = applyPrivateView(public, privateSessionView(full, 'p2'));
    expect(opponent.containsKey('hitmanTile'), isFalse);
    expect(opponent['players'][0]['cash'], 0);
    expect(opponent['players'][1]['cash'], 10);
    final outcome = jsonDecode(
      publicOutcome(
        jsonEncode({
          'results': [full],
        }),
      ),
    );
    expect(outcome['results'][0].containsKey('hitmanTile'), isFalse);
    expect(outcome['results'][0]['players'][0]['cash'], 0);
  });

  test('Online commands reject other seats and stale simultaneous hires', () {
    final g = game();
    addTearDown(g.dispose);
    shop(g, 4);
    final r = _roomSnapshot(g);
    RoomCommandResult hire({String sender = 'u1', int revision = 1}) =>
        executeRoomCommand(
          room: r,
          senderId: sender,
          expectedRevision: revision,
          action: 'hitmanHire',
          args: {'tile': 30},
          board: g.board,
        );
    expect(() => hire(sender: 'u2'), throwsStateError);
    expect(() => hire(revision: 0), throwsStateError);
    final hired = hire();
    final committed = GameController(
      session: GameSession.fromJson(jsonDecode(hired.state)),
      board: g.board,
    );
    addTearDown(committed.dispose);
    expect(committed.session.hitmanTile, 30);
    expect(
      () => executeRoomCommand(
        room: _roomSnapshot(committed, revision: 2),
        senderId: 'u1',
        expectedRevision: 1,
        action: 'hitmanHire',
        args: {'tile': 40},
        board: g.board,
      ),
      throwsStateError,
    );
    expect(
      () => executeRoomCommand(
        room: _roomSnapshot(committed, revision: 2),
        senderId: 'u1',
        expectedRevision: 2,
        action: 'hitmanHire',
        args: {'tile': 40},
        board: g.board,
      ),
      throwsStateError,
    );
  });
}
