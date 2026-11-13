import 'package:flutter/material.dart';
import '../domain/board_definition.dart';
import '../domain/game_session.dart';
import '../vector/board_artwork.dart';
import '../vector/vector_scene.dart';

/// Shows the cause and consequence while keeping the written rules below it.
class TurnResultVisual extends StatelessWidget {
  const TurnResultVisual({
    required this.session,
    required this.board,
    super.key,
  });
  final GameSession session;
  final BoardDefinition board;

  @override
  Widget build(BuildContext context) {
    final summary = session.tileSummary;
    if (summary == null) return const SizedBox.shrink();
    final source = board.tiles[summary.landedIndex];
    final destination = board.tiles[summary.finalPosition];
    final arrested =
        session.phase == TurnPhase.jailChoice ||
        summary.title.toUpperCase().contains('POLICE');
    final attack =
        summary.title.toUpperCase().contains('STABBER') ||
        summary.title.toUpperCase().contains('PEW PEW');
    final drowned =
        summary.finalPosition == 0 &&
        (source.type == TileType.sea ||
            summary.message.toLowerCase().contains('drowned'));
    final died = drowned || summary.message.toLowerCase().contains('you died');
    final moved = summary.landedIndex != summary.finalPosition;
    final inventory =
        !moved &&
        {
          TileType.boat,
          TileType.antidote,
          TileType.rawMeat,
          TileType.cash,
          TileType.star,
          TileType.shop,
        }.contains(source.type);
    final from = arrested ? 'police' : BoardArtwork.symbolFor(source);
    final to = died
        ? 'ghost'
        : arrested
        ? 'jail'
        : attack || summary.finalPosition == 0
        ? 'startFlag'
        : inventory
        ? 'inventory'
        : BoardArtwork.symbolFor(destination);
    final label = drowned
        ? 'YOU DROWNED'
        : died
        ? 'YOU DIED'
        : arrested
        ? 'JAIL'
        : attack || summary.finalPosition == 0
        ? 'START'
        : inventory
        ? 'INVENTORY'
        : destination.typeLabel.toUpperCase();
    final turns = session.currentPlayer.skipTurns;
    return Semantics(
      label: '${source.typeLabel} to $label',
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Flexible(
                child: _badge(
                  from,
                  arrested ? 'POLICE' : source.typeLabel.toUpperCase(),
                  const Color(0xFF487884),
                ),
              ),
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 10),
                child: Icon(
                  Icons.arrow_forward_rounded,
                  color: Color(0xFF987642),
                  size: 32,
                ),
              ),
              Flexible(
                child: _badge(
                  to,
                  label,
                  died ? const Color(0xFF526078) : const Color(0xFF3D7565),
                  player: !died,
                ),
              ),
            ],
          ),
          if (turns > 0) ...[
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(
                  Icons.hourglass_bottom_rounded,
                  color: Color(0xFF987642),
                ),
                const SizedBox(width: 6),
                Text(
                  'Miss $turns ${turns == 1 ? 'turn' : 'turns'}',
                  style: const TextStyle(
                    color: Color(0xFF254849),
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _badge(
    String symbol,
    String label,
    Color color, {
    bool player = false,
  }) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Stack(
          clipBehavior: Clip.none,
          children: [
            Container(
              width: 90,
              height: 90,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: color,
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: const Color(0xFFE0D1AE), width: 2),
                boxShadow: [
                  BoxShadow(
                    color: color.withValues(alpha: .18),
                    blurRadius: 8,
                    offset: const Offset(0, 5),
                  ),
                ],
              ),
              child: symbol == 'inventory'
                  ? const Icon(
                      Icons.backpack_rounded,
                      color: Colors.white,
                      size: 54,
                    )
                  : CustomPaint(
                      painter: _ResultIconPainter(
                        BoardArtwork.illustration(symbol),
                      ),
                    ),
            ),
            if (player)
              Positioned(
                right: -6,
                bottom: -6,
                child: CircleAvatar(
                  radius: 16,
                  backgroundColor: Color(session.currentPlayer.colorValue),
                  child: const Icon(
                    Icons.person,
                    color: Colors.white,
                    size: 24,
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(height: 10),
        Text(
          label,
          textAlign: TextAlign.center,
          style: const TextStyle(
            color: Color(0xFF254849),
            fontSize: 11,
            fontWeight: FontWeight.w800,
          ),
        ),
      ],
    );
  }
}

class _ResultIconPainter extends CustomPainter {
  _ResultIconPainter(this.scene);
  final VectorScene scene;
  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.scale(size.width / 100, size.height / 100);
    scene.paint(canvas);
    canvas.restore();
  }

  @override
  bool shouldRepaint(_ResultIconPainter oldDelegate) =>
      oldDelegate.scene != scene;
}
