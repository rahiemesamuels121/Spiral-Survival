import 'package:flutter/material.dart';
import '../../app/theme.dart';
import '../../app/platform/lobby_music.dart';
import '../game/application/game_controller.dart';
import '../game/data/board_repository.dart';
import '../game/data/session_store.dart';
import '../game/domain/board_definition.dart';
import '../game/domain/game_session.dart';
import '../game/presentation/game_screen.dart';
import '../help/help_screen.dart';
import '../multiplayer/presentation/online_room_screen.dart';
import 'setup_screen.dart';

class MainMenuScreen extends StatefulWidget {
  const MainMenuScreen({super.key});
  @override
  State<MainMenuScreen> createState() => _MainMenuScreenState();
}

class _MainMenuScreenState extends State<MainMenuScreen> {
  GameSession? _saved;
  bool _resuming = false;

  @override
  void initState() {
    super.initState();
    _refreshSave();
  }

  Future<void> _refreshSave() async {
    final saved = await SessionStore().load();
    if (mounted) setState(() => _saved = saved);
  }

  Future<void> _open(Widget screen) async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        settings: RouteSettings(
          name: screen is GameScreen ? LobbyMusicController.gameRoute : null,
        ),
        builder: (_) => screen,
      ),
    );
    if (mounted) await _refreshSave();
  }

  Future<void> _resume() async {
    if (_resuming || _saved == null) return;
    setState(() => _resuming = true);
    GameController? controller;
    try {
      final board = await const BoardRepository().loadBoard();
      controller = GameController(session: _saved!, board: board);
      if (!mounted) return;
      final game = controller;
      await _open(
        GameScreen(
          controller: game,
          canInteract: game.session.isComputerGame
              ? () => !game.session.isComputerTurn
              : null,
        ),
      );
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not resume the game: $error')),
        );
      }
    } finally {
      controller?.dispose();
      if (mounted) setState(() => _resuming = false);
    }
  }

  Future<void> _help() async {
    BoardDefinition? board;
    try {
      board = await const BoardRepository().loadBoard();
    } catch (_) {
      /* Rules stay readable without a board. */
    }
    if (mounted) await _open(HelpScreen(board: board));
  }

  Widget _mode({
    required String title,
    required String description,
    required IconData icon,
    required VoidCallback onTap,
  }) => Card(
    color: AppTheme.panel,
    margin: const EdgeInsets.only(bottom: 14),
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(20),
      side: BorderSide(color: AppTheme.gold.withValues(alpha: .3)),
    ),
    child: InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Row(
          children: [
            Icon(icon, color: AppTheme.gold, size: 32),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      color: AppTheme.gold,
                      fontWeight: FontWeight.w800,
                      fontSize: 20,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(description),
                ],
              ),
            ),
            const SizedBox(width: 8),
            const Icon(Icons.chevron_right, color: AppTheme.gold),
          ],
        ),
      ),
    ),
  );

  @override
  Widget build(BuildContext context) => Scaffold(
    body: Container(
      decoration: const BoxDecoration(gradient: AppTheme.menuGradient),
      child: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 620),
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const SizedBox(width: 48),
                      Expanded(
                        child: Center(
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(28),
                            child: Image.asset(
                              'assets/branding/spiral_survival.png',
                              width: 170,
                              height: 170,
                              semanticLabel: 'Spiral Survival game artwork',
                            ),
                          ),
                        ),
                      ),
                      const LobbyMusicButton(),
                    ],
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    'SPIRAL SURVIVAL',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: AppTheme.gold,
                      fontSize: 28,
                      letterSpacing: 2,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Choose how you want to play',
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 28),
                  _mode(
                    title: 'PASS & PLAY',
                    description:
                        '2–5 players on one device. Choose players and avatars next.',
                    icon: Icons.group,
                    onTap: () => _open(const GameSetupScreen()),
                  ),
                  _mode(
                    title: 'VS COMPUTER',
                    description:
                        'Play offline against 1–4 computers. Choose your avatar next.',
                    icon: Icons.smart_toy_outlined,
                    onTap: () => _open(const GameSetupScreen(vsComputer: true)),
                  ),
                  _mode(
                    title: 'ONLINE',
                    description:
                        'Create or join a private room, then choose your character in the lobby.',
                    icon: Icons.public,
                    onTap: () => _open(const OnlineRoomScreen()),
                  ),
                  if (_saved != null) ...[
                    OutlinedButton.icon(
                      onPressed: _resuming ? null : _resume,
                      icon: const Icon(Icons.play_circle_outline),
                      label: const Text('CONTINUE SAVED GAME'),
                    ),
                    const SizedBox(height: 10),
                  ],
                  TextButton.icon(
                    onPressed: _help,
                    icon: const Icon(Icons.help_outline),
                    label: const Text('HOW TO PLAY & TILE GUIDE'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    ),
  );
}
