import 'package:flutter/material.dart';
import '../application/game_controller.dart';
import '../domain/game_session.dart';
import '../../../app/theme.dart';

/// Only mount inside the current player's private view.
class HitmanContractPanel extends StatefulWidget {
  const HitmanContractPanel({required this.controller, super.key});
  final GameController controller;

  @override
  State<HitmanContractPanel> createState() => _HitmanContractPanelState();
}

class _HitmanContractPanelState extends State<HitmanContractPanel> {
  late int _tile = widget.controller.session.currentPlayer.position;

  @override
  Widget build(BuildContext context) => Theme(
    data: ThemeData(
      useMaterial3: true,
      colorScheme: ColorScheme.fromSeed(seedColor: AppTheme.teal),
    ),
    child: DefaultTextStyle(
      style: const TextStyle(
        color: AppTheme.ink,
        fontSize: 14,
        height: 1.4,
        fontFamily: 'Roboto',
      ),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: AppTheme.ivory,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: AnimatedBuilder(
            animation: widget.controller,
            builder: (context, _) {
              final game = widget.controller;
              final session = game.session;
              final owner = session.hitmanOwnerId == session.currentPlayer.id;
              return Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    'One hitman · One anonymous contract · \$${game.hitmanHirePrice}',
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 12),
                  if (owner) ...[
                    Text(
                      'YOUR HITMAN · SPACE ${session.hitmanTile}',
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'Before rolling, choose one opponent within 20 spaces of the hitman. A kill returns them to START, releases the hitman and ends your turn without movement. No stars or cash are awarded.',
                    ),
                    if (session.phase != TurnPhase.ready)
                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: 12),
                        child: Text(
                          'This turn was used for movement. Keep your contract and choose a target before rolling on a later turn.',
                        ),
                      )
                    else if (game.hitmanTargets.isEmpty)
                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: 12),
                        child: Text(
                          'No opponents are in range. Your contract remains active.',
                        ),
                      ),
                    for (final index in game.hitmanTargets)
                      Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: FilledButton.icon(
                          icon: const Icon(Icons.gps_fixed),
                          label: Text(
                            'TARGET ${session.players[index].name} · SPACE ${session.players[index].position}',
                            textAlign: TextAlign.center,
                          ),
                          onPressed: () => game.useHitman(index),
                        ),
                      ),
                  ] else if (session.hitmanHired) ...[
                    const Text(
                      'The hitman is on another contract. Return after it is completed.',
                    ),
                  ] else ...[
                    const Text(
                      'Hire on the Secret Society tile. Secret Agents can also hire from up to 3 route spaces away, before rolling or after landing nearby. After moving, hire or keep a contract and then tap END TURN. Choose any space on the map for the hitman. Only you can see his position. On your turn, choose a target within 20 spaces. The contract lasts until one kill. A kill ends your turn; you cannot also move.',
                    ),
                    const SizedBox(height: 12),
                    DropdownButtonFormField<int>(
                      key: const ValueKey('hitman-placement'),
                      initialValue: _tile,
                      isExpanded: true,
                      decoration: const InputDecoration(
                        labelText: 'Place hitman on space',
                      ),
                      items: [
                        for (final tile in game.board.tiles)
                          DropdownMenuItem(
                            value: tile.index,
                            child: Text(
                              '${tile.index} · ${tile.label.isEmpty ? tile.typeLabel : tile.label}',
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                      ],
                      onChanged: game.canHireHitman
                          ? (value) => setState(() => _tile = value!)
                          : null,
                    ),
                    const SizedBox(height: 12),
                    FilledButton.icon(
                      key: const ValueKey('hire-hitman'),
                      icon: const Icon(Icons.visibility_off_outlined),
                      label: Text('HIRE HITMAN · \$${game.hitmanHirePrice}'),
                      onPressed: game.canHireHitman
                          ? () => game.hireHitman(_tile)
                          : null,
                    ),
                    if (session.currentPlayer.cash < game.hitmanHirePrice)
                      Text(
                        'You need \$${game.hitmanHirePrice - session.currentPlayer.cash} more.',
                      ),
                  ],
                ],
              );
            },
          ),
        ),
      ),
    ),
  );
}
