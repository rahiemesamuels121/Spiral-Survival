import 'package:flutter/material.dart';
import '../../app/theme.dart';
import '../game/application/game_controller.dart';
import '../game/data/session_store.dart';
import '../game/data/board_repository.dart';
import '../game/domain/board_definition.dart';
import '../game/domain/game_session.dart';
import '../game/presentation/game_screen.dart';

class GameSetupScreen extends StatefulWidget {
  const GameSetupScreen({super.key});

  @override
  State<GameSetupScreen> createState() => _GameSetupScreenState();
}

class _GameSetupScreenState extends State<GameSetupScreen> {
  final _formKey = GlobalKey<FormState>();
  final _store = SessionStore();
  late final List<TextEditingController> _names;
  int _count = 3; // Requested default: Player 1, Player 2, Player 3.
  GameSession? _saved;
  late final Future<BoardDefinition> _boardFuture;

  @override
  void initState() {
    super.initState();
    _names = List.generate(
      5,
      (i) => TextEditingController(text: 'Player ${i + 1}'),
    );
    _boardFuture = const BoardRepository().loadBoard();
    _refreshSave();
  }

  Future<void> _refreshSave() async {
    final saved = await _store.load();
    if (mounted) setState(() => _saved = saved);
  }

  @override
  void dispose() {
    for (final controller in _names) {
      controller.dispose();
    }
    super.dispose();
  }

  Future<void> _openGame(GameSession session) async {
    try {
      final board = await _boardFuture;
      if (!mounted) return;
      if (session.boardId != board.id) {
        _showError(
          'This save was created with another board map. Start a new game.',
        );
        return;
      }
      final controller = GameController(session: session, board: board);
      await Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => GameScreen(controller: controller),
        ),
      );
      controller.dispose();
      if (mounted) await _refreshSave();
    } catch (error) {
      if (mounted) _showError('Could not load the board: $error');
    }
  }

  void _showError(String message) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _startGame() async {
    if (!_formKey.currentState!.validate()) return;
    final names = _names.take(_count).map((e) => e.text.trim()).toList();
    if (names.map((e) => e.toLowerCase()).toSet().length != _count) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please give each player a unique name.')),
      );
      return;
    }
    try {
      final board = await _boardFuture;
      final controller = GameController.newGame(
        names: names,
        colors: AppTheme.playerColors.map((c) => c.toARGB32()).toList(),
        board: board,
      );
      await _store.clear();
      if (!mounted) return;
      await _openGame(controller.session);
      controller.dispose();
    } catch (error) {
      if (mounted) _showError('Could not start the game: $error');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [Color(0xFF101E29), Color(0xFF243E47), Color(0xFF101E29)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
        child: SafeArea(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 750),
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(24),
                child: Form(
                  key: _formKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const Text(
                        'SPIRAL QUEST',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 38,
                          fontWeight: FontWeight.w900,
                          letterSpacing: 4,
                          color: AppTheme.gold,
                        ),
                      ),
                      const SizedBox(height: 5),
                      const Text(
                        'LOCAL PASS & PLAY • 2–5 PLAYERS',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: AppTheme.muted,
                          letterSpacing: 2,
                        ),
                      ),
                      const SizedBox(height: 22),
                      Container(
                        padding: const EdgeInsets.all(24),
                        decoration: BoxDecoration(
                          color: AppTheme.panel,
                          border: Border.all(
                            color: AppTheme.gold.withValues(alpha: 0.30),
                          ),
                          borderRadius: BorderRadius.circular(24),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'NEW GAME',
                              style: TextStyle(
                                color: AppTheme.gold,
                                fontSize: 20,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const SizedBox(height: 12),
                            const Text('Number of players'),
                            const SizedBox(height: 8),
                            Wrap(
                              spacing: 8,
                              children: [
                                for (var n = 2; n <= 5; n++)
                                  ChoiceChip(
                                    label: Text(
                                      '$n',
                                      style: TextStyle(
                                        color: _count == n
                                            ? AppTheme.navy
                                            : AppTheme.text,
                                      ),
                                    ),
                                    selected: _count == n,
                                    onSelected: (_) =>
                                        setState(() => _count = n),
                                  ),
                              ],
                            ),
                            const SizedBox(height: 18),
                            for (var i = 0; i < _count; i++) ...[
                              Row(
                                children: [
                                  CircleAvatar(
                                    backgroundColor: AppTheme.playerColors[i],
                                    child: Text(
                                      '${i + 1}',
                                      style: const TextStyle(
                                        color: AppTheme.navy,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: TextFormField(
                                      controller: _names[i],
                                      maxLength: 16,
                                      decoration: InputDecoration(
                                        labelText: 'Player ${i + 1} name',
                                        counterText: '',
                                        isDense: true,
                                      ),
                                      validator: (value) =>
                                          value == null || value.trim().isEmpty
                                          ? 'Enter a player name'
                                          : null,
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 12),
                            ],
                            const Row(
                              children: [
                                Icon(Icons.group, color: AppTheme.gold),
                                SizedBox(width: 9),
                                Expanded(
                                  child: Text(
                                    'Local multiplayer • One Android device',
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 18),
                            SizedBox(
                              width: double.infinity,
                              child: FilledButton.icon(
                                onPressed: _startGame,
                                icon: const Icon(Icons.casino),
                                label: const Text('START GAME'),
                              ),
                            ),
                            if (_saved != null) ...[
                              const SizedBox(height: 10),
                              SizedBox(
                                width: double.infinity,
                                child: OutlinedButton.icon(
                                  onPressed: () => _openGame(_saved!),
                                  icon: const Icon(Icons.play_circle_outline),
                                  label: const Text('CONTINUE SAVED GAME'),
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                      const SizedBox(height: 14),
                      const Text(
                        '120 spaces. One spiral. Reach the finish to win.',
                        textAlign: TextAlign.center,
                        style: TextStyle(fontSize: 12, color: Colors.white60),
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
}
