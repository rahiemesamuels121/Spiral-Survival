import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../domain/board_definition.dart';
import 'vector_scene.dart';

/// Shared tile geometry and artwork for the game and development exports.
class BoardArtwork {
  BoardArtwork(this.board) {
    _build();
  }
  final BoardDefinition board;
  final VectorScene scene = VectorScene();
  static const symbols = BoardTile.artworkValues;

  static String symbolFor(BoardTile tile) {
    if (tile.artwork != null && symbols.contains(tile.artwork)) {
      return tile.artwork == 'spiral' ? 'portal' : tile.artwork!;
    }
    return switch (tile.type) {
      TileType.start => 'startFlag',
      TileType.sea => 'water',
      TileType.boat => 'boat',
      TileType.antidote => 'antidote',
      TileType.rawMeat => 'rawMeat',
      TileType.lion => 'lion',
      TileType.snake => 'snake',
      TileType.cash => tile.label.contains('TRAIN') ? 'train' : 'cash',
      TileType.police => 'police',
      TileType.fine => 'cash',
      TileType.jail || TileType.goToJail => 'jail',
      TileType.mine => 'mine',
      TileType.portal => 'portal',
      TileType.setBack => 'back',
      TileType.moveForward => 'forward',
      TileType.shop => 'shop',
      TileType.event => 'dice',
      TileType.confusion => 'confusion',
      TileType.star => 'star',
      TileType.hospital => 'hospital',
      TileType.fire => 'fire',
      TileType.trapDoor => 'trapDoor',
      TileType.finish => 'stop',
      TileType.normal => switch (tile.label.toUpperCase()) {
        'JET' => 'jet',
        'FIRE' => 'fire',
        'SURF' => 'surf',
        'BOAT' => 'boat',
        'ORANGE ICON' => 'diamond',
        'SPIRAL' => 'portal',
        'S' => 'lion',
        _ => 'none',
      },
    };
  }

  static const squareSize = 50.0;
  static Size tileSize(BoardTile tile) => const Size.square(squareSize);

  static Rect tileRect(BoardTile tile) => Rect.fromCenter(
    center: Offset(tile.x * 1000, tile.y * 1000),
    width: tileSize(tile).width,
    height: tileSize(tile).height,
  );

  static const _playColors = ['#608D93', '#9F747A', '#C6AA70', '#699887'];
  static const _playTints = ['#192E39', '#1C2C39', '#203438', '#1C3438'];

  void _build() {
    scene.rect(const Rect.fromLTWH(0, 0, 1000, 1000), fill: '#101E29');
    for (var i = 0; i < 4; i++) {
      scene.rect(
        Rect.fromLTWH(i.isEven ? 20 : 500, i < 2 ? 20 : 500, 480, 480),
        fill: _playTints[i],
        radius: 28,
      );
    }
    // Restrained foil details keep attention on the route and its symbols.
    for (final x in [250.0, 500.0, 750.0]) {
      for (final y in [250.0, 500.0, 750.0]) {
        scene.path(VectorPath()..star(x, y, 5), stroke: '#52635C', line: 1);
      }
    }
    scene.rect(
      const Rect.fromLTWH(8, 8, 984, 984),
      stroke: '#B69B67',
      line: 3,
      radius: 34,
    );
    scene.rect(
      const Rect.fromLTWH(17, 17, 966, 966),
      stroke: '#3D545B',
      line: 1,
      radius: 28,
    );
    final segments = <String, List<BoardTile>>{};
    for (final tile in board.tiles) {
      segments.putIfAbsent(tile.segment, () => []).add(tile);
    }
    var segmentIndex = 0;
    for (final tiles in segments.values) {
      if (tiles.length < 2) continue;
      final route = VectorPath()
        ..move(tiles.first.x * 1000, tiles.first.y * 1000);
      for (final tile in tiles.skip(1)) {
        route.line(tile.x * 1000, tile.y * 1000);
      }
      scene.path(route, stroke: _playColors[segmentIndex++ % 4], line: 73);
      scene.path(route, stroke: '#D8D1BE', line: 66);
    }
    scene.rect(
      const Rect.fromLTWH(360, 473, 280, 60),
      fill: '#142A34',
      stroke: '#A88E5F',
      line: 1,
      radius: 18,
    );
    scene.text('SPIRAL QUEST', 500, 500, size: 26, color: '#E5C889');
    scene.text(
      'FORTUNE  /  DANGER  /  SURVIVAL',
      500,
      520,
      size: 8,
      color: '#BBC6BC',
      bold: false,
    );
    scene.text('THE JOURNEY IS THE GAME', 500, 900, size: 10, color: '#BAC4B6');
    for (final tile in board.tiles) {
      _tile(tile);
    }
  }

