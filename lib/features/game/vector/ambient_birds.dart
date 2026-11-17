import 'dart:math' as math;
import 'dart:ui';
import '../../../app/theme.dart';

/// A short cosmetic flight; the game only ticks while the birds are visible.
class AmbientBirds {
  static const duration = 6.0;
  static const color = AppTheme.sky;
  double? _age;
  Rect _route = Rect.zero;
  bool _reverse = false;
  bool get isFlying => _age != null;

  void start(Rect route, {bool reverse = false}) {
    _route = route;
    _reverse = reverse;
    _age = 0;
  }

  void clear() => _age = null;

  void update(double dt) {
    if (_age == null || !dt.isFinite || dt <= 0) return;
    _age = _age! + dt;
    if (_age! >= duration) clear();
  }

  void paint(Canvas canvas) {
    if (_age == null || _route.isEmpty) return;
    final t = (_age! / duration).clamp(0.0, 1.0);
    final x = _route.left + _route.width * (-.15 + 1.3 * t);
    final y = _route.top + _route.height * (.25 + .13 * t);
    final unit = math.min(_route.width, _route.height) / 390;
    final opacity = (math.min(t, 1 - t) * 7).clamp(0.0, .9);
    final paint = Paint()
      ..color = color.withValues(alpha: opacity)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.8 * unit
      ..strokeCap = StrokeCap.round;
    for (var i = 0; i < 5; i++) {
      final px = _reverse ? _route.left + _route.right - x : x;
      final dx = (i.isEven ? -1 : 1) * (i + 1) * 9 * unit;
      final dy = i * 8 * unit;
      final flap = math.sin(_age! * 8 + i * .7) * 4 * unit;
      canvas.drawPath(
        Path()
          ..moveTo(px + dx - 6 * unit, y + dy - flap)
          ..quadraticBezierTo(
            px + dx - 3 * unit,
            y + dy - 3 * unit,
            px + dx,
            y + dy,
          )
          ..quadraticBezierTo(
            px + dx + 3 * unit,
            y + dy - 3 * unit,
            px + dx + 6 * unit,
            y + dy - flap,
          ),
        paint,
      );
    }
  }
}
