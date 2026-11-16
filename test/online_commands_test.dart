import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:spiral_pass_play/app/theme.dart';
import 'package:spiral_pass_play/features/game/application/game_controller.dart';
import 'package:spiral_pass_play/features/game/data/board_repository.dart';
import 'package:spiral_pass_play/features/game/domain/board_definition.dart';
import 'package:spiral_pass_play/features/game/domain/game_session.dart';
import 'package:spiral_pass_play/features/game/domain/weapon.dart';
import 'package:spiral_pass_play/features/game/domain/player_icon.dart';
import 'package:spiral_pass_play/features/multiplayer/domain/room_protocol.dart';

OnlineRoom roomFor(
  GameSession session, {
  int revision = 1,
  String status = 'playing',
}) => OnlineRoom(
  code: 'ABCDEFGH',
  hostId: 'u0',
  members: {
    for (var i = 0; i < session.players.length; i++)
      'u$i': session.players[i].name,
  },
  playerOrder: [for (var i = 0; i < session.players.length; i++) 'u$i'],
  status: status,
  revision: revision,
  state: jsonEncode(session.toJson()),
  outcome: '',
  lastRequestId: '',
  lastError: '',
  hostSeen: DateTime.now(),
  expiresAt: DateTime.now().add(const Duration(hours: 24)),
);

List<GameSession> _results(RoomCommandResult result) =>
    ((jsonDecode(result.outcome) as Map<String, dynamic>)['results'] as List)
        .map((value) => GameSession.fromJson(Map<String, dynamic>.from(value)))
        .toList();