  void _tile(BoardTile tile) {
    scene.beginGroup(
      'tile-${tile.index}',
      title:
          'Tile ${tile.index}: '
          '${tile.label.isEmpty ? tile.typeLabel : tile.label} · ${tile.typeLabel}',
    );
    final rect = tileRect(tile);
    final symbol = symbolFor(tile);
    final accent = _playColors[(tile.index ~/ 4) % 4];
    final fill = tile.fillColor != null
        ? colorHex(tile.fillColor!)
        : switch (tile.type) {
            TileType.mine => switch (tile.mineColor) {
              MineColor.red => '#B73542',
              MineColor.blue => '#236DC1',
              MineColor.green => '#27834C',
            },
            TileType.normal => tile.index.isEven ? '#F8F1E2' : '#EFE5D1',
            TileType.start || TileType.boat || TileType.sea => 'url(#blue)',
            TileType.rawMeat ||
            TileType.antidote ||
            TileType.snake ||
            TileType.cash ||
            TileType.moveForward => 'url(#green)',
            TileType.jail || TileType.goToJail || TileType.star => 'url(#gold)',
            TileType.police => 'url(#navy)',
            TileType.portal || TileType.confusion => 'url(#purple)',
            TileType.shop || TileType.event || TileType.hospital => '#F8F1E2',
            _ => 'url(#red)',
          };
    final darkText = tile.fillColor != null
        ? Color(tile.fillColor!).computeLuminance() > .4
        : ![
            TileType.start,
            TileType.boat,
            TileType.sea,
            TileType.police,
            TileType.portal,
            TileType.confusion,
            TileType.fire,
            TileType.mine,
            TileType.trapDoor,
            TileType.fine,
            TileType.setBack,
            TileType.finish,
          ].contains(tile.type);
    final ink = tile.textColor == null
        ? darkText
              ? '#213E47'
              : '#FFFFFF'
        : colorHex(tile.textColor!);
    scene.rect(rect, fill: fill, stroke: '#FCF5E5', line: 1.2, radius: 5);
    if (tile.type == TileType.normal) {
      scene.rect(
        Rect.fromLTWH(rect.left + 4, rect.top + 4, rect.width - 8, 3),
        fill: accent,
        radius: 1.5,
      );
    }
    scene.rect(
      rect.deflate(3),
      stroke: darkText ? accent : '#FFFFFF',
      line: .5,
      radius: 2,
    );
    final hasIcon = symbol != 'none';
    var label = tile.label.isEmpty && tile.type != TileType.normal
        ? tile.typeLabel
        : tile.label;
    if (label == 'START · SPIRAL') label = 'START';
    if (label == 'STOP · FINISH') label = 'FINISH';
    if (label == 'INSTANT DEATH · RETURN TO START') label = 'SEA';
    if (label == 'ORANGE ICON' || label == 'BLUE') label = '';
    final hasCaption = label.isNotEmpty;
    if (hasIcon) {
      final iconSize = math.min(
        rect.width - 12,
        rect.height * (hasCaption ? .56 : .86),
      );
      _icon(
        symbol,
        Rect.fromCenter(
          center: Offset(
            rect.center.dx,
            rect.top + rect.height * (hasCaption ? .34 : .5),
          ),
          width: iconSize,
          height: iconSize,
        ),
        ink,
      );
    }
    if (hasCaption) {
      final lines = _wrap(label, 8);
      final fontSize = math.min(
        hasIcon ? 9.0 : 10.0,
        (rect.width - 8) /
            math.max(
              1,
              lines.fold<int>(0, (n, line) => math.max(n, line.length)),
            ) /
            .65,
      );
      final labelY = hasIcon ? rect.top + rect.height * .76 : rect.center.dy;
      for (var i = 0; i < lines.length; i++) {
        scene.text(
          lines[i],
          rect.center.dx,
          labelY + (i - (lines.length - 1) / 2) * (fontSize + 1),
          size: fontSize,
          color: ink,
        );
      }
    }
    scene.endGroup();
  }

