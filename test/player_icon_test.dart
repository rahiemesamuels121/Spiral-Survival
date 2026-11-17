import 'package:flame/components.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';
import 'package:spiral_pass_play/features/game/application/game_controller.dart';
import 'package:spiral_pass_play/features/game/data/board_repository.dart';
import 'package:spiral_pass_play/features/game/data/session_store.dart';
import 'package:spiral_pass_play/features/game/domain/player_icon.dart';
import 'package:spiral_pass_play/features/game/domain/player_state.dart';
import 'package:spiral_pass_play/features/game/flame/spiral_board_game.dart';
import 'package:spiral_pass_play/features/game/presentation/game_screen.dart';
import 'package:spiral_pass_play/features/game/presentation/player_avatar.dart';
import 'package:spiral_pass_play/features/setup/setup_screen.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() {
    SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.empty();
  });

  test('Player icons persist and older saves keep numbered tokens', () {
    final player = PlayerState(id: 'p1', name: 'One', colorValue: 1);
    final old = player.toJson()..remove('icon');
    expect(PlayerState.fromJson(old).icon, PlayerIcon.number);
    for (final icon in PlayerIcon.values) {
      player.icon = icon;
      expect(PlayerState.fromJson(player.toJson()).icon, icon);
    }
  });

  testWidgets('Local setup lets each player choose a different icon', (
    tester,
  ) async {
    await tester.runAsync(() async {
      await tester.pumpWidget(const MaterialApp(home: GameSetupScreen()));
      await Future<void>.delayed(const Duration(milliseconds: 100));
    });
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byTooltip('Change Player 1 icon'));
    await tester.tap(find.byTooltip('Change Player 1 icon'));
    await tester.pumpAndSettle();
    expect(
      find.descendant(
        of: find.byType(AlertDialog),
        matching: find.byType(OutlinedButton),
      ),
      findsNWidgets(3),
    );
    expect(find.text('Rocket'), findsNothing);
    await tester.ensureVisible(find.text('Secret Agent'));
    await tester.tap(find.text('Secret Agent'));
    await tester.pumpAndSettle();
    final avatars = tester
        .widgetList<PlayerAvatar>(find.byType(PlayerAvatar))
        .toList();
    expect(avatars.first.icon, PlayerIcon.secretAgent);
    expect(avatars[1].icon, PlayerIcon.paw);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'Character is locked during the match and its abilities are readable',
    (tester) async {
      tester.view.physicalSize = const Size(900, 600);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final board = (await tester.runAsync(
        () => const BoardRepository().loadReferenceBoard(),
      ))!;
      final game = GameController.newGame(
        names: ['One', 'Two'],
        colors: [1, 2],
        board: board,
        icons: [PlayerIcon.secretAgent, PlayerIcon.swimmer],
      );
      addTearDown(game.dispose);
      await tester.runAsync(() async {
        await tester.pumpWidget(
          MaterialApp(home: GameScreen(controller: game)),
        );
        await Future<void>.delayed(const Duration(milliseconds: 100));
      });
      await tester.pump();
      expect(find.byTooltip('Change player icon'), findsNothing);
      expect(game.canChangePlayerIcon, isFalse);
      game.changePlayerIcon(PlayerIcon.paw);
      expect(game.session.currentPlayer.icon, PlayerIcon.secretAgent);
      await tester.tap(find.byTooltip('Character abilities'));
      await tester.pump(const Duration(milliseconds: 350));
      expect(find.text('Secret Agent'), findsOneWidget);
      expect(find.textContaining('Characters are locked'), findsOneWidget);
      expect(find.text('Choose your character'), findsNothing);
      final saved = await tester.runAsync(() async {
        await Future<void>.delayed(const Duration(milliseconds: 20));
        return SessionStore().load();
      });
      expect(saved!.players.first.icon, PlayerIcon.secretAgent);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets('Board token switches between number and icon glyphs', (
    tester,
  ) async {
    final token = PlayerToken(
      number: 2,
      color: Colors.red,
      position: Vector2.zero(),
    );
    await token.onLoad();
    // Mount queued caption components before inspecting their renderer.
    await token.addToParent(Component());
    await token.children.first.onLoad();
    token.setIcon(PlayerIcon.star);
    final caption = token.children.whereType<TextComponent>().single;
    expect(caption.text, String.fromCharCode(PlayerIcon.star.symbol.codePoint));
    token.setIcon(PlayerIcon.number);
    expect(caption.text, '2');
  });
}