BoardDefinition _combatBoard({bool withPolice = false}) => BoardDefinition([
  for (var i = 0; i <= 40; i++)
    BoardTile(
      index: i,
      x: i / 40,
      y: 0,
      type: i == 0
          ? TileType.start
          : i == 40
          ? TileType.finish
          : withPolice && i == 20
          ? TileType.police
          : withPolice && (i == 10 || i == 30)
          ? TileType.jail
          : TileType.normal,
    ),
]);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late BoardDefinition board;
  late GameController game;
  setUp(() async {
    board = await const BoardRepository().loadReferenceBoard();
    game = GameController.newGame(
      names: ['One', 'Two', 'Three', 'Four', 'Five'],
      colors: AppTheme.playerColors.map((c) => c.toARGB32()).toList(),
      board: board,
    );
  });
  tearDown(() => game.dispose());

  test('Players can change only their own icon outside their turn', () {
    final before = game.session.toJson();
    final result = executeRoomCommand(
      room: roomFor(game.session),
      senderId: 'u1',
      expectedRevision: 1,
      action: 'playerIcon',
      args: {'icon': 'rocket'},
      board: board,
    );
    final state = GameSession.fromJson(jsonDecode(result.state));
    expect(state.players[1].icon, PlayerIcon.rocket);
    expect(state.players.first.icon, PlayerIcon.number);
    final expected = jsonDecode(jsonEncode(before)) as Map<String, dynamic>;
    expected['players'][1]['icon'] = 'rocket';
    expect(state.toJson(), expected);
    expect(result.outcome, isEmpty);
    for (final args in [
      {'icon': 'unknown'},
      {'icon': 'star', 'player': 'p1'},
    ]) {
      expect(
        () => executeRoomCommand(
          room: roomFor(game.session),
          senderId: 'u1',
          expectedRevision: 1,
          action: 'playerIcon',
          args: args,
          board: board,
        ),
        throwsStateError,
      );
    }
    expect(
      () => executeRoomCommand(
        room: roomFor(game.session),
        senderId: 'outsider',
        expectedRevision: 1,
        action: 'playerIcon',
        args: {'icon': 'star'},
        board: board,
      ),
      throwsStateError,
    );
  });
  test('Five-player room maps the current Firebase UID to its seat', () {
    final room = roomFor(game.session);
    expect(room.full, isTrue);
    expect(room.activeUid, 'u0');
    expect(room.playerOrder.length, maxRoomPlayers);
  });
  test(
    'Host rolls, resolves movement and advances without pass-device screens',
    () {
      final result = executeRoomCommand(
        room: roomFor(game.session),
        senderId: 'u0',
        expectedRevision: 1,
        action: 'roll',
        args: {},
        board: board,
        diceRoller: () => 1,
      );
      final state = GameSession.fromJson(jsonDecode(result.state));
      expect(state.players.first.position, 1);
      expect(state.currentPlayerIndex, 1);
      expect(state.phase, TurnPhase.ready);
      expect(jsonDecode(result.outcome)['path'], [1]);
    },
  );
  test('Guests cannot act for another seat or replay a stale command', () {
    for (final (sender, revision) in [('u1', 1), ('outsider', 1), ('u0', 0)]) {
      expect(
        () => executeRoomCommand(
          room: roomFor(game.session),
          senderId: sender,
          expectedRevision: revision,
          action: 'roll',
          args: {},
          board: board,
        ),
        throwsStateError,
      );
    }
    expect(game.session.players.first.position, 0);
  });
  test('A pickup advances the turn and carries a separate result snapshot', () {
    game.session.currentPlayer.position = 1;
    final result = executeRoomCommand(
      room: roomFor(game.session),
      senderId: 'u0',
      expectedRevision: 1,
      action: 'roll',
      args: {},
      board: board,
      diceRoller: () => 1,
    );
    final state = GameSession.fromJson(jsonDecode(result.state));
    expect(state.phase, TurnPhase.ready);
    expect(state.currentPlayerIndex, 1);
    expect(state.players.first.inventory.boats, 1);
    final shown = _results(result).single;
    expect(shown.phase, TurnPhase.specialReview);
    expect(shown.currentPlayer.id, 'p1');
    expect(shown.tileSummary!.landedIndex, 2);
    final next = executeRoomCommand(
      room: roomFor(state, revision: 2),
      senderId: 'u1',
      expectedRevision: 2,
      action: 'roll',
      args: {},
      board: board,
      diceRoller: () => 1,
    );
    expect(GameSession.fromJson(jsonDecode(next.state)).players[1].position, 1);
  });
  for (final pay in [true, false]) {
    test(
      'Hospital ${pay ? 'payment' : 'restart'} works as an online action exactly once',
      () {
        game.session.currentPlayer.position = 75;
        final roll = executeRoomCommand(
          room: roomFor(game.session),
          senderId: 'u0',
          expectedRevision: 1,
          action: 'roll',
          args: {},
          board: board,
          diceRoller: () => 1,
        );
        final arrival = GameSession.fromJson(jsonDecode(roll.state));
        expect(arrival.phase, TurnPhase.hospitalChoice);
        expect(arrival.currentPlayer.isInjured, isTrue);
        final chosen = executeRoomCommand(
          room: roomFor(arrival, revision: 2),
          senderId: 'u0',
          expectedRevision: 2,
          action: 'hospital',
          args: {'pay': pay},
          board: board,
        );
        final state = GameSession.fromJson(jsonDecode(chosen.state));
        expect(state.players.first.cash, pay ? 0 : 10);
        expect(state.players.first.position, pay ? 62 : 0);
        expect(state.players.first.isInjured, isFalse);
        expect(state.phase, pay ? TurnPhase.shopping : TurnPhase.ready);
        expect(state.currentPlayerIndex, pay ? 0 : 1);
        if (!pay) expect(_results(chosen).single.currentPlayer.id, 'p1');
        expect(
          () => executeRoomCommand(
            room: roomFor(state, revision: 3),
            senderId: 'u0',
            expectedRevision: 3,
            action: 'hospital',
            args: {'pay': pay},
            board: board,
          ),
          throwsStateError,
        );
      },
    );
  }
  test(
    'Green mine leads to treatment and working hospital purchases online',
    () {
      game.session.currentPlayer
        ..position = 84
        ..cash = 40;
      var state = game.session;
      var revision = 1;
      void command(String action, Map<String, dynamic> args) {
        final result = executeRoomCommand(
          room: roomFor(state, revision: revision),
          senderId: 'u0',
          expectedRevision: revision,
          action: action,
          args: args,
          board: board,
          diceRoller: () => 1,
        );
        state = GameSession.fromJson(jsonDecode(result.state));
        revision++;
      }

      command('roll', {});
      expect(state.phase, TurnPhase.hospitalChoice);
      expect(state.currentPlayer.position, 62);
      command('hospital', {'pay': true});
      expect(state.phase, TurnPhase.shopping);
      command('medicalBuy', {'item': 'healthPack'});
      expect(state.currentPlayer.inventory.healthPacks, 1);
      expect(state.currentPlayer.cash, 20);
      expect(state.phase, TurnPhase.shopping);
      command('shopDone', {});
      expect(state.players.first.inventory.healthPacks, 1);
      expect(state.currentPlayerIndex, 1);
    },
  );
  test('Healthy hospital shopping purchases are committed by the host', () {
    game.session.currentPlayer
      ..position = 61
      ..cash = 30;
    final arrivalResult = executeRoomCommand(
      room: roomFor(game.session),
      senderId: 'u0',
      expectedRevision: 1,
      action: 'roll',
      args: {},
      board: board,
      diceRoller: () => 1,
    );
    final arrival = GameSession.fromJson(jsonDecode(arrivalResult.state));
    expect(arrival.phase, TurnPhase.shopping);
    expect(arrival.currentPlayer.cash, 30);
    final boughtPack = executeRoomCommand(
      room: roomFor(arrival, revision: 2),
      senderId: 'u0',
      expectedRevision: 2,
      action: 'medicalBuy',
      args: {'item': 'healthPack'},
      board: board,
    );
    final withPack = GameSession.fromJson(jsonDecode(boughtPack.state));
    expect(withPack.currentPlayer.inventory.healthPacks, 1);
    expect(withPack.currentPlayer.cash, 20);
    final boughtAntidote = executeRoomCommand(
      room: roomFor(withPack, revision: 3),
      senderId: 'u0',
      expectedRevision: 3,
      action: 'medicalBuy',
      args: {'item': 'antidote'},
      board: board,
    );
    final withBoth = GameSession.fromJson(jsonDecode(boughtAntidote.state));
    expect(withBoth.currentPlayer.inventory.antidotes, 1);
    expect(withBoth.currentPlayer.inventory.healthPacks, 1);
    expect(withBoth.currentPlayer.cash, 15);
    expect(withBoth.phase, TurnPhase.shopping);
    expect(game.session.currentPlayer.cash, 30);
    expect(game.session.currentPlayer.inventory.healthPacks, 0);
    expect(
      () => executeRoomCommand(
        room: roomFor(withBoth, revision: 4),
        senderId: 'u0',
        expectedRevision: 3,
        action: 'medicalBuy',
        args: {'item': 'antidote'},
        board: board,
      ),
      throwsStateError,
    );
  });
  test('An online health pack treats one injury and cannot be reused', () {
    game.session.currentPlayer
      ..position = 61
      ..isInjured = true
      ..cash = 0;
    game.session.currentPlayer.inventory.healthPacks = 1;
    final roll = executeRoomCommand(
      room: roomFor(game.session),
      senderId: 'u0',
      expectedRevision: 1,
      action: 'roll',
      args: {},
      board: board,
      diceRoller: () => 1,
    );
    final injured = GameSession.fromJson(jsonDecode(roll.state));
    expect(injured.phase, TurnPhase.hospitalChoice);
    expect(injured.currentPlayer.isInjured, isTrue);
    final healed = executeRoomCommand(
      room: roomFor(injured, revision: 2),
      senderId: 'u0',
      expectedRevision: 2,
      action: 'healthPack',
      args: {},
      board: board,
    );
    final state = GameSession.fromJson(jsonDecode(healed.state));
    expect(state.currentPlayer.inventory.healthPacks, 0);
    expect(state.currentPlayer.isInjured, isFalse);
    expect(state.currentPlayer.position, 62);
    expect(state.currentPlayer.cash, 0);
    expect(state.phase, TurnPhase.shopping);
    expect(
      () => executeRoomCommand(
        room: roomFor(state, revision: 3),
        senderId: 'u0',
        expectedRevision: 3,
        action: 'healthPack',
        args: {},
        board: board,
      ),
      throwsStateError,
    );
  });
  for (final hazard in [65, 76, 103]) {
    test(
      'Online hazard $hazard consumes a pack and keeps the player there',
      () {
        game.session.currentPlayer
          ..position = hazard - 1
          ..cash = 0;
        game.session.currentPlayer.inventory.healthPacks = 2;
        final roll = executeRoomCommand(
          room: roomFor(game.session),
          senderId: 'u0',
          expectedRevision: 1,
          action: 'roll',
          args: {},
          board: board,
          diceRoller: () => 1,
        );
        final state = GameSession.fromJson(jsonDecode(roll.state));
        expect(state.players.first.position, hazard);
        expect(state.players.first.inventory.healthPacks, 1);
        expect(state.players.first.isInjured, isFalse);
        expect(state.players.first.cash, 0);
        expect(state.players.first.skipTurns, hazard == 65 ? 1 : 0);
        expect(state.pendingHospital, isFalse);
        expect(state.phase, TurnPhase.ready);
        expect(_results(roll).single.currentPlayer.position, hazard);
        expect(jsonDecode(roll.outcome)['path'], [hazard]);
        expect(
          () => executeRoomCommand(
            room: roomFor(state, revision: 2),
            senderId: 'u0',
            expectedRevision: 1,
            action: 'roll',
            args: {},
            board: board,
          ),
          throwsStateError,
        );
      },
    );
  }
  for (final weapon in WeaponType.values) {
    for (final sameTile in [true, false]) {
      test(
        'Online ${weapon.label} ${sameTile ? 'same-tile' : 'ranged'} kill awards three stars without cash',
        () {
          final combatBoard = _combatBoard();
          final combat = GameController.newGame(
            names: ['One', 'Two'],
            colors: [1, 2],
            board: combatBoard,
            diceRoller: () => sameTile ? 4 : 6,
          );
          addTearDown(combat.dispose);
          final attacker = combat.session.currentPlayer;
          attacker
            ..position = 10
            ..cash = 70;
          attacker.inventory
            ..stars = 2
            ..stabbers = weapon == WeaponType.stabber ? 1 : 0
            ..pewPews = weapon == WeaponType.pewPew ? 1 : 0;
          combat.session.players[1]
            ..position = sameTile ? 10 : 17
            ..cash = 25;
          combat.roll();
          combat.finishAnimation();
          final attacked = executeRoomCommand(
            room: roomFor(combat.session),
            senderId: 'u0',
            expectedRevision: 1,
            action: 'attack',
            args: {'weapon': weapon.name, 'target': 1},
            board: combatBoard,
          );
          final state = GameSession.fromJson(jsonDecode(attacked.state));
          expect(state.players.first.inventory.stars, 5);
          expect(state.players.first.cash, 70);
          expect(state.players[1].cash, 25);
          expect(state.players[1].position, 0);
          expect(state.phase, TurnPhase.ready);
          expect(
            _results(attacked).single.tileSummary!.changes,
            contains('Stars: +3 (2 → 5)'),
          );
          expect(attacker.inventory.stars, 2);
          expect(combat.session.players[1].position, sameTile ? 10 : 17);
          for (final revision in [1, 2]) {
            expect(
              () => executeRoomCommand(
                room: roomFor(state, revision: 2),
                senderId: 'u0',
                expectedRevision: revision,
                action: 'attack',
                args: {'weapon': weapon.name, 'target': 1},
                board: combatBoard,
              ),
              throwsStateError,
            );
          }
          expect(state.players.first.inventory.stars, 5);
        },
      );
    }
  }
  test(
    'Online kill stars cause jail on the next movement into police range',
    () {
      final combatBoard = _combatBoard(withPolice: true);
      final combat = GameController.newGame(
        names: ['One', 'Two'],
        colors: [1, 2],
        board: combatBoard,
        diceRoller: () => 4,
      );
      addTearDown(combat.dispose);
      combat.session.currentPlayer
        ..position = 16
        ..cash = 70;
      combat.session.currentPlayer.inventory.stabbers = 1;
      combat.session.players[1].position = 16;
      combat.roll();
      var state = combat.session;
      var revision = 1;
      RoomCommandResult action(
        String uid,
        String name, {
        Map<String, dynamic> args = const {},
        int dice = 1,
      }) {
        final result = executeRoomCommand(
          room: roomFor(state, revision: revision),
          senderId: uid,
          expectedRevision: revision,
          action: name,
          args: args,
          board: combatBoard,
          diceRoller: () => dice,
        );
        state = GameSession.fromJson(jsonDecode(result.state));
        revision++;
        return result;
      }

      action('u0', 'attack', args: {'weapon': 'stabber', 'target': 1});
      expect(state.players.first.inventory.stars, 3);
      expect(state.players.first.inventory.hasWeapons, isFalse);
      expect(state.currentPlayerIndex, 1);
      action('u1', 'roll');
      expect(state.currentPlayerIndex, 0);
      final arrest = action('u0', 'roll');
      expect(jsonDecode(arrest.outcome)['path'], [17, 10]);
      expect(state.players.first.position, 10);
      expect(state.players.first.inventory.stars, 0);
      expect(state.players.first.skipTurns, 3);
      expect(state.players.first.cash, 70);
      expect(state.pendingPoliceFine, isNull);
      expect(state.phase, TurnPhase.ready);
    },
  );
  test('Medical purchases reject malformed and unaffordable requests', () {
    game.session.currentPlayer
      ..position = 62
      ..cash = 4;
    game.session
      ..phase = TurnPhase.shopping
      ..pendingShopTile = 62;
    for (final args in <Map<String, dynamic>>[
      {},
      {'item': 'unknown'},
      {'item': 1},
      {'item': 'healthPack', 'price': 0},
      {'item': 'healthPack'},
      {'item': 'antidote'},
    ]) {
      expect(
        () => executeRoomCommand(
          room: roomFor(game.session),
          senderId: 'u0',
          expectedRevision: 1,
          action: 'medicalBuy',
          args: args,
          board: board,
        ),
        throwsStateError,
      );
    }
    expect(game.session.currentPlayer.cash, 4);
    expect(game.session.currentPlayer.inventory.healthPacks, 0);
    expect(game.session.currentPlayer.inventory.antidotes, 0);
  });
  test('Hospital cannot consume a pack a player does not own', () {
    game.session.currentPlayer
      ..position = 75
      ..cash = 10;
    final roll = executeRoomCommand(
      room: roomFor(game.session),
      senderId: 'u0',
      expectedRevision: 1,
      action: 'roll',
      args: {},
      board: board,
      diceRoller: () => 1,
    );
    final injured = GameSession.fromJson(jsonDecode(roll.state));
    expect(injured.phase, TurnPhase.hospitalChoice);
    expect(
      () => executeRoomCommand(
        room: roomFor(injured, revision: 2),
        senderId: 'u0',
        expectedRevision: 2,
        action: 'healthPack',
        args: {},
        board: board,
      ),
      throwsStateError,
    );
    for (final args in <Map<String, dynamic>>[
      {},
      {'pay': 'true'},
      {'pay': true, 'item': 'healthPack'},
    ]) {
      expect(
        () => executeRoomCommand(
          room: roomFor(injured, revision: 2),
          senderId: 'u0',
          expectedRevision: 2,
          action: 'hospital',
          args: args,
          board: board,
        ),
        throwsStateError,
      );
    }
  });
  test('Unknown and unavailable actions cannot mutate a match', () {
    final room = roomFor(game.session);
    for (final action in [
      'win',
      'review',
      'event',
      'move',
      'shopDone',
      'endTurn',
      'healthPack',
    ]) {
      expect(
        () => executeRoomCommand(
          room: room,
          senderId: 'u0',
          expectedRevision: 1,
          action: action,
          args: {},
          board: board,
        ),
        throwsStateError,
      );
    }
  });
  test('Medical purchases outside hospital shopping cannot mutate a match', () {
    expect(
      () => executeRoomCommand(
        room: roomFor(game.session),
        senderId: 'u0',
        expectedRevision: 1,
        action: 'medicalBuy',
        args: {'item': 'antidote'},
        board: board,
      ),
      throwsStateError,
    );
  });
  test('Ended rooms reject actions', () {
    expect(
      () => executeRoomCommand(
        room: roomFor(game.session, status: 'closed'),
        senderId: 'u0',
        expectedRevision: 1,
        action: 'roll',
        args: {},
        board: board,
      ),
      throwsStateError,
    );
  });

  test('An event result advances to its hospital decision without waiting', () {
    final tiles = board.tiles.toList();
    tiles[59] = tiles[59].withChanges({'type': 'event'});
    final eventBoard = BoardDefinition(tiles, id: board.id);
    final eventGame = GameController.newGame(
      names: ['One', 'Two'],
      colors: [1, 2],
      board: eventBoard,
      eventCardOrder: ['forward_3'],
    );
    addTearDown(eventGame.dispose);
    eventGame.session.currentPlayer
      ..position = 58
      ..isInjured = true;
    final result = executeRoomCommand(
      room: roomFor(eventGame.session),
      senderId: 'u0',
      expectedRevision: 1,
      action: 'roll',
      args: {},
      board: eventBoard,
      diceRoller: () => 1,
    );
    final state = GameSession.fromJson(jsonDecode(result.state));
    expect(state.phase, TurnPhase.hospitalChoice);
    expect(state.currentPlayerIndex, 0);
    expect(state.pendingHospital, isTrue);
    expect(state.pendingCardId, isNull);
    final event = _results(result).single;
    expect(event.phase, TurnPhase.eventReveal);
    expect(event.pendingCardId, 'forward_3');
    expect(event.currentPlayer.id, 'p1');
    expect(event.currentPlayer.position, 62);
  });

  test(
    'Finishing hospital shopping captures purchases and advances the turn',
    () {
      game.session.currentPlayer
        ..position = 62
        ..cash = 30;
      game.session
        ..phase = TurnPhase.shopping
        ..pendingShopTile = 62;
      final bought = executeRoomCommand(
        room: roomFor(game.session),
        senderId: 'u0',
        expectedRevision: 1,
        action: 'medicalBuy',
        args: {'item': 'antidote'},
        board: board,
      );
      final done = executeRoomCommand(
        room: roomFor(
          GameSession.fromJson(jsonDecode(bought.state)),
          revision: 2,
        ),
        senderId: 'u0',
        expectedRevision: 2,
        action: 'shopDone',
        args: {},
        board: board,
      );
      final state = GameSession.fromJson(jsonDecode(done.state));
      expect(state.phase, TurnPhase.ready);
      expect(state.currentPlayerIndex, 1);
      expect(state.pendingShopTile, isNull);
      final result = _results(done).single;
      expect(result.currentPlayer.id, 'p1');
      expect(result.currentPlayer.inventory.antidotes, 1);
      expect(result.currentPlayer.cash, 25);
      expect(utf8.encode(done.outcome).length, lessThanOrEqualTo(8192));
    },
  );

  test('The exact finish commits a winner without a shared result barrier', () {
    game.session.currentPlayer.position = board.lastIndex - 1;
    final result = executeRoomCommand(
      room: roomFor(game.session),
      senderId: 'u0',
      expectedRevision: 1,
      action: 'roll',
      args: {},
      board: board,
      diceRoller: () => 1,
    );
    final state = GameSession.fromJson(jsonDecode(result.state));
    expect(state.phase, TurnPhase.completed);
    expect(state.winnerId, 'p1');
    expect(state.players.first.position, board.lastIndex);
  });

  test('Portal cards remain a decision and their result advances the turn', () {
    game.session.currentPlayer.position = 24;
    final roll = executeRoomCommand(
      room: roomFor(game.session),
      senderId: 'u0',
      expectedRevision: 1,
      action: 'roll',
      args: {},
      board: board,
      diceRoller: () => 1,
    );
    final choice = GameSession.fromJson(jsonDecode(roll.state));
    expect(choice.phase, TurnPhase.portalChoice);
    expect(choice.currentPlayerIndex, 0);
    final chosen = executeRoomCommand(
      room: roomFor(choice, revision: 2),
      senderId: 'u0',
      expectedRevision: 2,
      action: 'portal',
      args: {'card': choice.portalCardDirections.indexOf(1)},
      board: board,
    );
    final state = GameSession.fromJson(jsonDecode(chosen.state));
    expect(state.phase, TurnPhase.ready);
    expect(state.currentPlayerIndex, 1);
    expect(state.players.first.position, 55);
    final shown = _results(chosen).single;
    expect(shown.currentPlayer.id, 'p1');
    expect(shown.currentPlayer.position, 55);
    expect(shown.tileSummary!.title, 'MYSTERY PORTAL · FORWARDS');
  });

  for (final pay in [true, false]) {
    test(
      'Online police ${pay ? 'bribe stays on the encounter tile' : 'refusal animates to jail'} exactly once',
      () {
        final policeBoard = _combatBoard(withPolice: true);
        final arrested = GameController.newGame(
          names: ['One', 'Two'],
          colors: [1, 2],
          board: policeBoard,
        );
        addTearDown(arrested.dispose);
        arrested.session.currentPlayer
          ..position = 16
          ..cash = 100;
        arrested.session.currentPlayer.inventory.stabbers = 1;
        final roll = executeRoomCommand(
          room: roomFor(arrested.session),
          senderId: 'u0',
          expectedRevision: 1,
          action: 'roll',
          args: {},
          board: policeBoard,
          diceRoller: () => 1,
        );
        final choice = GameSession.fromJson(jsonDecode(roll.state));
        expect(choice.phase, TurnPhase.jailChoice);
        expect(choice.currentPlayerIndex, 0);
        expect(choice.players.first.position, 17);
        expect(choice.pendingPoliceJail, 10);
        expect(jsonDecode(roll.outcome)['path'], [17]);
        final chosen = executeRoomCommand(
          room: roomFor(choice, revision: 2),
          senderId: 'u0',
          expectedRevision: 2,
          action: 'police',
          args: {'pay': pay},
          board: policeBoard,
        );
        final state = GameSession.fromJson(jsonDecode(chosen.state));
        expect(state.phase, TurnPhase.ready);
        expect(state.currentPlayerIndex, 1);
        expect(state.pendingPoliceFine, isNull);
        expect(state.pendingPoliceJail, isNull);
        expect(state.players.first.position, pay ? 17 : 10);
        expect(state.players.first.cash, pay ? 80 : 100);
        expect(state.players.first.skipTurns, pay ? 0 : 1);
        final shown = _results(chosen).single;
        expect(shown.currentPlayer.id, 'p1');
        expect(shown.currentPlayer.position, pay ? 17 : 10);
        if (pay) {
          expect(
            (jsonDecode(chosen.outcome) as Map).containsKey('path'),
            isFalse,
          );
        } else {
          expect(jsonDecode(chosen.outcome)['path'], [10]);
          expect(jsonDecode(chosen.outcome)['playerIndex'], 0);
        }
        for (final expectedRevision in [2, 3]) {
          expect(
            () => executeRoomCommand(
              room: roomFor(state, revision: 3),
              senderId: 'u0',
              expectedRevision: expectedRevision,
              action: 'police',
              args: {'pay': pay},
              board: policeBoard,
            ),
            throwsStateError,
          );
        }
        expect(state.players.first.cash, pay ? 80 : 100);
      },
    );
  }
  for (final scenario in ['event', 'hazard', 'attack']) {
    test(
      'Five-player $scenario presentation fits Firestore outcome limits',
      () {
        final tiles = _combatBoard().tiles.toList();
        tiles[10] = tiles[10].withChanges({'type': 'event'});
        tiles[20] = tiles[20].withChanges({'type': 'fire', 'destination': 25});
        tiles[25] = tiles[25].withChanges({'type': 'hospital'});
        final largeBoard = BoardDefinition(tiles);
        final large = GameController.newGame(
          names: [for (var i = 0; i < 5; i++) 'Player ${'$i'.padLeft(9, '0')}'],
          colors: [1, 2, 3, 4, 5],
          board: largeBoard,
          eventCardOrder: ['cash_50'],
          diceRoller: () => 4,
        );
        addTearDown(large.dispose);
        for (final player in large.session.players) {
          expect(player.name.length, 16);
          player
            ..position = 5
            ..cash = 1000000
            ..debt = 1000000;
          player.inventory
            ..healthPacks = 9999
            ..antidotes = 9999
            ..boats = 9999
            ..rawMeat = 9999
            ..stabbers = 9999
            ..pewPews = 9999
            ..stars = 9999;
        }
        if (scenario == 'attack') {
          large.session.currentPlayer.position = 11;
          large.session.players[1].position = 11;
          large.roll();
        } else {
          large.session.currentPlayer.position = scenario == 'event' ? 9 : 19;
        }
        final result = executeRoomCommand(
          room: roomFor(large.session),
          senderId: 'u0',
          expectedRevision: 1,
          action: scenario == 'attack' ? 'attack' : 'roll',
          args: scenario == 'attack' ? {'weapon': 'stabber', 'target': 1} : {},
          board: largeBoard,
          diceRoller: () => 1,
        );
        expect(_results(result), hasLength(1));
        expect(utf8.encode(result.outcome).length, lessThanOrEqualTo(8192));
      },
    );
  }
}
