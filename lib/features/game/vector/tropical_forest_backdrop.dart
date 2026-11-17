import 'dart:math' as math;
import 'dart:ui' as ui;
import 'package:flutter/material.dart';

/// A cached forest floor in world coordinates. Native drawing commands are recorded
/// once per viewport size; panning and token movement do not rebuild the foliage.
class TropicalForestBackdrop {
  ui.Picture? _picture;
  Size? _size;

  void paint(Canvas canvas, Size size) {
    if (size.isEmpty || !size.width.isFinite || !size.height.isFinite) return;
    if (_picture == null || _size != size) {
      dispose();
      final recorder = ui.PictureRecorder();
      _draw(Canvas(recorder), size);
      _picture = recorder.endRecording();
      _size = size;
    }
    canvas.drawPicture(_picture!);
  }

  void dispose() {
    _picture?.dispose();
    _picture = null;
    _size = null;
  }

  void _draw(Canvas canvas, Size size) {
    final random = math.Random(71421);
    final w = size.width;
    final h = size.height;
    final bounds = Offset.zero & size;
    final unit = (math.min(w, h) / 390).clamp(.8, 4.0);
    final paint = Paint();
    canvas.drawRect(
      bounds,
      paint
        ..shader = ui.Gradient.linear(
          Offset.zero,
          Offset(w * .65, h),
          const [Color(0xFF091A2B), Color(0xFF1B403D), Color(0xFF142E45)],
          const [0, .5, 1],
        ),
    );
    paint.shader = null;

    // Uneven patches of moss and leaf litter soften the forest floor.
    for (var i = 0; i < 35; i++) {
      final x = random.nextDouble() * w;
      final y = random.nextDouble() * h;
      canvas.drawOval(
        Rect.fromCenter(
          center: Offset(x, y),
          width: (45 + random.nextDouble() * 130) * unit,
          height: (25 + random.nextDouble() * 70) * unit,
        ),
        paint
          ..color = [
            const Color(0x222E6942),
            const Color(0x2239794B),
            const Color(0x22333F23),
          ][i % 3],
      );
    }
    _stream(canvas, size, unit);
    for (var i = 0; i < (w * h / 850).ceil(); i++) {
      final x = random.nextDouble() * w;
      final y = random.nextDouble() * h;
      canvas.drawLine(
        Offset(x, y),
        Offset(x + 2.5 * unit, y - unit),
        paint
          ..color = i.isEven ? const Color(0x334E7444) : const Color(0x333E3927)
          ..strokeWidth = unit
          ..strokeCap = StrokeCap.round,
      );
    }

    final spacing = 112 * unit;
    for (var row = -1; row <= (h / spacing).ceil(); row++) {
      for (var column = -1; column <= (w / spacing).ceil(); column++) {
        final center = Offset(
          (column + .5) * spacing + (random.nextDouble() - .5) * spacing * .75,
          (row + .5) * spacing + (random.nextDouble() - .5) * spacing * .75,
        );
        final radius = (43 + random.nextDouble() * 25) * unit;
        if ((row + column) % 3 == 0) {
          _palm(canvas, center, radius, random);
        } else {
          _broadleaf(canvas, center, radius * .8, random);
        }
        if (random.nextDouble() > .65) {
          _rocks(
            canvas,
            center + Offset(radius * .55, radius * .6),
            unit,
            random,
          );
        }
      }
    }
    // Small ferns fill the gaps without obscuring the main canopy shapes.
    for (var i = 0; i < (w * h / 12000).ceil(); i++) {
      final center = Offset(random.nextDouble() * w, random.nextDouble() * h);
      _palm(
        canvas,
        center,
        (19 + random.nextDouble() * 10) * unit,
        random,
        fern: true,
      );
      if (i % 5 == 0) _flowers(canvas, center, unit);
    }
    canvas.drawRect(
      bounds,
      Paint()
        ..shader = ui.Gradient.radial(
          Offset(w / 2, h / 2),
          math.max(w, h) * .68,
          const [Color(0x00051512), Color(0x6610201B)],
          const [.25, 1],
        ),
    );
  }

  void _stream(Canvas canvas, Size size, double unit) {
    final w = size.width;
    final h = size.height;
    final path = Path()
      ..moveTo(-w * .1, h * .15)
      ..cubicTo(w * .12, h * .04, w * .38, h * .26, w * .61, h * .13)
      ..cubicTo(w * .83, h * .02, w * .86, h * .3, w * 1.1, h * .25);
    final lower = Path()
      ..moveTo(-w * .1, h * .86)
      ..cubicTo(w * .22, h * .72, w * .28, h * 1.03, w * .63, h * .88)
      ..cubicTo(w * .83, h * .79, w, h * .94, w * 1.1, h * .84);
    path.addPath(lower, Offset.zero);
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;
    canvas.drawPath(
      path,
      paint
        ..color = const Color(0xFF20392A)
        ..strokeWidth = 39 * unit,
    );
    canvas.drawPath(
      path,
      paint
        ..color = const Color(0xFF8E7359)
        ..strokeWidth = 28 * unit,
    );
    canvas.drawPath(
      path,
      paint
        ..color = const Color(0xFF123D3C)
        ..strokeWidth = 22 * unit,
    );
    canvas.drawPath(
      path,
      paint
        ..color = const Color(0xFF286C87)
        ..strokeWidth = 13 * unit,
    );
    canvas.drawPath(
      path,
      paint
        ..color = const Color(0x66558D7D)
        ..strokeWidth = 2 * unit,
    );
  }

