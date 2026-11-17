import 'package:flutter/material.dart';
import '../../../app/theme.dart';
import '../application/game_controller.dart';
import '../domain/game_session.dart';
import '../domain/weapon.dart';

/// Keeps weapon choices visible and legible on the light turn card.
class WeaponActionOverlay extends StatelessWidget {
  const WeaponActionOverlay({required this.controller, super.key});

  final GameController controller;

  @override
  Widget build(BuildContext context) {
    final session = controller.session;
    final beforeMoving = session.phase == TurnPhase.preMoveWeaponChoice;
    final weapons = [
      for (final weapon in WeaponType.values)
        if (controller.weaponTargets(weapon).isNotEmpty) weapon,
    ];
    return ColoredBox(
      color: AppTheme.navy,
      child: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            key: const ValueKey('weapon-actions-scroll'),
            padding: const EdgeInsets.all(12),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 860),
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: AppTheme.ivory,
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(color: AppTheme.gold),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        'YOU ROLLED A ${session.lastDice}',
                        style: const TextStyle(
                          color: Color(0xFF725E3A),
                          fontWeight: FontWeight.w800,
                          fontSize: 12,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        beforeMoving ? 'MOVE OR ATTACK' : 'CHOOSE A TARGET',
                        style: const TextStyle(
                          color: AppTheme.ink,
                          fontSize: 22,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        beforeMoving
                            ? 'Use this roll to move OR attack. An attack replaces movement, uses one weapon and earns 3 stars with no cash.'
                            : 'Use one weapon on a target in range; earn 3 stars and no cash.',
                        style: const TextStyle(
                          color: AppTheme.ink,
                          fontSize: 13,
                        ),
                      ),
                      const SizedBox(height: 14),
                      LayoutBuilder(
                        builder: (context, bounds) {
                          final groups = [
                            for (final weapon in weapons)
                              _weaponGroup(
                                weapon,
                                sameTileOnly: session.lastDice != 6,
                              ),
                          ];
                          if (groups.isEmpty) {
                            return const Text(
                              'No targets are in range of your weapons.',
                              style: TextStyle(color: AppTheme.ink),
                            );
                          }
                          if (bounds.maxWidth >= 500 && groups.length == 2) {
                            return Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Expanded(child: groups[0]),
                                const SizedBox(width: 12),
                                Expanded(child: groups[1]),
                              ],
                            );
                          }
                          return Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              for (var i = 0; i < groups.length; i++) ...[
                                if (i > 0) const SizedBox(height: 16),
                                groups[i],
                              ],
                            ],
                          );
                        },
                      ),
                      const SizedBox(height: 16),
                      FilledButton.icon(
                        style: FilledButton.styleFrom(
                          backgroundColor: AppTheme.teal,
                          foregroundColor: AppTheme.ivory,
                          minimumSize: const Size.fromHeight(50),
                        ),
                        onPressed: beforeMoving
                            ? controller.chooseMovement
                            : controller.skipWeaponAction,
                        icon: Icon(
                          beforeMoving
                              ? Icons.directions_walk
                              : Icons.check_circle_outline,
                        ),
                        label: Text(
                          beforeMoving
                              ? 'MOVE ${session.lastDice} SPACES'
                              : 'END TURN',
                          textAlign: TextAlign.center,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _weaponGroup(
    WeaponType weapon, {
    required bool sameTileOnly,
  }) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    mainAxisSize: MainAxisSize.min,
    children: [
      Text(
        sameTileOnly
            ? '${weapon.label.toUpperCase()} · SAME TILE'
            : '${weapon.label.toUpperCase()} · WITHIN ${controller.weaponRange(weapon)} SPACES',
        style: const TextStyle(
          color: AppTheme.ink,
          fontSize: 13,
          fontWeight: FontWeight.w900,
        ),
      ),
      const SizedBox(height: 3),
      Text(
        'Owned ${controller.weaponCount(weapon)} · Range ${controller.weaponRange(weapon)}',
        style: const TextStyle(color: Color(0xFF475959), fontSize: 12),
      ),
      for (final targetIndex in controller.weaponTargets(weapon))
        Padding(
          padding: const EdgeInsets.only(top: 8),
          child: OutlinedButton.icon(
            style: OutlinedButton.styleFrom(
              foregroundColor: AppTheme.ink,
              backgroundColor: const Color(0xFFE9DFC9),
              side: const BorderSide(color: Color(0xFF9B8C6E)),
              minimumSize: const Size.fromHeight(50),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
            ),
            onPressed: () => controller.useWeapon(weapon, targetIndex),
            icon: Icon(
              weapon == WeaponType.stabber
                  ? Icons.hardware_outlined
                  : Icons.flash_on_outlined,
            ),
            label: Text(
              'Use ${weapon.label} on ${controller.session.players[targetIndex].name} '
              '(${(controller.session.players[targetIndex].position - controller.session.currentPlayer.position).abs()} spaces)',
              textAlign: TextAlign.center,
            ),
          ),
        ),
    ],
  );
}