  static List<String> _wrap(String text, int length) {
    if (text.isEmpty) return [];
    final lines = <String>[];
    var current = '';
    for (final word in text.split(RegExp(r'\s+'))) {
      if (current.isNotEmpty && current.length + word.length + 1 > length) {
        lines.add(current);
        current = '';
      }
      current = current.isEmpty ? word : '$current $word';
    }
    if (current.isNotEmpty) lines.add(current);
    return lines;
  }

  static final Map<String, VectorScene> _illustrations = {};

  static VectorScene illustration(String symbol, {String ink = '#FFFFFF'}) =>
      _illustrations.putIfAbsent('$symbol:$ink', () {
        final result = VectorScene();
        _drawIcon(result, symbol, const Rect.fromLTWH(0, 0, 100, 100), ink);
        return result;
      });

  void _icon(String kind, Rect r, String ink) => _drawIcon(scene, kind, r, ink);

  static void _drawIcon(VectorScene scene, String kind, Rect r, String ink) {
    final p = _IconPen(scene, r);
    switch (kind) {
      case 'startFlag':
        p.rect(18, 8, 6, 78, fill: '#FFFFFF', radius: 2);
        p.polygon(
          [
            const Offset(24, 10),
            const Offset(87, 17),
            const Offset(68, 36),
            const Offset(24, 35),
          ],
          fill: '#70E7A7',
          stroke: '#FFFFFF',
          line: 3,
        );
        p.rect(10, 85, 29, 6, fill: '#FFFFFF', radius: 3);
      case 'star':
        p.polygon(
          [
            for (var i = 0; i < 10; i++)
              Offset(
                50 +
                    math.cos(-math.pi / 2 + i * math.pi / 5) *
                        (i.isEven ? 45 : 19),
                50 +
                    math.sin(-math.pi / 2 + i * math.pi / 5) *
                        (i.isEven ? 45 : 19),
              ),
          ],
          fill: '#208CCB',
          stroke: '#FFF0B5',
          line: 4,
        );
      case 'spiral':
      case 'portal':
        for (final offset in [0.0, math.pi]) {
          final points = [
            for (var i = 0; i < 100; i++)
              Offset(
                50 + math.cos(i * .14 + offset) * (3 + i * .44),
                50 + math.sin(i * .14 + offset) * (3 + i * .36),
              ),
          ];
          p.polyline(
            points,
            stroke: kind == 'portal' ? '#EAD9FF' : ink,
            line: 4,
          );
        }
      case 'police':
        p.rect(12, 67, 76, 13, fill: '#CED5DA');
        p.rect(
          20,
          27,
          60,
          40,
          fill: '#193F70',
          stroke: '#D9EDFF',
          line: 3,
          radius: 16,
        );
        p.rect(24, 33, 23, 29, fill: '#F24B68', radius: 8);
        p.rect(53, 33, 23, 29, fill: '#3DBBFF', radius: 8);
        for (final x in [10.0, 50.0, 90.0]) {
          p.polyline([Offset(x, 8), Offset(x, 18)], stroke: '#FFF3C8', line: 3);
        }
      case 'jail':
        p.rect(8, 10, 84, 78, fill: '#15243B', stroke: '#A77B3C', line: 4);
        for (var x = 19.0; x <= 85; x += 16) {
          p.rect(x, 12, 5, 73, fill: 'url(#gold)');
        }
        p.rect(8, 65, 84, 19, fill: '#D9AE5F');
      case 'antidote':
        p.rect(37, 1, 26, 16, fill: '#F1D58E', radius: 3);
        p.rect(
          30,
          18,
          40,
          66,
          fill: '#B5F3E7',
          stroke: '#F9FFF5',
          line: 3,
          radius: 9,
        );
        p.rect(34, 48, 32, 31, fill: '#2A9F79', radius: 5);
        p.rect(44, 30, 12, 38, fill: '#FFFCDE');
        p.rect(33, 43, 34, 12, fill: '#FFFCDE');
      case 'snake':
        p.curve(
          [
            const Offset(13, 78),
            const Offset(100, 92),
            const Offset(0, 40),
            const Offset(59, 47),
            const Offset(95, 60),
            const Offset(97, 12),
            const Offset(56, 18),
          ],
          stroke: '#E0BD63',
          line: 18,
        );
        p.curve(
          [
            const Offset(13, 78),
            const Offset(100, 92),
            const Offset(0, 40),
            const Offset(59, 47),
            const Offset(95, 60),
            const Offset(97, 12),
            const Offset(56, 18),
          ],
          stroke: '#6FB345',
          line: 12,
        );
        p.ellipse(51, 19, 20, 12, fill: '#9CCB52', stroke: '#1C3A25', line: 2);
        p.ellipse(45, 16, 3, 3, fill: '#15283C');
        p.polyline(
          [const Offset(33, 22), const Offset(17, 28), const Offset(9, 24)],
          stroke: '#FF7766',
          line: 2,
        );
      case 'water':
      case 'surf':
        for (var y = 20.0; y < 90; y += 22) {
          p.curve(
            [
              Offset(3, y),
              Offset(26, y - 19),
              Offset(31, y + 19),
              Offset(50, y),
              Offset(72, y - 19),
              Offset(79, y + 19),
              Offset(98, y),
            ],
            stroke: kind == 'surf' ? '#2778B7' : '#B8F3FF',
            line: 5,
          );
        }
        if (kind == 'surf') {
          p.ellipse(
            51,
            50,
            10,
            34,
            fill: '#FFD85C',
            stroke: '#276CAF',
            line: 3,
          );
          p.polyline(
            [const Offset(51, 20), const Offset(51, 80)],
            stroke: '#FFFFFF',
            line: 2,
          );
        }
      case 'ghost':
        p.ellipse(50, 35, 30, 27, fill: '#F6F4EC');
        p.polygon([
          const Offset(20, 34),
          const Offset(80, 34),
          const Offset(80, 87),
          const Offset(65, 76),
          const Offset(50, 89),
          const Offset(35, 76),
          const Offset(20, 87),
        ], fill: '#F6F4EC');
        p.ellipse(39, 37, 5, 8, fill: '#243C50');
        p.ellipse(61, 37, 5, 8, fill: '#243C50');
        p.ellipse(50, 59, 7, 9, fill: '#243C50');
      case 'skull':
        p.ellipse(50, 38, 32, 29, fill: '#F5EAD0');
        p.ellipse(37, 38, 8, 9, fill: '#173048');
        p.ellipse(63, 38, 8, 9, fill: '#173048');
        p.rect(33, 59, 34, 20, fill: '#F5EAD0', radius: 4);
      case 'boat':
        p.polygon(
          [
            const Offset(7, 59),
            const Offset(95, 50),
            const Offset(75, 78),
            const Offset(25, 78),
          ],
          fill: '#F9F6E4',
          stroke: '#B1DBE5',
          line: 2,
        );
        p.polygon([
          const Offset(24, 53),
          const Offset(40, 32),
          const Offset(70, 32),
          const Offset(82, 53),
        ], fill: '#E2F3EF');
        p.rect(41, 36, 24, 12, fill: '#276080');
        p.polyline(
          [const Offset(54, 31), const Offset(54, 9)],
          stroke: '#F0DB9A',
          line: 3,
        );
        p.polyline(
          [const Offset(5, 88), const Offset(93, 88)],
          stroke: '#81DEDF',
          line: 3,
        );
      case 'cash':
        p.rect(
          9,
          22,
          79,
          52,
          fill: '#D9E8A0',
          stroke: '#FFF1C1',
          line: 3,
          radius: 3,
        );
        p.rect(16, 29, 65, 38, stroke: '#427254', line: 2);
        p.ellipse(49, 48, 14, 18, fill: '#6E9C62');
        p.text(r'$', 49, 49, size: 29, ink: '#F7F1B6');
      case 'mine':
        for (var i = 0; i < 8; i++) {
          final angle = i * math.pi / 4;
          p.polyline(
            [
              Offset(50 + math.cos(angle) * 24, 48 + math.sin(angle) * 24),
              Offset(50 + math.cos(angle) * 43, 48 + math.sin(angle) * 43),
            ],
            stroke: '#173B67',
            line: 7,
          );
        }
        p.ellipse(50, 48, 29, 29, fill: '#173B67', stroke: '#EAF3FF', line: 3);
        p.ellipse(41, 37, 8, 5, fill: '#70A4D9');
        p.ellipse(53, 52, 8, 8, fill: '#FFDC64', stroke: '#FFFFFF', line: 2);
        p.text('!', 53, 51, size: 16, ink: '#173B67');
      case 'confusion':
        p.curve(
          [
            const Offset(18, 36),
            const Offset(25, 5),
            const Offset(76, 5),
            const Offset(83, 35),
          ],
          stroke: '#D4F9FF',
          line: 7,
        );
        p.polyline(
          [const Offset(69, 27), const Offset(83, 35), const Offset(86, 19)],
          stroke: '#D4F9FF',
          line: 6,
        );
        p.curve(
          [
            const Offset(83, 64),
            const Offset(76, 96),
            const Offset(24, 96),
            const Offset(18, 65),
          ],
          stroke: '#FFE47D',
          line: 7,
        );
        p.polyline(
          [const Offset(15, 82), const Offset(18, 65), const Offset(32, 72)],
          stroke: '#FFE47D',
          line: 6,
        );
        p.text('?', 50, 51, size: 36, ink: '#FFFFFF');
      case 'dice':
        p.rect(
          9,
          10,
          51,
          51,
          fill: '#AF343D',
          stroke: '#F5D995',
          line: 3,
          radius: 9,
        );
        p.rect(
          40,
          38,
          51,
          51,
          fill: '#FFF4D6',
          stroke: '#8D784D',
          line: 3,
          radius: 9,
        );
        for (final dot in [
          const Offset(23, 24),
          const Offset(44, 46),
          const Offset(53, 51),
          const Offset(78, 76),
          const Offset(53, 76),
          const Offset(78, 51),
        ]) {
          p.ellipse(dot.dx, dot.dy, 4, 4, fill: '#192E45');
        }
      case 'shop':
        p.rect(
          17,
          27,
          67,
          59,
          fill: '#9B6BA5',
          stroke: '#F5DBA6',
          line: 3,
          radius: 5,
        );
        p.curve(
          [
            const Offset(33, 36),
            const Offset(27, -3),
            const Offset(76, -3),
            const Offset(68, 36),
          ],
          stroke: '#FFF0D1',
          line: 5,
        );
        p.ellipse(51, 59, 12, 12, fill: '#FBE18D');
      case 'back':
      case 'forward':
        final back = kind == 'back';
        for (var i = 0; i < 2; i++) {
          final x = 24 + i * 39.0;
          p.polyline(
            [
              Offset(x + (back ? 21 : 0), 18),
              Offset(x + (back ? 0 : 21), 47),
              Offset(x + (back ? 21 : 0), 76),
            ],
            stroke: ink,
            line: 10,
          );
        }
      case 'stop':
        p.polygon(
          [
            for (var i = 0; i < 8; i++)
              Offset(
                50 + math.cos(math.pi / 8 + i * math.pi / 4) * 45,
                47 + math.sin(math.pi / 8 + i * math.pi / 4) * 45,
              ),
          ],
          fill: '#A62C32',
          stroke: '#FFE7A3',
          line: 4,
        );
        p.text('STOP', 50, 48, size: 20, ink: '#FFFFFF');
      case 'jet':
        p.polygon(
          [
            const Offset(50, 2),
            const Offset(60, 39),
            const Offset(95, 62),
            const Offset(94, 72),
            const Offset(59, 57),
            const Offset(57, 83),
            const Offset(70, 94),
            const Offset(50, 89),
            const Offset(30, 94),
            const Offset(43, 83),
            const Offset(41, 57),
            const Offset(6, 72),
            const Offset(5, 62),
            const Offset(40, 39),
          ],
          fill: '#3479E7',
          stroke: '#17428F',
          line: 2,
        );
      case 'hospital':
        p.rect(
          14,
          28,
          72,
          60,
          fill: '#E3F2F0',
          stroke: '#4B91AA',
          line: 3,
          radius: 3,
        );
        p.rect(
          32,
          5,
          36,
          39,
          fill: '#E3F2F0',
          stroke: '#4B91AA',
          line: 3,
          radius: 3,
        );
        p.rect(45, 11, 10, 26, fill: '#C84346');
        p.rect(37, 19, 26, 10, fill: '#C84346');
        p.rect(43, 64, 16, 24, fill: '#347C9B');
        for (final x in [24.0, 65.0]) {
          p.rect(x, 49, 12, 13, fill: '#70BECE');
        }
      case 'trapDoor':
        p.polygon(
          [
            const Offset(12, 45),
            const Offset(80, 45),
            const Offset(92, 86),
            const Offset(23, 86),
          ],
          fill: '#071526',
          stroke: '#E3B86F',
          line: 4,
        );
        p.polygon(
          [
            const Offset(12, 45),
            const Offset(25, 7),
            const Offset(92, 12),
            const Offset(80, 45),
          ],
          fill: '#A66C38',
          stroke: '#FFE1A0',
          line: 3,
        );
        p.polyline(
          [const Offset(37, 11), const Offset(30, 44)],
          stroke: '#633A26',
          line: 2,
        );
        p.polyline(
          [const Offset(59, 12), const Offset(52, 44)],
          stroke: '#633A26',
          line: 2,
        );
        p.polyline(
          [
            const Offset(50, 52),
            const Offset(56, 69),
            const Offset(48, 64),
            const Offset(56, 69),
            const Offset(60, 60),
          ],
          stroke: '#F0D08A',
          line: 4,
        );
      case 'fire':
        p.curve(
          [
            const Offset(51, 5),
            const Offset(70, 38),
            const Offset(19, 40),
            const Offset(36, 62),
            const Offset(47, 52),
            const Offset(63, 43),
            const Offset(67, 26),
            const Offset(115, 103),
            const Offset(4, 109),
            const Offset(30, 49),
          ],
          fill: '#F18431',
          stroke: '#FFCF75',
          line: 3,
          close: true,
        );
        p.ellipse(51, 71, 13, 17, fill: '#FFE5A0');
      case 'diamond':
        p.rect(14, 14, 72, 72, fill: '#B26326', stroke: '#665737', line: 4);
        p.polygon(
          [
            const Offset(50, 17),
            const Offset(83, 50),
            const Offset(50, 83),
            const Offset(17, 50),
          ],
          fill: '#F3AE40',
          stroke: '#FFF2C4',
          line: 2,
        );
        p.polyline(
          [const Offset(18, 18), const Offset(82, 82)],
          stroke: '#FFE197',
          line: 2,
        );
      case 'train':
        p.rect(
          18,
          35,
          67,
          35,
          fill: '#B53A3E',
          stroke: '#FFE3A1',
          line: 3,
          radius: 4,
        );
        p.rect(
          22,
          15,
          30,
          35,
          fill: '#B53A3E',
          stroke: '#FFE3A1',
          line: 3,
          radius: 3,
        );
        p.rect(29, 21, 16, 17, fill: '#8CD2DE');
        p.rect(67, 18, 10, 19, fill: '#B53A3E');
        for (final x in [30.0, 53.0, 76.0]) {
          p.ellipse(x, 74, 10, 10, fill: '#152A41', stroke: '#D3B676', line: 3);
        }
      case 'rawMeat':
        p.curve(
          const [
            Offset(24, 33),
            Offset(35, 12),
            Offset(82, 17),
            Offset(86, 43),
            Offset(90, 68),
            Offset(57, 87),
            Offset(32, 76),
            Offset(10, 66),
            Offset(10, 48),
            Offset(24, 33),
          ],
          fill: '#EF5770',
          stroke: '#FFFFFF',
          line: 4,
          close: true,
        );
        p.ellipse(53, 49, 13, 11, fill: '#FFF4DC', stroke: '#FFFFFF', line: 3);
        break;
      case 'lion':
        p.ellipse(50, 44, 38, 38, fill: '#B37A2D', stroke: '#FFE3A1', line: 3);
        p.ellipse(50, 43, 24, 28, fill: '#E9B653');
        p.ellipse(41, 38, 3, 3, fill: '#173048');
        p.ellipse(59, 38, 3, 3, fill: '#173048');
        p.polygon([
          const Offset(43, 49),
          const Offset(57, 49),
          const Offset(50, 57),
        ], fill: '#173048');
        p.polyline(
          [const Offset(39, 65), const Offset(50, 59), const Offset(61, 65)],
          stroke: '#654327',
          line: 3,
        );
      default:
        break;
    }
  }
}

