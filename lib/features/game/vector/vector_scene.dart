import 'dart:math' as math;
import 'package:flutter/material.dart';

String svgEscape(String text) => text
    .replaceAll('&', '&amp;')
    .replaceAll('<', '&lt;')
    .replaceAll('>', '&gt;')
    .replaceAll('"', '&quot;')
    .replaceAll("'", '&apos;');
String vectorNumber(num n) => n.toStringAsFixed(2);
String colorHex(int value) =>
    '#${(value & 0xFFFFFF).toRadixString(16).padLeft(6, '0')}';

/// One set of vector primitives drives native Canvas drawing and SVG export.
/// No raster images or screenshot tracing are used.
class VectorScene {
  final List<_Node> _nodes = [];
  void beginGroup(String id, {String? title}) => _nodes.add(
    _Markup(
      '<g id="${svgEscape(id)}">'
      '${title == null ? '' : '<title>${svgEscape(title)}</title>'}',
    ),
  );
  void endGroup() => _nodes.add(_Markup('</g>'));
  static const gradients = <String, List<int>>{
    'navy': [0xFF355263, 0xFF213747],
    'gold': [0xFFF0DAA7, 0xFFD7B976, 0xFFE8CF96],
    'ivory': [0xFFF9F3E5, 0xFFECE2CC],
    'blue': [0xFF397F9A, 0xFF24596F],
    'red': [0xFFAA5355, 0xFF823D47],
    'green': [0xFFDBEBDD, 0xFFA9C9B6],
    'purple': [0xFF7D6A9D, 0xFF594C78],
  };

  void rect(
    Rect rect, {
    String fill = 'none',
    String stroke = 'none',
    double line = 1,
    double radius = 0,
  }) {
    final path = Path()
      ..addRRect(RRect.fromRectAndRadius(rect, Radius.circular(radius)));
    _nodes.add(
      _Shape(
        path,
        '<rect x="${vectorNumber(rect.left)}" y="${vectorNumber(rect.top)}" width="${vectorNumber(rect.width)}" height="${vectorNumber(rect.height)}" rx="${vectorNumber(radius)}"',
        fill,
        stroke,
        line,
      ),
    );
  }

  void ellipse(
    double x,
    double y,
    double rx,
    double ry, {
    String fill = 'none',
    String stroke = 'none',
    double line = 1,
  }) {
    final path = Path()
      ..addOval(
        Rect.fromCenter(center: Offset(x, y), width: rx * 2, height: ry * 2),
      );
    _nodes.add(
      _Shape(
        path,
        '<ellipse cx="${vectorNumber(x)}" cy="${vectorNumber(y)}" rx="${vectorNumber(rx)}" ry="${vectorNumber(ry)}"',
        fill,
        stroke,
        line,
      ),
    );
  }

  void path(
    VectorPath path, {
    String fill = 'none',
    String stroke = 'none',
    double line = 1,
  }) {
    _nodes.add(_Shape(path.path, '<path d="${path.data}"', fill, stroke, line));
  }

  void text(
    String value,
    double x,
    double y, {
    double size = 12,
    String color = '#FFF6DB',
    bool bold = true,
  }) {
    _nodes.add(_Text(value, x, y, size, color, bold));
  }

  void paint(Canvas canvas) {
    for (final node in _nodes) {
      node.paint(canvas);
    }
  }

  String toSvg({String title = 'Spiral Quest board'}) {
    final defs = gradients.entries.map((entry) {
      final colors = entry.value;
      return '<linearGradient id="${entry.key}" x1="0" y1="0" x2="1" y2="1">${[for (var i = 0; i < colors.length; i++) '<stop offset="${i / (colors.length - 1)}" stop-color="${colorHex(colors[i])}"/>'].join()}</linearGradient>';
    }).join();
    return '<?xml version="1.0" encoding="UTF-8"?>\n'
        '<svg xmlns="http://www.w3.org/2000/svg" width="1261" height="1261" viewBox="0 0 1000 1000" role="img">'
        '<title>${svgEscape(title)}</title><desc>Editable vector recreation with 120 individually mapped spaces. All artwork is paths, shapes, and text.</desc>'
        '<defs>$defs</defs>${_nodes.map((node) => node.svg).join()}</svg>\n';
  }
}

