import 'package:flame/components.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:spiral_pass_play/features/game/flame/spiral_board_game.dart';

PlayerToken token() =>
    PlayerToken(number: 1, color: Colors.red, position: Vector2.zero());

void main() {
  test('Movement retains elapsed time across frames and ends exactly once', () {
    final coarse = token();
    final fine = token();
    var coarseCompleted = 0;
    var fineCompleted = 0;
    final steps = [Vector2(40, 0), Vector2(80, 0), Vector2(80, 40)];
    coarse.walk(steps, () => coarseCompleted++);
    fine.walk(steps, () => fineCompleted++);
    coarse.update(.7);
    for (var i = 0; i < 70; i++) {
      fine.update(.01);
    }
    expect(coarse.position.distanceTo(fine.position), lessThan(.001));
    coarse.update(.3);
    fine.update(.3);
    expect(coarse.position.distanceTo(steps.last), lessThan(.001));
    expect(fine.position.distanceTo(steps.last), lessThan(.001));
    coarse.update(1);
    expect(coarseCompleted, 1);
    expect(fineCompleted, 1);
  });

  test('Token flows through adjoining spaces without a stop', () {
    final player = token();
    player.walk([Vector2(40, 0), Vector2(80, 0)], () {});
    player.update(PlayerToken.secondsPerSpace - .001);
    final before = player.position.x;
    player.update(.001);
    final boundary = player.position.x;
    player.update(.001);
    final after = player.position.x;
    expect(boundary - before, greaterThan(.1));
    expect(after - boundary, closeTo(boundary - before, .005));
  });

  test(
    'Mine death shrinks at impact and respawns at START before completion',
    () {
      final player = token()..position.setValues(300, 400);
      var completed = 0;
      player.dieAndRespawn(Vector2(20, 30), () => completed++);
      player.update(.3);
      expect(player.position.x, 300);
      expect(player.scale.x, lessThan(1));
      expect(completed, 0);
      player.update(.2);
      expect(player.position.x, 20);
      expect(player.position.y, 30);
      expect(player.scale.x, lessThan(.2));
      player.update(.5);
      expect(player.scale.x, 1);
      expect(completed, 1);
      player.update(1);
      expect(completed, 1);
    },
  );
}
