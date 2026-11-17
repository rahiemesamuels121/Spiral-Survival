import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:spiral_pass_play/app/theme.dart';
import 'package:spiral_pass_play/features/game/application/game_controller.dart';
import 'package:spiral_pass_play/features/game/data/board_repository.dart';
import 'package:spiral_pass_play/features/game/domain/game_session.dart';
import 'package:spiral_pass_play/features/game/domain/medical_item.dart';
import 'package:spiral_pass_play/features/game/domain/player_icon.dart';
import 'package:spiral_pass_play/features/multiplayer/application/online_game_controller.dart';
import 'package:spiral_pass_play/features/multiplayer/data/room_service.dart';
import 'package:spiral_pass_play/features/multiplayer/domain/room_protocol.dart';

class TestConnection extends RoomService {
  TestConnection(super.board);
  final actions = <String>[];
  final arguments = <Map<String, dynamic>>[];
  @override
  Future<void> send(String action, Map<String, dynamic> args) async {
    actions.add(action);
    arguments.add(Map<String, dynamic>.from(args));
  }

  void publish(OnlineRoom value) {
    room = value;
    notifyListeners();
  }
}

OnlineRoom snapshot(
  GameSession game, {
  int revision = 1,
  String outcome = '',
}) => OnlineRoom(
  code: 'ABCDEFGH',
  hostId: 'u0',
  members: const {'u0': 'One', 'u1': 'Two'},
  playerOrder: const ['u0', 'u1'],
  status: 'playing',
  revision: revision,
  state: jsonEncode(game.toJson()),
  outcome: outcome,
  lastRequestId: '',
  lastError: '',
  hostSeen: DateTime.now(),
  expiresAt: DateTime.now().add(const Duration(hours: 24)),
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late GameController game;
  late TestConnection connection;
  late OnlineGameController client;
  setUp(() async {
    final board = await const BoardRepository().loadReferenceBoard();
    game = GameController.newGame(
      names: ['One', 'Two'],
      colors: AppTheme.playerColors.map((c) => c.toARGB32()).toList(),
      board: board,
    );
    connection = TestConnection(board)
      ..uid = 'u0'
      ..connected = true
      ..room = snapshot(game.session);
    client = OnlineGameController(connection: connection);
  });
  tearDown(() {
    client.dispose();
    connection.dispose();
    game.dispose();
  });

  test('Online character changes are disabled on every turn', () {
    expect(client.canChangePlayerIcon, isFalse);
    client.changePlayerIcon(PlayerIcon.swimmer);
    expect(connection.actions, isEmpty);
    connection.uid = 'u1';
    expect(client.canChangePlayerIcon, isFalse);
    client.changePlayerIcon(PlayerIcon.secretAgent);
    expect(connection.actions, isEmpty);
    expect(client.session.players.first.icon, PlayerIcon.number);
    expect(client.session.players[1].icon, PlayerIcon.number);
  });
  test(
    'Only the current seat can send a request and local dice never mutate state',
    () async {
      connection.uid = 'u1';
      client.beginDiceRoll();
      client.dismissTileSummary();
      expect(connection.actions, isEmpty);
      connection.uid = 'u0';
      client.beginDiceRoll();
      client.beginDiceRoll();
      expect(connection.actions, ['roll']);
      expect(client.session.lastDice, isNull);
      expect(client.session.currentPlayer.position, 0);
      await Future<void>.delayed(Duration.zero);
    },
  );

  test('Committed moves animate before enabling the next player', () {
    final result = executeRoomCommand(
      room: connection.room!,
      senderId: 'u0',
      expectedRevision: 1,
      action: 'roll',
      args: {},
      board: connection.board,
      diceRoller: () => 1,
    );
    connection.uid = 'u1';
    connection.publish(
      snapshot(
        GameSession.fromJson(jsonDecode(result.state)),
        revision: 2,
        outcome: result.outcome,
      ),
    );
    expect(client.session.phase, TurnPhase.animating);
    expect(client.canAct, isFalse);
    expect(client.lastOutcome!.path, [1]);
    client.finishAnimation();
    expect(client.session.phase, TurnPhase.ready);
    expect(client.localResult, isNull);
    expect(client.canAct, isTrue);
    expect(connection.actions, isEmpty);
    expect(client.canAct, isTrue);
  });

  test(
    'A slow client synchronizes new state while movements finish in order',
    () {
      final first = executeRoomCommand(
        room: connection.room!,
        senderId: 'u0',
        expectedRevision: 1,
        action: 'roll',
        args: {},
        board: connection.board,
        diceRoller: () => 1,
      );
      final next = snapshot(
        GameSession.fromJson(jsonDecode(first.state)),
        revision: 2,
        outcome: first.outcome,
      );
      connection.publish(next);
      final second = executeRoomCommand(
        room: next,
        senderId: 'u1',
        expectedRevision: 2,
        action: 'roll',
        args: {},
        board: connection.board,
        diceRoller: () => 1,
      );
      connection.publish(
        snapshot(
          GameSession.fromJson(jsonDecode(second.state)),
          revision: 3,
          outcome: second.outcome,
        ),
      );
      expect(client.lastOutcome!.sequence, 2);
      expect(client.session.players[1].position, 1);
      client.finishAnimation();
      expect(client.lastOutcome!.sequence, 3);
      expect(client.session.phase, TurnPhase.animating);
      client.finishAnimation();
      expect(client.session.phase, TurnPhase.ready);
      expect(client.session.players[1].position, 1);
    },
  );

  test('Connection loss disables every local game action', () {
    connection.connected = false;
    client.beginDiceRoll();
    client.chooseMovement();
    client.chooseHospitalTreatment(pay: true);
    client.useHealthPack();
    expect(client.buyMedicalItem(MedicalItem.antidote), isFalse);
    expect(client.canAct, isFalse);
    expect(connection.actions, isEmpty);
    expect(client.status, contains('Reconnecting'));
  });

  test(
    'Medical purchase waits for the host snapshot before changing inventory',
    () async {
      game.session.currentPlayer
        ..position = 62
        ..cash = 20;
      game.session
        ..phase = TurnPhase.shopping
        ..pendingShopTile = 62;
      connection.publish(snapshot(game.session, revision: 2));
      client.finishAnimation();
      expect(client.isHospitalShopping, isTrue);

      expect(client.buyMedicalItem(MedicalItem.healthPack), isTrue);
      expect(client.buyMedicalItem(MedicalItem.antidote), isFalse);
      expect(connection.actions, ['medicalBuy']);
      expect(connection.arguments, [
        {'item': 'healthPack'},
      ]);
      expect(client.session.currentPlayer.cash, 20);
      expect(client.session.currentPlayer.inventory.healthPacks, 0);

      final committed = executeRoomCommand(
        room: connection.room!,
        senderId: 'u0',
        expectedRevision: 2,
        action: connection.actions.single,
        args: connection.arguments.single,
        board: connection.board,
      );
      connection.publish(
        snapshot(
          GameSession.fromJson(jsonDecode(committed.state)),
          revision: 3,
        ),
      );
      expect(client.session.currentPlayer.cash, 10);
      expect(client.session.currentPlayer.inventory.healthPacks, 1);
      expect(client.session.phase, TurnPhase.shopping);
      await Future<void>.delayed(Duration.zero);
    },
  );

  test('Health pack treatment is requested without healing locally', () async {
    game.session.currentPlayer
      ..position = 62
      ..isInjured = true
      ..cash = 0;
    game.session.currentPlayer.inventory.healthPacks = 1;
    game.session
      ..phase = TurnPhase.hospitalChoice
      ..pendingHospital = true;
    connection.publish(snapshot(game.session, revision: 2));
    client.finishAnimation();

    client.useHealthPack();
    client.useHealthPack();
    expect(connection.actions, ['healthPack']);
    expect(connection.arguments.single, isEmpty);
    expect(client.session.currentPlayer.isInjured, isTrue);
    expect(client.session.currentPlayer.inventory.healthPacks, 1);

    final committed = executeRoomCommand(
      room: connection.room!,
      senderId: 'u0',
      expectedRevision: 2,
      action: connection.actions.single,
      args: connection.arguments.single,
      board: connection.board,
    );
    connection.publish(
      snapshot(GameSession.fromJson(jsonDecode(committed.state)), revision: 3),
    );
    expect(client.session.currentPlayer.isInjured, isFalse);
    expect(client.session.currentPlayer.inventory.healthPacks, 0);
    expect(client.session.phase, TurnPhase.shopping);
    await Future<void>.delayed(Duration.zero);
  });

  test(
    'Each device dismisses its result while the next player can roll',
    () async {
      game.session.currentPlayer.position = 1;
      final initial = snapshot(game.session, revision: 2);
      connection.publish(initial);
      client.finishAnimation();
      final otherConnection = TestConnection(connection.board)
        ..uid = 'u1'
        ..connected = true
        ..room = initial;
      final other = OnlineGameController(connection: otherConnection);
      addTearDown(other.dispose);
      addTearDown(otherConnection.dispose);

      final pickup = executeRoomCommand(
        room: initial,
        senderId: 'u0',
        expectedRevision: 2,
        action: 'roll',
        args: {},
        board: connection.board,
        diceRoller: () => 1,
      );
      final next = snapshot(
        GameSession.fromJson(jsonDecode(pickup.state)),
        revision: 3,
        outcome: pickup.outcome,
      );
      connection.publish(next);
      otherConnection.publish(next);
      expect(client.localResult, isNull);
      expect(other.localResult, isNull);
      client.finishAnimation();
      other.finishAnimation();
      expect(client.session.currentPlayerIndex, 1);
      expect(other.session.currentPlayerIndex, 1);
      expect(client.localPlayerId, 'p1');
      expect(other.localPlayerId, 'p2');
      expect(client.localResult!.currentPlayer.id, 'p1');
      expect(other.localResult!.currentPlayer.id, 'p1');
      expect(other.canAct, isFalse);

      other.dismissTileSummary();
      expect(other.localResult, isNull);
      expect(other.canAct, isTrue);
      expect(otherConnection.actions, isEmpty);
      expect(client.localResult, isNotNull);
      other.beginDiceRoll();
      expect(otherConnection.actions, ['roll']);
      final rolled = executeRoomCommand(
        room: next,
        senderId: 'u1',
        expectedRevision: 3,
        action: 'roll',
        args: {},
        board: connection.board,
        diceRoller: () => 1,
      );
      final latest = snapshot(
        GameSession.fromJson(jsonDecode(rolled.state)),
        revision: 4,
        outcome: rolled.outcome,
      );
      connection.publish(latest);
      otherConnection.publish(latest);
      expect(client.session.players[1].position, 1);
      client.finishAnimation();
      other.finishAnimation();
      expect(client.localResult!.currentPlayer.id, 'p1');
      expect(client.session.currentPlayerIndex, 0);
      expect(client.canAct, isFalse);
      connection.connected = false;
      client.dismissLocalResult();
      expect(
        client.localResult,
        isNull,
      ); // The next ordinary move has no popup.
      expect(connection.actions, isEmpty);
      connection.connected = true;
      expect(client.canAct, isTrue);

      connection.publish(latest); // Heartbeats never replay a dismissed result.
      expect(client.localResult, isNull);
      final reconnected = OnlineGameController(connection: connection);
      addTearDown(reconnected.dispose);
      expect(reconnected.localResult, isNull);
      expect(reconnected.session.currentPlayerIndex, 0);
      await Future<void>.delayed(Duration.zero);
    },
  );

  test(
    'An event result is local while its real hospital decision stays live',
    () {
      game.session.currentPlayer
        ..position = 62
        ..isInjured = true;
      game.session
        ..phase = TurnPhase.eventReveal
        ..pendingCardId = 'cash_30'
        ..pendingHospital = true;
      final event = game.session.toJson();
      game.session
        ..phase = TurnPhase.hospitalChoice
        ..pendingCardId = null;
      connection.publish(
        snapshot(
          game.session,
          revision: 2,
          outcome: jsonEncode({
            'results': [event],
          }),
        ),
      );
      client.finishAnimation();
      expect(client.session.phase, TurnPhase.hospitalChoice);
      expect(client.localResult!.phase, TurnPhase.eventReveal);
      expect(client.canAct, isFalse);
      client.dismissEventCard();
      expect(client.localResult, isNull);
      expect(client.session.phase, TurnPhase.hospitalChoice);
      expect(client.session.pendingHospital, isTrue);
      expect(client.canAct, isTrue);
      expect(connection.actions, isEmpty);
    },
  );

  test('Results queue independently while later turns keep synchronizing', () {
    game.session.currentPlayer.position = 1;
    connection.publish(snapshot(game.session, revision: 2));
    client.finishAnimation();
    final first = executeRoomCommand(
      room: connection.room!,
      senderId: 'u0',
      expectedRevision: 2,
      action: 'roll',
      args: {},
      board: connection.board,
      diceRoller: () => 1,
    );
    final firstRoom = snapshot(
      GameSession.fromJson(jsonDecode(first.state)),
      revision: 3,
      outcome: first.outcome,
    );
    connection.publish(firstRoom);
    final second = executeRoomCommand(
      room: firstRoom,
      senderId: 'u1',
      expectedRevision: 3,
      action: 'roll',
      args: {},
      board: connection.board,
      diceRoller: () => 2,
    );
    final secondRoom = snapshot(
      GameSession.fromJson(jsonDecode(second.state)),
      revision: 4,
      outcome: second.outcome,
    );
    connection.publish(secondRoom);
    expect(client.session.players[0].inventory.boats, 1);
    expect(client.session.players[1].inventory.boats, 1);
    expect(client.localResult, isNull);
    client.finishAnimation();
    expect(client.localResult, isNull);
    client.finishAnimation();
    expect(client.localResult!.currentPlayer.id, 'p1');
    client.dismissLocalResult();
    expect(client.localResult!.currentPlayer.id, 'p2');
    client.dismissLocalResult();
    expect(client.localResult, isNull);
    expect(client.session.currentPlayerIndex, 0);
    expect(client.canAct, isTrue);
    expect(connection.actions, isEmpty);
    connection.publish(secondRoom);
    expect(client.localResult, isNull);
  });

  for (final pay in [true, false]) {
    test(
      'Online ${pay ? 'bribe' : 'jail refusal'} keeps decisions and results local',
      () async {
        game.session.currentPlayer
          ..position = 15
          ..cash = 100;
        final initial = snapshot(game.session, revision: 2);
        connection.publish(initial);
        client.finishAnimation();
        final otherConnection = TestConnection(connection.board)
          ..uid = 'u1'
          ..connected = true
          ..room = initial;
        final other = OnlineGameController(connection: otherConnection);
        addTearDown(other.dispose);
        addTearDown(otherConnection.dispose);
        final encounter = executeRoomCommand(
          room: initial,
          senderId: 'u0',
          expectedRevision: 2,
          action: 'roll',
          args: {},
          board: connection.board,
          diceRoller: () => 1,
        );
        final decision = snapshot(
          GameSession.fromJson(jsonDecode(encounter.state)),
          revision: 3,
          outcome: encounter.outcome,
        );
        connection.publish(decision);
        otherConnection.publish(decision);
        client.finishAnimation();
        other.finishAnimation();
        expect(client.session.phase, TurnPhase.jailChoice);
        expect(client.session.currentPlayer.position, 16);
        expect(client.session.pendingPoliceJail, 13);
        expect(client.localPlayerId, 'p1');
        expect(other.localPlayerId, 'p2');
        expect(client.localResult, isNotNull);
        client.dismissLocalResult();
        other.dismissLocalResult();
        expect(client.canAct, isTrue);
        expect(other.canAct, isFalse);
        client.choosePolicePenalty(payFine: pay);
        client.choosePolicePenalty(payFine: pay);
        expect(connection.actions, ['police']);
        expect(connection.arguments, [
          {'pay': pay},
        ]);
        expect(client.session.currentPlayer.position, 16);
        expect(client.session.currentPlayer.cash, 100);
        final chosen = executeRoomCommand(
          room: decision,
          senderId: 'u0',
          expectedRevision: 3,
          action: connection.actions.single,
          args: connection.arguments.single,
          board: connection.board,
        );
        final committed = snapshot(
          GameSession.fromJson(jsonDecode(chosen.state)),
          revision: 4,
          outcome: chosen.outcome,
        );
        connection.publish(committed);
        otherConnection.publish(committed);
        if (!pay) {
          expect(client.session.phase, TurnPhase.animating);
          expect(client.lastOutcome!.path, [13]);
          expect(client.localResult, isNull);
          client.finishAnimation();
          other.finishAnimation();
        }
        expect(client.session.players.first.position, pay ? 16 : 13);
        expect(client.session.players.first.cash, pay ? 80 : 100);
        expect(client.session.players.first.skipTurns, pay ? 0 : 1);
        expect(client.localResult!.currentPlayer.id, 'p1');
        expect(client.localResult!.currentPlayer.position, pay ? 16 : 13);
        expect(other.localResult!.currentPlayer.id, 'p1');
        other.dismissLocalResult();
        expect(other.canAct, isTrue);
        expect(otherConnection.actions, isEmpty);
        expect(client.localResult, isNotNull);
        client.dismissLocalResult();
        expect(connection.actions, ['police']);
        await Future<void>.delayed(Duration.zero);
      },
    );
  }
}