class VectorPath {
  final Path path = Path();
  final StringBuffer _data = StringBuffer();
  String get data => _data.toString();
  void move(double x, double y) {
    path.moveTo(x, y);
    _data.write('M${vectorNumber(x)} ${vectorNumber(y)}');
  }

  void line(double x, double y) {
    path.lineTo(x, y);
    _data.write('L${vectorNumber(x)} ${vectorNumber(y)}');
  }

  void cubic(double x1, double y1, double x2, double y2, double x, double y) {
    path.cubicTo(x1, y1, x2, y2, x, y);
    _data.write(
      'C${vectorNumber(x1)} ${vectorNumber(y1)} ${vectorNumber(x2)} ${vectorNumber(y2)} ${vectorNumber(x)} ${vectorNumber(y)}',
    );
  }

  void close() {
    path.close();
    _data.write('Z');
  }

  void polygon(List<Offset> points) {
    move(points.first.dx, points.first.dy);
    for (final point in points.skip(1)) {
      line(point.dx, point.dy);
    }
    close();
  }

  void star(double x, double y, double radius, {int points = 5}) {
    polygon([
      for (var i = 0; i < points * 2; i++)
        Offset(
          x +
              math.cos(-math.pi / 2 + i * math.pi / points) *
                  radius *
                  (i.isEven ? 1 : .43),
          y +
              math.sin(-math.pi / 2 + i * math.pi / points) *
                  radius *
                  (i.isEven ? 1 : .43),
        ),
    ]);
  }
}

abstract class _Node {
  void paint(Canvas canvas);
  String get svg;
}

class _Markup extends _Node {
  _Markup(this.svg);
  @override
  final String svg;
  @override
  void paint(Canvas canvas) {}
}

Paint _paint(
  String value,
  Rect bounds, {
  bool stroke = false,
  double line = 1,
}) {
  final paint = Paint()
    ..style = stroke ? PaintingStyle.stroke : PaintingStyle.fill
    ..strokeWidth = line
    ..strokeJoin = StrokeJoin.round
    ..strokeCap = StrokeCap.round;
  if (value.startsWith('url(#')) {
    final colors = VectorScene.gradients[value.substring(5, value.length - 1)]!;
    paint.shader = LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: colors.map(Color.new).toList(),
    ).createShader(bounds.inflate(.01));
  } else {
    paint.color = Color(0xFF000000 | int.parse(value.substring(1), radix: 16));
  }
  return paint;
}

class _Shape extends _Node {
  _Shape(this.path, this.tag, this.fill, this.stroke, this.line);
  final Path path;
  final String tag, fill, stroke;
  final double line;
  late final Rect _bounds = path.getBounds();
  late final Paint _fillPaint = _paint(fill, _bounds);
  late final Paint _strokePaint = _paint(
    stroke,
    _bounds,
    stroke: true,
    line: line,
  );

  @override
  void paint(Canvas canvas) {
    if (fill != 'none') canvas.drawPath(path, _fillPaint);
    if (stroke != 'none') canvas.drawPath(path, _strokePaint);
  }

  @override
  String get svg =>
      '$tag fill="$fill" stroke="$stroke" stroke-width="${vectorNumber(line)}" stroke-linecap="round" stroke-linejoin="round"/>';
}

class _Text extends _Node {
  _Text(this.value, this.x, this.y, this.size, this.color, this.bold);
  final String value, color;
  final double x, y, size;
  final bool bold;
  TextPainter? _painter;
  @override
  void paint(Canvas canvas) {
    final painter = _painter ??= (TextPainter(
      text: TextSpan(
        text: value,
        style: TextStyle(
          fontFamily: 'Arial',
          fontSize: size,
          height: 1,
          fontWeight: bold ? FontWeight.w800 : FontWeight.w400,
          color: Color(0xFF000000 | int.parse(color.substring(1), radix: 16)),
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout());
    painter.paint(
      canvas,
      Offset(x - painter.width / 2, y - painter.height / 2),
    );
  }

  @override
  String get svg =>
      '<text x="${vectorNumber(x)}" y="${vectorNumber(y)}" text-anchor="middle" dominant-baseline="central" font-family="Arial,sans-serif" font-size="${vectorNumber(size)}" font-weight="${bold ? 800 : 400}" fill="$color">${svgEscape(value)}</text>';
}
