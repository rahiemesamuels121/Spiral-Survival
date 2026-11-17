import 'package:flutter/material.dart';
import '../../app/theme.dart';
import '../../app/platform/lobby_music.dart';
import '../game/application/game_controller.dart';
import '../game/data/session_store.dart';
import '../game/data/board_repository.dart';
import '../game/domain/board_definition.dart';
import '../game/domain/game_session.dart';
import '../game/presentation/game_screen.dart';
import '../game/presentation/player_avatar.dart';
import '../game/domain/player_icon.dart';
import '../help/help_screen.dart';

class GameSetupScreen extends StatefulWidget {
  const GameSetupScreen({this.vsComputer = false, super.key});
  final bool vsComputer;

  @override
  State<GameSetupScreen> createState() => _GameSetupScreenState();
}

class _GameSetupScreenState extends State<GameSetupScreen> {
  final _formKey = GlobalKey<FormState>();
  final _store = SessionStore();
  late final List<TextEditingController> _names;
  final _icons = List.filled(5, PlayerIcon.paw);
  bool get _vsComputer => widget.vsComputer;
  int _count = 3; // Requested default: Player 1, Player 2, Player 3.
  late final Future<BoardDefinition> _boardFuture;

  @override
  void initState() {
    super.initState();
    _names = List.generate(
      5,
      (i) => TextEditingController(text: 'Player ${i + 1}'),
    );
    _count = _vsComputer ? 2 : 3;
    _boardFuture = const BoardRepository().loadBoard();
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
          settings: const RouteSettings(name: LobbyMusicController.gameRoute),
          builder: (_) => GameScreen(
            controller: controller,
            canInteract: session.isComputerGame
                ? () => !controller.session.isComputerTurn
                : null,
          ),
        ),
      );
      controller.dispose();
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
    final names = _names
        .take(_vsComputer ? 1 : _count)
        .map((e) => e.text.trim())
        .toList();
    if (_vsComputer) {
      for (var i = 1; i < _count; i++) {
        var number = i;
        var name = 'Computer $number';
        while (names.any(
          (value) => value.toLowerCase() == name.toLowerCase(),
        )) {
          name = 'Computer ${++number}';
        }
        names.add(name);
      }
    }
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
        icons: [
          for (var i = 0; i < _count; i++)
            _vsComputer && i > 0
                ? PlayerIcon.selectable[(i - 1) % PlayerIcon.selectable.length]
                : _icons[i],
        ],
        computerPlayerIds: {
          if (_vsComputer)
            for (var i = 1; i < _count; i++) 'p${i + 1}',
        },
      );
      await _store.clear();
      if (!mounted) return;
      await _openGame(controller.session);
      controller.dispose();
    } catch (error) {
      if (mounted) _showError('Could not start the game: $error');
    }
  }

  Future<void> _chooseCharacter(int index) async {
    final icon = await pickPlayerIcon(
      context,
      selected: _icons[index],
      color: AppTheme.playerColors[index],
      number: index + 1,
    );
    if (icon != null && mounted) setState(() => _icons[index] = icon);
  }

  Future<void> _showHelp() async {
    BoardDefinition? board;
    try {
      board = await _boardFuture;
    } catch (_) {
      // Rules remain available even if a custom board cannot be loaded.
    }
    if (!mounted) return;
    await Navigator.of(
      context,
    ).push(MaterialPageRoute<void>(builder: (_) => HelpScreen(board: board)));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_vsComputer ? 'VS COMPUTER SETUP' : 'PASS & PLAY SETUP'),
        actions: [
          const LobbyMusicButton(),
          IconButton(
            tooltip: 'How to play',
            onPressed: _showHelp,
            icon: const Icon(Icons.help_outline),
          ),
        ],
      ),
      body: Container(
        decoration: const BoxDecoration(gradient: AppTheme.menuGradient),
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
                      Text(
                        _vsComputer
                            ? 'YOUR OPPONENTS & AVATAR'
                            : 'PLAYERS & AVATARS',
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          fontSize: 28,
                          fontWeight: FontWeight.w900,
                          letterSpacing: 4,
                          color: AppTheme.gold,
                        ),
                      ),
                      const SizedBox(height: 5),
                      Text(
                        _vsComputer
                            ? 'Choose your opponents, name and character.'
                            : 'Choose the player count, names and characters.',
                        textAlign: TextAlign.center,
                        style: const TextStyle(
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
                            Text(
                              _vsComputer
                                  ? 'Number of computer opponents'
                                  : 'Number of players',
                            ),
                            const SizedBox(height: 8),
                            Wrap(
                              spacing: 8,
                              children: [
                                for (
                                  var n = (_vsComputer ? 1 : 2);
                                  n <= (_vsComputer ? 4 : 5);
                                  n++
                                )
                                  ChoiceChip(
                                    label: Text(
                                      '$n',
                                      style: TextStyle(
                                        color:
                                            _count == (_vsComputer ? n + 1 : n)
                                            ? AppTheme.navy
                                            : AppTheme.text,
                                      ),
                                    ),
                                    selected:
                                        _count == (_vsComputer ? n + 1 : n),
                                    onSelected: (_) => setState(
                                      () => _count = _vsComputer ? n + 1 : n,
                                    ),
                                  ),
                              ],
                            ),
                            const SizedBox(height: 18),
                            for (
                              var i = 0;
                              i < (_vsComputer ? 1 : _count);
                              i++
                            ) ...[
                              Row(
                                children: [
                                  Tooltip(
                                    message: 'Change Player ${i + 1} icon',
                                    child: InkWell(
                                      onTap: () => _chooseCharacter(i),
                                      child: PlayerAvatar(
                                        icon: _icons[i],
                                        color: AppTheme.playerColors[i],
                                        number: i + 1,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: TextFormField(
                                      controller: _names[i],
                                      maxLength: 16,
                                      decoration: InputDecoration(
                                        labelText: _vsComputer
                                            ? 'Your name'
                                            : 'Player ${i + 1} name',
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
                              TextButton.icon(
                                onPressed: () => _chooseCharacter(i),
                                icon: const Icon(Icons.badge_outlined),
                                label: Text(
                                  '${_icons[i].label} · CHOOSE AVATAR',
                                ),
                              ),
                              const SizedBox(height: 12),
                            ],
                            Row(
                              children: [
                                Icon(
                                  _vsComputer
                                      ? Icons.smart_toy_outlined
                                      : Icons.group,
                                  color: AppTheme.gold,
                                ),
                                const SizedBox(width: 9),
                                Expanded(
                                  child: Text(
                                    _vsComputer
                                        ? 'You vs ${_count - 1} computer opponent${_count == 2 ? '' : 's'} • Offline'
                                        : 'Local multiplayer • One Android device',
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
                                label: Text(
                                  _vsComputer
                                      ? 'START VS COMPUTER'
                                      : 'START GAME',
                                ),
                              ),
                            ),
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
