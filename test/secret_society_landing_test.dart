import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';
import 'package:spiral_pass_play/app/theme.dart';
import 'package:spiral_pass_play/features/game/application/computer_opponent.dart';
import 'package:spiral_pass_play/features/game/application/game_controller.dart';
import 'package:spiral_pass_play/features/game/data/board_repository.dart';
import 'package:spiral_pass_play/features/game/domain/game_session.dart';
import 'package:spiral_pass_play/features/game/domain/player_icon.dart';
import 'package:spiral_pass_play/features/game/presentation/game_screen.dart';
import 'package:spiral_pass_play/features/game/presentation/turn_result_visual.dart';
import 'package:spiral_pass_play/features/multiplayer/domain/room_protocol.dart';

OnlineRoom _room(GameSession session, {int revision = 1}) => OnlineRoom(
  code: 'ABCDEFGH',
  hostId: 'u1',
  members: const {'u1': 'One', 'u2': 'Two'},
  playerOrder: const ['u1', 'u2'],
  status: 'playing',
  revision: revision,
  state: jsonEncode(session.toJson()),
  outcome: '',
  lastRequestId: '',
  lastError: '',
  hostSeen: DateTime.now(),
  expiresAt: DateTime.now().add(const Duration(hours: 1)),
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() {
    rootBundle.evict(BoardRepository.assetPath);
    SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.empty();
  });

  for (final destination in [57, 63]) {
    test(
      'Landing on $destination offers optional access without ending the turn or showing a normal result',
      () async {
        final board = await const BoardRepository().loadReferenceBoard();
        final game = GameController.newGame(
          names: ['One', 'Two'],
          colors: [1, 2],
          board: board,
          icons: [PlayerIcon.secretAgent, PlayerIcon.paw],
          diceRoller: () => 1,
        );
        addTearDown(game.dispose);
        game.session.currentPlayer.position = destination - 1;
        game.session.currentPlayer.cash = 200;
        game.session.players[1].position = 70;
        game.roll();
        game.finishAnimation();
        expect(game.session.phase, TurnPhase.secretSocietyAccess);
        expect(game.session.currentPlayerIndex, 0);
        expect(game.session.currentPlayer.position, destination);
        expect(game.session.tileSummary, isNull);
        expect(game.beginDiceRoll(), isNull);
        expect(game.hireHitman(destination), isTrue);
        expect(game.session.currentPlayer.cash, 50);
        expect(game.useHitman(1), isFalse);
        final restored = GameController(
          session: GameSession.fromJson(game.session.toJson()),
          board: board,
        );
        addTearDown(restored.dispose);
        expect(restored.session.phase, TurnPhase.secretSocietyAccess);
        expect(restored.session.hitmanTile, destination);
        restored.finishShopping();
        expect(restored.session.phase, TurnPhase.handoff);
        expect(restored.session.currentPlayerIndex, 1);
      },
    );
  }

  for (final icon in [PlayerIcon.paw, PlayerIcon.swimmer]) {
    test('$icon does not receive nearby access after landing', () async {
      final board = await const BoardRepository().loadReferenceBoard();
      final game = GameController.newGame(
        names: ['One', 'Two'],
        colors: [1, 2],
        board: board,
        icons: [icon, PlayerIcon.paw],
        diceRoller: () => 1,
      );
      addTearDown(game.dispose);
      game.session.currentPlayer.position = 56;
      game.roll();
      game.finishAnimation();
      expect(game.session.phase, TurnPhase.handoff);
      expect(game.session.currentPlayerIndex, 1);
    });
  }

  for (final destination in [58, 59, 62]) {
    test(
      'Special tile $destination resolves before nearby access is offered',
      () async {
        final board = await const BoardRepository().loadReferenceBoard();
        final game = GameController.newGame(
          names: ['One', 'Two'],
          colors: [1, 2],
          board: board,
          icons: [PlayerIcon.secretAgent, PlayerIcon.paw],
          diceRoller: () => 1,
          eventCardOrder: ['cash_30'],
        );
        addTearDown(game.dispose);
        game.session.currentPlayer.position = destination - 1;
        game.roll();
        game.finishAnimation();
        if (game.session.phase == TurnPhase.eventReveal) {
          game.dismissEventCard();
        }
        if (game.session.phase == TurnPhase.shopping) game.finishShopping();
        if (game.session.phase == TurnPhase.specialReview) {
          game.dismissTileSummary();
        }
        expect(game.session.phase, TurnPhase.secretSocietyAccess);
        game.finishShopping();
        expect(game.session.currentPlayerIndex, 1);
      },
    );
  }

  test(
    'Online host keeps the landing player active for hiring and advances after End Turn',
    () async {
      final board = await const BoardRepository().loadOnlineBoard();
      final game = GameController.newGame(
        names: ['One', 'Two'],
        colors: [1, 2],
        board: board,
        icons: [PlayerIcon.secretAgent, PlayerIcon.paw],
      );
      addTearDown(game.dispose);
      game.session.currentPlayer.position = 56;
      game.session.currentPlayer.cash = 200;
      final roll = executeRoomCommand(
        room: _room(game.session),
        senderId: 'u1',
        expectedRevision: 1,
        action: 'roll',
        args: {},
        board: board,
        diceRoller: () => 1,
      );
      final landed = GameSession.fromJson(jsonDecode(roll.state));
      expect(landed.phase, TurnPhase.secretSocietyAccess);
      expect(landed.currentPlayerIndex, 0);
      expect((jsonDecode(roll.outcome) as Map)['results'], isNull);
      final hired = executeRoomCommand(
        room: _room(landed, revision: 2),
        senderId: 'u1',
        expectedRevision: 2,
        action: 'hitmanHire',
        args: {'tile': 70},
        board: board,
      );
      final placed = GameSession.fromJson(jsonDecode(hired.state));
      expect(placed.hitmanTile, 70);
      expect(placed.currentPlayer.cash, 50);
      expect(placed.phase, TurnPhase.secretSocietyAccess);
      final end = executeRoomCommand(
        room: _room(placed, revision: 3),
        senderId: 'u1',
        expectedRevision: 3,
        action: 'shopDone',
        args: {},
        board: board,
      );
      final next = GameSession.fromJson(jsonDecode(end.state));
      expect(next.phase, TurnPhase.ready);
      expect(next.currentPlayerIndex, 1);
    },
  );

  test(
    'Computer Secret Agent handles nearby access without rolling or getting stuck',
    () async {
      final board = await const BoardRepository().loadReferenceBoard();
      final game = GameController.newGame(
        names: ['Computer', 'You'],
        colors: [1, 2],
        board: board,
        icons: [PlayerIcon.secretAgent, PlayerIcon.paw],
        computerPlayerIds: {'p1'},
        diceRoller: () => 1,
      );
      addTearDown(game.dispose);
      game.session.currentPlayer.position = 56;
      game.session.currentPlayer.cash = 200;
      game.session.players[1].position = 70;
      game.roll();
      game.finishAnimation();
      ComputerStrategy().takeAction(game);
      expect(game.session.currentPlayerIndex, 1);
      expect(game.session.phase, TurnPhase.ready);
      expect(game.session.hitmanOwnerId, 'p1');
      expect(game.session.hitmanTile, 70);
      expect(game.session.players.first.cash, 50);
      expect(
        game.session.players[1].position,
        70,
      ); // Hiring after movement cannot kill.
    },
  );

  for (final size in [const Size(390, 844), const Size(800, 360)]) {
    testWidgets('Landing access has a visible labeled control at $size', (
      tester,
    ) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      tester.platformDispatcher.textScaleFactorTestValue = 1.25;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      final board = (await tester.runAsync(
        () => const BoardRepository().loadReferenceBoard(),
      ))!;
      final game = GameController.newGame(
        names: ['One', 'Two'],
        colors: [1, 2],
        board: board,
        icons: [PlayerIcon.secretAgent, PlayerIcon.paw],
        diceRoller: () => 1,
      );
      game.session.currentPlayer.position = 56;
      game.session.currentPlayer.cash = 200;
      game.session.players[1].position = 70;
      await tester.runAsync(() async {
        await tester.pumpWidget(
          MaterialApp(
            theme: AppTheme.dark,
            home: GameScreen(controller: game),
          ),
        );
        await Future<void>.delayed(const Duration(milliseconds: 150));
      });
      await tester.pump();
      game.roll();
      for (var i = 0; i < 40; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      expect(game.session.phase, TurnPhase.secretSocietyAccess);
      expect(find.byType(TurnResultVisual), findsNothing);
      expect(find.text(r'SECRET SOCIETY · $150').hitTestable(), findsOneWidget);
      expect(find.text('END TURN').hitTestable(), findsOneWidget);
      await tester.tap(find.text(r'SECRET SOCIETY · $150'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      final hire = find.text(r'HIRE HITMAN · $150');
      await tester.ensureVisible(hire);
      await tester.tap(hire);
      await tester.pump();
      expect(game.session.currentPlayer.cash, 50);
      expect(game.session.hitmanTile, 57);
      expect(game.hitmanTargets, isEmpty);
      await tester.tap(find.text('CLOSE'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      await tester.tap(find.text('END TURN'));
      await tester.pump();
      expect(game.session.currentPlayerIndex, 1);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      game.dispose();
    });
  }
}
