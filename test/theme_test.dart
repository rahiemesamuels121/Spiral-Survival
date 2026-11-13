import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:spiral_pass_play/app/theme.dart';

double contrast(Color a, Color b) {
  final x = a.computeLuminance();
  final y = b.computeLuminance();
  return x > y ? (x + .05) / (y + .05) : (y + .05) / (x + .05);
}

void main() {
  test('Premium interface keeps readable text contrast', () {
    for (final pair in [
      (AppTheme.gold, AppTheme.navy),
      (AppTheme.text, AppTheme.panel),
      (AppTheme.muted, AppTheme.panel),
      (AppTheme.ink, AppTheme.ivory),
      (AppTheme.ivory, AppTheme.teal),
    ]) {
      expect(contrast(pair.$1, pair.$2), greaterThanOrEqualTo(4.5));
    }
  });
  test('All five player colors support readable numbered markers', () {
    for (final color in AppTheme.playerColors) {
      expect(contrast(color, AppTheme.navy), greaterThanOrEqualTo(4.5));
    }
  });
}
