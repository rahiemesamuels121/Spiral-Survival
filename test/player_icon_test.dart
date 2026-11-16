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
    await tester.ensureVisible(find.text('Star'));
    await tester.tap(find.text('Star'));
    await tester.pumpAndSettle();
    final avatars = tester
        .widgetList<PlayerAvatar>(find.byType(PlayerAvatar))
        .toList();
    expect(avatars.first.icon, PlayerIcon.star);
    expect(avatars[1].icon, PlayerIcon.number);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Changing an icon updates the board token and saved game', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(900, 600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final board = (await tester.runAsync(
      () => const BoardRepository().loadReferenceBoard(),
    ))!;
    final game = GameController.newGame(
      names: ['One', 'Two'],
      colors: [0xFFCC3333, 0xFF33CC33],
      board: board,
    );
    addTearDown(game.dispose);
    await tester.runAsync(() async {
      await tester.pumpWidget(MaterialApp(home: GameScreen(controller: game)));
      await Future<void>.delayed(const Duration(milliseconds: 100));
    });
    await tester.pump();
    await tester.tap(find.byTooltip('Change player icon'));
    await tester.pump(const Duration(milliseconds: 350));
    expect(find.text('Choose player icon'), findsOneWidget);
    await tester.tap(find.text('Rocket'));
    await tester.pump(const Duration(milliseconds: 350));
    expect(game.session.players.first.icon, PlayerIcon.rocket);
    expect(game.session.players[1].icon, PlayerIcon.number);
    final token = tester.widget<GameScreen>(find.byType(GameScreen));
    expect(token.controller.session.players.first.icon, PlayerIcon.rocket);
    final saved = await tester.runAsync(() async {
      await Future<void>.delayed(const Duration(milliseconds: 20));
      return SessionStore().load();
    });
    expect(saved!.players.first.icon, PlayerIcon.rocket);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

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