class _IconPen {
  _IconPen(this.scene, this.bounds);
  final VectorScene scene;
  final Rect bounds;
  double x(double x) => bounds.left + x / 100 * bounds.width;
  double y(double y) => bounds.top + y / 100 * bounds.height;
  double scale(double n) => n / 100 * bounds.width;
  void rect(
    double left,
    double top,
    double width,
    double height, {
    String fill = 'none',
    String stroke = 'none',
    double line = 1,
    double radius = 0,
  }) => scene.rect(
    Rect.fromLTWH(x(left), y(top), scale(width), scale(height)),
    fill: fill,
    stroke: stroke,
    line: scale(line),
    radius: scale(radius),
  );
  void ellipse(
    double cx,
    double cy,
    double rx,
    double ry, {
    String fill = 'none',
    String stroke = 'none',
    double line = 1,
  }) => scene.ellipse(
    x(cx),
    y(cy),
    scale(rx),
    scale(ry),
    fill: fill,
    stroke: stroke,
    line: scale(line),
  );
  void polygon(
    List<Offset> points, {
    String fill = 'none',
    String stroke = 'none',
    double line = 1,
  }) => scene.path(
    VectorPath()..polygon(points.map((p) => Offset(x(p.dx), y(p.dy))).toList()),
    fill: fill,
    stroke: stroke,
    line: scale(line),
  );
  void polyline(
    List<Offset> points, {
    String stroke = 'none',
    double line = 1,
  }) {
    final path = VectorPath()..move(x(points.first.dx), y(points.first.dy));
    for (final p in points.skip(1)) {
      path.line(x(p.dx), y(p.dy));
    }
    scene.path(path, stroke: stroke, line: scale(line));
  }

  void curve(
    List<Offset> points, {
    String fill = 'none',
    String stroke = 'none',
    double line = 1,
    bool close = false,
  }) {
    final path = VectorPath()..move(x(points.first.dx), y(points.first.dy));
    for (var i = 1; i + 2 < points.length; i += 3) {
      path.cubic(
        x(points[i].dx),
        y(points[i].dy),
        x(points[i + 1].dx),
        y(points[i + 1].dy),
        x(points[i + 2].dx),
        y(points[i + 2].dy),
      );
    }
    if (close) path.close();
    scene.path(path, fill: fill, stroke: stroke, line: scale(line));
  }

  void text(
    String text,
    double cx,
    double cy, {
    double size = 12,
    String ink = '#FFFFFF',
  }) => scene.text(text, x(cx), y(cy), size: scale(size), color: ink);
}