  void _palm(
    Canvas canvas,
    Offset center,
    double radius,
    math.Random random, {
    bool fern = false,
  }) {
    canvas.save();
    canvas.translate(center.dx, center.dy);
    canvas.rotate(random.nextDouble() * math.pi * 2);
    final paint = Paint();
    canvas.drawOval(
      Rect.fromCenter(
        center: Offset(radius * .12, radius * .18),
        width: radius * 1.6,
        height: radius * 1.35,
      ),
      paint..color = const Color(0x33071915),
    );
    final count = fern ? 7 : 9;
    for (var branch = 0; branch < count; branch++) {
      canvas.save();
      canvas.rotate(
        branch * math.pi * 2 / count + (random.nextDouble() - .5) * .28,
      );
      final length = radius * (.78 + random.nextDouble() * .25);
      final bend = (random.nextDouble() - .5) * length * .5;
      final leaves = Path();
      for (var step = 1; step <= 8; step++) {
        final t = step / 9;
        final y = -length * t;
        final x = bend * t * t;
        final width = length * .21 * math.sin(t * math.pi) + 1;
        for (final side in [-1.0, 1.0]) {
          leaves.moveTo(x, y + length * .09);
          leaves.quadraticBezierTo(
            x + side * width * .65,
            y + length * .04,
            x + side * width,
            y - length * .13,
          );
          leaves.quadraticBezierTo(
            x + side * width * .26,
            y - length * .1,
            x,
            y,
          );
          leaves.close();
        }
      }
      leaves.moveTo(0, 2);
      leaves.quadraticBezierTo(bend * .3 - 1, -length * .5, bend, -length);
      leaves.quadraticBezierTo(bend * .3 + 1, -length * .5, 0, 2);
      paint.color = (fern
          ? const [Color(0xFF44734A), Color(0xFF587E49), Color(0xFF386642)]
          : const [
              Color(0xFF275C3C),
              Color(0xFF347749),
              Color(0xFF43854C),
            ])[branch % 3];
      canvas.drawPath(leaves, paint);
      canvas.drawPath(
        Path()
          ..moveTo(0, 0)
          ..quadraticBezierTo(bend * .3, -length * .5, bend, -length),
        Paint()
          ..color = const Color(0x886D9A57)
          ..style = PaintingStyle.stroke
          ..strokeWidth = .8,
      );
      canvas.restore();
    }
    canvas.drawCircle(
      Offset.zero,
      fern ? 2 : 3.5,
      paint..color = const Color(0xFF6E7342),
    );
    canvas.restore();
  }

  void _broadleaf(
    Canvas canvas,
    Offset center,
    double radius,
    math.Random random,
  ) {
    canvas.save();
    canvas.translate(center.dx, center.dy);
    canvas.rotate(random.nextDouble() * math.pi * 2);
    final paint = Paint();
    canvas.drawOval(
      Rect.fromCenter(
        center: Offset(radius * .13, radius * .2),
        width: radius * 1.7,
        height: radius * 1.3,
      ),
      paint..color = const Color(0x44091E17),
    );
    for (var i = 0; i < 7; i++) {
      canvas.save();
      canvas.rotate(i * math.pi * 2 / 7);
      final length = radius * (.7 + random.nextDouble() * .35);
      final width = length * .27;
      final bend = length * .18;
      final leaf = Path()
        ..moveTo(0, 2)
        ..cubicTo(
          -width,
          -length * .25,
          -width + bend,
          -length * .75,
          bend,
          -length,
        )
        ..cubicTo(width + bend, -length * .7, width, -length * .25, 0, 2)
        ..close();
      canvas.drawPath(
        leaf,
        paint
          ..color = const [
            Color(0xFF204F36),
            Color(0xFF2B6540),
            Color(0xFF347246),
            Color(0xFF426F42),
          ][i % 4],
      );
      canvas.drawPath(
        Path()
          ..moveTo(0, 0)
          ..quadraticBezierTo(bend * .3, -length * .6, bend, -length),
        Paint()
          ..color = const Color(0x886B965B)
          ..style = PaintingStyle.stroke
          ..strokeWidth = .9,
      );
      canvas.restore();
    }
    canvas.restore();
  }

  void _rocks(Canvas canvas, Offset center, double unit, math.Random random) {
    final paint = Paint();
    for (var i = 0; i < 3; i++) {
      final point =
          center +
          Offset(
            (random.nextDouble() - .5) * 22 * unit,
            (random.nextDouble() - .5) * 14 * unit,
          );
      final rect = Rect.fromCenter(
        center: point,
        width: (9 + random.nextDouble() * 10) * unit,
        height: (6 + random.nextDouble() * 7) * unit,
      );
      canvas.drawOval(
        rect.translate(2 * unit, 3 * unit),
        paint..color = const Color(0x55091D17),
      );
      canvas.drawOval(rect, paint..color = const Color(0xFF586654));
      canvas.drawOval(
        Rect.fromCenter(
          center: point - Offset(2 * unit, 2 * unit),
          width: rect.width * .65,
          height: rect.height * .6,
        ),
        paint..color = const Color(0xFF9D8870),
      );
      canvas.drawCircle(
        point + Offset(3 * unit, 0),
        3 * unit,
        paint..color = const Color(0xFF3F6743),
      );
    }
  }

  void _flowers(Canvas canvas, Offset center, double unit) {
    final paint = Paint()..color = const Color(0xFF9E7146);
    canvas.drawLine(
      center,
      center + Offset(0, -14 * unit),
      paint..strokeWidth = 1.4 * unit,
    );
    for (var i = 0; i < 3; i++) {
      final p =
          center + Offset(i.isEven ? -2.0 * unit : 2.0 * unit, -5.0 * i * unit);
      canvas.drawOval(
        Rect.fromCenter(center: p, width: 7 * unit, height: 3.5 * unit),
        paint
          ..color = i.isEven
              ? const Color(0xFFE63C25)
              : const Color(0xFFFFC34A),
      );
    }
  }
}
