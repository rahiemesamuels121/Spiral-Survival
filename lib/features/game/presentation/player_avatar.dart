import 'package:flutter/material.dart';
import '../domain/player_icon.dart';

extension PlayerIconAppearance on PlayerIcon {
  String get label => switch (this) {
    PlayerIcon.number => 'Number',
    PlayerIcon.star => 'Star',
    PlayerIcon.rocket => 'Rocket',
    PlayerIcon.shield => 'Shield',
    PlayerIcon.paw => 'Cat Whisperer',
    PlayerIcon.secretAgent => 'Secret Agent',
    PlayerIcon.swimmer => 'Swimmer',
    PlayerIcon.bolt => 'Lightning',
    PlayerIcon.diamond => 'Diamond',
    PlayerIcon.flag => 'Flag',
  };

  String get ability => switch (this) {
    PlayerIcon.paw =>
      'Pass lions without raw meat or injury. Your supplies are not consumed.',
    PlayerIcon.secretAgent =>
      'Access Secret Society from up to 3 route spaces away, before rolling or after landing nearby. Weapons reach 3 extra spaces: Stabber 8, Pew pew 13. Get \$50 off every Secret Society purchase, including the hitman (\$150).',
    PlayerIcon.swimmer =>
      'Survive water and surf without a boat. Swim to the first space after the water.',
    _ =>
      'Legacy cosmetic avatar. Choose a character in a new game to gain an ability.',
  };

  IconData get symbol => switch (this) {
    PlayerIcon.number => Icons.tag,
    PlayerIcon.star => Icons.star,
    PlayerIcon.rocket => Icons.rocket_launch,
    PlayerIcon.shield => Icons.shield,
    PlayerIcon.paw => Icons.pets,
    PlayerIcon.secretAgent => Icons.badge_outlined,
    PlayerIcon.swimmer => Icons.pool,
    PlayerIcon.bolt => Icons.bolt,
    PlayerIcon.diamond => Icons.diamond,
    PlayerIcon.flag => Icons.flag,
  };
}

class PlayerAvatar extends StatelessWidget {
  const PlayerAvatar({
    required this.icon,
    required this.color,
    required this.number,
    this.radius = 20,
    super.key,
  });
  final PlayerIcon icon;
  final Color color;
  final int number;
  final double radius;

  @override
  Widget build(BuildContext context) => CircleAvatar(
    radius: radius,
    backgroundColor: color,
    child: icon == PlayerIcon.number
        ? Text(
            '$number',
            style: TextStyle(
              color: const Color(0xFF101E29),
              fontSize: radius,
              fontWeight: FontWeight.w900,
            ),
          )
        : Icon(icon.symbol, size: radius * 1.3, color: const Color(0xFF101E29)),
  );
}

Future<PlayerIcon?> pickPlayerIcon(
  BuildContext context, {
  required PlayerIcon selected,
  required Color color,
  required int number,
}) => showDialog<PlayerIcon>(
  context: context,
  builder: (context) => AlertDialog(
    title: const Text('Choose your character'),
    content: SizedBox(
      width: 360,
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'Choose before the match starts. Your character and ability are locked for the entire game.',
            ),
            const SizedBox(height: 12),
            for (final icon in PlayerIcon.selectable)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: OutlinedButton(
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.all(12),
                    side: BorderSide(
                      color: icon == selected ? color : Colors.grey,
                      width: icon == selected ? 3 : 1,
                    ),
                  ),
                  onPressed: () => Navigator.pop(context, icon),
                  child: Row(
                    children: [
                      PlayerAvatar(icon: icon, color: color, number: number),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              icon.label,
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(icon.ability),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('CANCEL'),
      ),
    ],
  ),
);
