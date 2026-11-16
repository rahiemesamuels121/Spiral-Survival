import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';
import 'package:spiral_pass_play/features/game/application/game_controller.dart';
import 'package:spiral_pass_play/features/game/domain/board_definition.dart';
import 'package:spiral_pass_play/features/game/domain/game_session.dart';
import 'package:spiral_pass_play/features/game/presentation/game_screen.dart';
import 'package:spiral_pass_play/features/multiplayer/application/online_game_controller.dart';
import 'package:spiral_pass_play/features/multiplayer/data/room_service.dart';
import 'package:spiral_pass_play/features/multiplayer/domain/room_protocol.dart';

class _Connection extends RoomService {
  _Connection(super.board);
  final actions = <String>[];

  @override
  Future<void> send(String action, Map<String, dynamic> args) async {
    actions.add(action);
  }

  void publish(OnlineRoom next) {
    room = next;
    notifyListeners();
  }
}

BoardDefinition _board() => BoardDefinition([
  for (var i = 0; i < 50; i++)
    BoardTile(
      index: i,
      x: (i % 10 + .5) / 10,
      y: (i ~/ 10 + .5) / 5,
      type: switch (i) {
        0 => TileType.start,
        2 => TileType.boat,
        3 => TileType.cash,
        10 => TileType.shop,
        20 => TileType.hospital,
        25 => TileType.jail,
        30 || 38 => TileType.portal,
        49 => TileType.finish,
        _ => TileType.normal,
      },
      amount: i == 3 ? 777 : 0,
    ),
]);

OnlineRoom _snapshot(
  GameSession session, {
  int revision = 1,
  String outcome = '',
}) => OnlineRoom(
  code: 'ABCDEFGH',
  hostId: 'u0',
  members: const {'u0': 'Owner', 'u1': 'Opponent'},
  playerOrder: const ['u0', 'u1'],
  status: 'playing',
  revision: revision,
  state: jsonEncode(session.toJson()),
  outcome: outcome,
  lastRequestId: '',
  lastError: '',
  hostSeen: DateTime.now(),
  expiresAt: DateTime.now().add(const Duration(hours: 24)),
);

GameController _game() {
  final game = GameController.newGame(
    names: ['Owner', 'Opponent'],
    colors: [0xFFCC3333, 0xFF33CC33],
    board: _board(),
    diceRoller: () => 1,
  );
  final own = game.session.players.first;
  own.cash = 123;
  own.debt = 13;
  own.inventory
    ..boats = 2
    ..antidotes = 3
    ..rawMeat = 4
    ..healthPacks = 5
    ..stabbers = 6
    ..pewPews = 7
    ..stars = 8;
  final other = game.session.players[1];
  other.cash = 987;
  other.debt = 99;
  other.inventory
    ..boats = 22
    ..antidotes = 33
    ..rawMeat = 44
    ..healthPacks = 55
    ..stabbers = 66
    ..pewPews = 77
    ..stars = 88;
  return game;
}

OnlineGameController _client(GameController game, {String uid = 'u0'}) {
  final connection = _Connection(game.board)
    ..uid = uid
    ..connected = true
    ..room = _snapshot(game.session);
  final client = OnlineGameController(connection: connection);
  addTearDown(client.dispose);
  addTearDown(connection.dispose);
  return client;
}

Future<void> _show(WidgetTester tester, Widget child) async {
  tester.view.physicalSize = const Size(1200, 900);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  SharedPreferencesAsyncPlatform.instance =
      InMemorySharedPreferencesAsync.empty();
  await tester.runAsync(() async {
    await tester.pumpWidget(MaterialApp(home: child));
    await Future<void>.delayed(const Duration(milliseconds: 100));
  });
  await tester.pump();
}

Widget _screen(OnlineGameController client, {Key? key}) => GameScreen(
  key: key,
  controller: client,
  online: true,
  canInteract: () => client.canAct,
  onlineStatus: () => client.status,
);

void _expectOwnerInventory() {
  expect(find.text(r'$123'), findsOneWidget);
  expect(find.text('Boats 2 · Antidotes 3 · Raw meat 4'), findsOneWidget);
  expect(find.text('Stabbers 6 · Pew pews 7'), findsOneWidget);
  expect(find.text('Stars 8'), findsOneWidget);
  expect(find.text('Debt \$13'), findsOneWidget);
}

