import 'dart:ui';
import 'package:flutter_test/flutter_test.dart';
import 'package:spiral_pass_play/app/theme.dart';
import 'package:spiral_pass_play/features/game/vector/ambient_birds.dart';

void main() {
  test('Birds use the blue palette and clear after a six second flight', () {
    final birds = AmbientBirds();
    expect(AmbientBirds.color, AppTheme.sky);
    birds.start(const Rect.fromLTWH(0, 0, 390, 844));
    birds.update(5.9);
    expect(birds.isFlying, isTrue);
    birds.update(.2);
    expect(birds.isFlying, isFalse);
    birds.start(const Rect.fromLTWH(0, 0, 390, 844));
    birds.clear();
    expect(birds.isFlying, isFalse);
  });
}
