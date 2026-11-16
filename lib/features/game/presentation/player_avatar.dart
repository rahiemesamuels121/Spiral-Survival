import 'package:flutter/material.dart';
import '../domain/player_icon.dart';

extension PlayerIconAppearance on PlayerIcon {
  String get label => switch (this) {
    PlayerIcon.number => 'Number',
    PlayerIcon.star => 'Star',
    PlayerIcon.rocket => 'Rocket',
    PlayerIcon.shield => 'Shield',
    PlayerIcon.paw => 'Paw',
    PlayerIcon.bolt => 'Lightning',
    PlayerIcon.diamond => 'Diamond',
    PlayerIcon.flag => 'Flag',
  };

  IconData get symbol => switch (this) {
    PlayerIcon.number => Icons.tag,
    PlayerIcon.star => Icons.star,
    PlayerIcon.rocket => Icons.rocket_launch,
    PlayerIcon.shield => Icons.shield,
    PlayerIcon.paw => Icons.pets,
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
    title: const Text('Choose player icon'),
    content: SizedBox(
      width: 360,
      child: SingleChildScrollView(
        child: Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            for (final icon in PlayerIcon.values)
              SizedBox(
                width: 96,
                child: OutlinedButton(
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.all(10),
                    side: BorderSide(
                      color: icon == selected ? color : Colors.grey,
                      width: icon == selected ? 3 : 1,
                    ),
                  ),
                  onPressed: () => Navigator.pop(context, icon),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      PlayerAvatar(icon: icon, color: color, number: number),
                      const SizedBox(height: 6),
                      Text(icon.label),
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