void _expectOpponentInventoryHidden() {
  for (final secret in [
    r'$987',
    'Boats 22',
    'Antidotes 33',
    'Raw meat 44',
    'Health packs 55',
    'Stabbers 66',
    'Pew pews 77',
    'Stars 88',
    'Debt \$99',
  ]) {
    expect(find.textContaining(secret), findsNothing, reason: secret);
  }
}

void main() {
  testWidgets(
    'Online inventory shows the viewer own items while another seat plays',
    (tester) async {
      final game = _game();
      addTearDown(game.dispose);
      game.session.currentPlayerIndex = 1;
      game.session.currentPlayer.position = 3;
      final client = _client(game);
      await _show(tester, _screen(client));
      expect(client.canAct, isFalse);
      await tester.tap(find.byTooltip('Players and inventory'));
      await tester.pump(const Duration(milliseconds: 350));
      expect(find.text('Owner'), findsOneWidget);
      expect(find.text('Opponent'), findsOneWidget);
      _expectOwnerInventory();
      _expectOpponentInventoryHidden();
      expect(find.textContaining('777'), findsNothing);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  for (final phase in [
    TurnPhase.shopping,
    TurnPhase.hospitalChoice,
    TurnPhase.jailChoice,
    TurnPhase.portalChoice,
    TurnPhase.weaponAction,
    TurnPhase.preMoveWeaponChoice,
  ]) {
    testWidgets('Opponent $phase decision hides its controls and finances', (
      tester,
    ) async {
      final game = _game();
      addTearDown(game.dispose);
      game.session
        ..currentPlayerIndex = 1
        ..phase = phase
        ..lastDice = 6
        ..message = r'Opponent has $987, 55 health packs and 88 stars.';
      final player = game.session.currentPlayer;
      switch (phase) {
        case TurnPhase.shopping:
          player.position = 10;
          game.session.pendingShopTile = 10;
        case TurnPhase.hospitalChoice:
          player.position = 20;
          player.isInjured = true;
          game.session.pendingHospital = true;
        case TurnPhase.jailChoice:
          player.position = 25;
          game.session.pendingPoliceFine = 20;
        case TurnPhase.portalChoice:
          player.position = 30;
          game.session.pendingPortalTile = 30;
          game.session.portalCardDirections.addAll([-1, 1]);
        default:
          player.position = 15;
      }
      final client = _client(game);
      await _show(tester, _screen(client));
      expect(client.canAct, isFalse);
      for (final privateText in [
        'WEAPON SHOP',
        'HOSPITAL SHOP',
        'INJURY TREATMENT',
        'POLICE · CHOOSE YOUR PENALTY',
        'MYSTERY PORTAL',
        'CHOOSE A TARGET',
        'MOVE OR ATTACK',
        'DONE SHOPPING',
        'PAY 10 COINS',
        r'PAY $20',
        'USE HEALTH PACK',
      ]) {
        expect(find.text(privateText), findsNothing, reason: privateText);
      }
      expect(find.textContaining(r'$987'), findsNothing);
      expect(find.textContaining('55 health packs'), findsNothing);
      expect(find.textContaining('88 stars'), findsNothing);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }

  testWidgets('Own hospital shop stays available with own cash and catalog', (
    tester,
  ) async {
    final game = _game();
    addTearDown(game.dispose);
    game.session.currentPlayer.position = 20;
    game.session
      ..phase = TurnPhase.shopping
      ..pendingShopTile = 20;
    final client = _client(game);
    await _show(tester, _screen(client));
    expect(find.text('HOSPITAL SHOP'), findsOneWidget);
    expect(find.textContaining(r'Cash: $123'), findsOneWidget);
    expect(find.text(r'BUY HEALTH PACK · $10'), findsOneWidget);
    expect(find.text(r'BUY ANTIDOTE · $5'), findsOneWidget);
    _expectOpponentInventoryHidden();
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets(
    'Movement HUD redacts another player financial and item message',
    (tester) async {
      final game = _game();
      addTearDown(game.dispose);
      game.session.currentPlayerIndex = 1;
      final client = _client(game);
      await _show(tester, _screen(client));
      final next = GameSession.fromJson(game.session.toJson());
      next.currentPlayer.position = 1;
      next.message = r'Opponent collected $987 and has 55 health packs.';
      (client.connection as _Connection).publish(
        _snapshot(
          next,
          revision: 2,
          outcome: jsonEncode({
            'playerIndex': 1,
            'dice': 1,
            'path': [1],
            'description': next.message,
            'landedType': 'cash',
            'effectLabel': 'CASH',
            'eventCardId': null,
          }),
        ),
      );
      await tester.pump();
      expect(find.text('Opponent is moving.'), findsOneWidget);
      expect(find.textContaining(r'$987'), findsNothing);
      expect(find.textContaining('55 health packs'), findsNothing);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets(
    'Online move details are visible to both seats and dismiss independently',
    (tester) async {
      final game = _game();
      addTearDown(game.dispose);
      game.session.currentPlayer.position = 2;
      final first = _client(game);
      final second = _client(game, uid: 'u1');
      const firstKey = ValueKey('first-client');
      const secondKey = ValueKey('second-client');
      await _show(
        tester,
        Row(
          children: [
            Expanded(child: _screen(first, key: firstKey)),
            Expanded(child: _screen(second, key: secondKey)),
          ],
        ),
      );
      final committed = executeRoomCommand(
        room: first.connection.room!,
        senderId: 'u0',
        expectedRevision: 1,
        action: 'roll',
        args: {},
        board: game.board,
        diceRoller: () => 1,
      );
      final snapshot = _snapshot(
        GameSession.fromJson(jsonDecode(committed.state)),
        revision: 2,
        outcome: committed.outcome,
      );
      (first.connection as _Connection).publish(snapshot);
      (second.connection as _Connection).publish(snapshot);
      first.finishAnimation();
      second.finishAnimation();
      await tester.pump();
      Finder inside(Key key, Finder finder) =>
          find.descendant(of: find.byKey(key), matching: finder);
      expect(first.localResult, isNotNull);
      expect(second.localResult, isNotNull);
      expect(inside(firstKey, find.text('CONTINUE')), findsOneWidget);
      expect(inside(secondKey, find.text('CONTINUE')), findsOneWidget);
      expect(inside(firstKey, find.textContaining('777')), findsWidgets);
      expect(inside(secondKey, find.textContaining('777')), findsWidgets);
      expect(first.canAct, isFalse);
      expect(second.canAct, isFalse);
      final unchangedRevision = second.connection.room!.revision;
      await tester.tap(inside(secondKey, find.text('CONTINUE')));
      await tester.pump();
      expect(second.localResult, isNull);
      expect(second.canAct, isTrue);
      expect(first.localResult, isNotNull);
      expect((second.connection as _Connection).actions, isEmpty);
      expect(second.connection.room!.revision, unchangedRevision);
      final roll = inside(
        secondKey,
        find.widgetWithText(FilledButton, 'ROLL DICE'),
      );
      expect(tester.widget<FilledButton>(roll).onPressed, isNotNull);
      expect(inside(firstKey, find.text('CONTINUE')), findsOneWidget);
      await tester.tap(roll);
      await tester.pump();
      expect((second.connection as _Connection).actions, ['roll']);
      expect(first.localResult, isNotNull);
      final firstContinue = inside(firstKey, find.text('CONTINUE'));
      await tester.ensureVisible(firstContinue);
      await tester.tap(firstContinue);
      await tester.pump();
      expect(first.localResult, isNull);
      expect((first.connection as _Connection).actions, isEmpty);
      expect(first.connection.room!.revision, unchangedRevision);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets('Pass-and-play inventory shows only the current player totals', (
    tester,
  ) async {
    final game = _game();
    addTearDown(game.dispose);
    await _show(tester, GameScreen(controller: game));
    await tester.tap(find.byTooltip('Players and inventory'));
    await tester.pump(const Duration(milliseconds: 350));
    _expectOwnerInventory();
    _expectOpponentInventoryHidden();
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
