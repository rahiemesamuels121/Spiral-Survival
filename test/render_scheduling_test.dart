import 'package:flame/game.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:spiral_pass_play/features/game/application/game_controller.dart';
import 'package:spiral_pass_play/features/game/data/board_repository.dart';
import 'package:spiral_pass_play/features/game/domain/game_session.dart';
import 'package:spiral_pass_play/features/game/flame/spiral_board_game.dart';

class CountingBoardGame extends SpiralBoardGame {
  CountingBoardGame({required super.controller});
  int frames = 0;
  @override
  void render(Canvas canvas) {
    frames++;
    super.render(canvas);
  }
}

void main() {
  testWidgets('Idle frames stop; input and hidden game updates resume safely', (
    tester,
  ) async {
    final board = (await tester.runAsync(
      () => const BoardRepository().loadReferenceBoard(),
    ))!;
    final controller = GameController.newGame(
      names: ['One', 'Two'],
      colors: [1, 2],
      board: board,
      diceRoller: () => 1,
    );
    final game = CountingBoardGame(controller: controller);
    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: GameWidget(game: game),
      ),
    );
    await tester.runAsync(() async => game.toBeLoaded());
    for (var i = 0; i < 8; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(game.paused, isTrue);
    final idleFrames = game.frames;
    for (var i = 0; i < 60; i++) {
      await tester.pump(const Duration(milliseconds: 16));
    }
    expect(game.frames, idleFrames, reason: 'No redraws during an idle second');

    final zoom = game.camera.viewfinder.zoom;
    game.zoomBoard(1.2);
    expect(game.paused, isFalse);
    await tester.pump();
    await tester.pump();
    expect(game.frames, greaterThan(idleFrames));
    expect(game.camera.viewfinder.zoom, greaterThan(zoom));
    expect(game.paused, isTrue);

    game.setSceneVisible(false);
    controller.roll();
    expect(game.paused, isTrue, reason: 'Updates must not wake a hidden board');
    game.setSceneVisible(true);
    expect(game.paused, isFalse);
    for (var i = 0; i < 80; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(controller.session.players.first.position, 1);
    expect(controller.session.phase, isNot(TurnPhase.animating));
    expect(game.paused, isTrue);
    await tester.pumpWidget(const SizedBox.shrink());
    controller.dispose();
  });
  testWidgets(
    'Blue birds wake an idle board and respect hidden and reduced motion',
    (tester) async {
      final board = (await tester.runAsync(
        () => const BoardRepository().loadReferenceBoard(),
      ))!;
      final controller = GameController.newGame(
        names: ['One', 'Two'],
        colors: [1, 2],
        board: board,
      );
      final game = CountingBoardGame(controller: controller);
      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: GameWidget(game: game),
        ),
      );
      await tester.runAsync(() async => game.toBeLoaded());
      for (var i = 0; i < 8; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      expect(game.paused, isTrue);
      await tester.pump(const Duration(seconds: 20));
      expect(game.ambientBirds.isFlying, isTrue);
      expect(game.paused, isFalse);
      for (var i = 0; i < 65; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      expect(game.ambientBirds.isFlying, isFalse);
      expect(game.paused, isTrue);
      game.setAmbientMotionEnabled(false);
      await tester.pump();
      await tester.pump();
      final frames = game.frames;
      await tester.pump(const Duration(seconds: 30));
      expect(game.ambientBirds.isFlying, isFalse);
      expect(game.frames, frames);
      game.setAmbientMotionEnabled(true);
      game.setSceneVisible(false);
      await tester.pump(const Duration(seconds: 30));
      expect(game.ambientBirds.isFlying, isFalse);
      expect(game.paused, isTrue);
      game.setSceneVisible(true);
      game.lifecycleStateChange(AppLifecycleState.paused);
      await tester.pump(const Duration(seconds: 30));
      expect(game.ambientBirds.isFlying, isFalse);
      expect(game.paused, isTrue);
      game.lifecycleStateChange(AppLifecycleState.resumed);
      await tester.pump(const Duration(seconds: 20));
      expect(game.ambientBirds.isFlying, isTrue);
      await tester.pumpWidget(const SizedBox.shrink());
      controller.dispose();
    },
  );
}
