import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../app/theme.dart';
import '../../../app/platform/lobby_music.dart';
import '../../game/data/board_repository.dart';
import '../../game/presentation/game_screen.dart';
import '../../game/presentation/player_avatar.dart';
import '../../game/domain/player_icon.dart';
import '../application/online_game_controller.dart';
import '../data/room_service.dart';

class OnlineRoomScreen extends StatefulWidget {
  const OnlineRoomScreen({super.key});
  @override
  State<OnlineRoomScreen> createState() => _OnlineRoomScreenState();
}

class _OnlineRoomScreenState extends State<OnlineRoomScreen> {
  RoomService? _service;
  final _name = TextEditingController();
  final _code = TextEditingController();
  bool _busy = false, _inGame = false, _opened = false;
  String? _error;
  PlayerIcon _avatar = PlayerIcon.paw;
  Timer? _refresh;

  @override
  void initState() {
    super.initState();
    _refresh = Timer.periodic(const Duration(seconds: 15), (_) {
      if (mounted) setState(() {});
    });
  }

  Future<RoomService> _connection() async {
    if (_service != null) return _service!;
    // Everyone uses the shipped board, never a device's old custom layout.
    final board = await const BoardRepository().loadOnlineBoard();
    final service = RoomService(board);
    service.addListener(_changed);
    _service = service;
    return service;
  }

  void _changed() {
    if (!mounted) return;
    setState(() {
      if (_service?.connected ?? false) _error = null;
    });
    if (_service?.room?.status == 'playing' && !_opened && !_inGame) {
      _opened = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) unawaited(_play());
      });
    }
  }

  Future<void> _run(Future<void> Function(RoomService) action) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await action(await _connection());
    } catch (e) {
      if (mounted) {
        setState(
          () => _error = e is StateError
              ? e.message.toString()
              : 'Could not connect. Check your internet, then try again.',
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _chooseAvatar() async {
    if (_busy ||
        (_service?.room != null && _service!.room!.status != 'waiting')) {
      return;
    }
    final icon = await pickPlayerIcon(
      context,
      selected: _service?.room?.avatarFor(_service!.uid ?? '') ?? _avatar,
      color: AppTheme.gold,
      number: 1,
    );
    if (!mounted || icon == null) return;
    if (_service?.room != null) {
      await _run((service) => service.chooseAvatar(icon));
    } else {
      setState(() => _avatar = icon);
    }
  }

  Widget _avatarChoice(PlayerIcon icon) => OutlinedButton(
    onPressed: _busy ? null : _chooseAvatar,
    child: Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Row(
        children: [
          PlayerAvatar(icon: icon, color: AppTheme.gold, number: 1),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  icon.label,
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
                Text(icon.ability),
                const Text('CHOOSE CHARACTER · Locks when the host starts'),
              ],
            ),
          ),
        ],
      ),
    ),
  );

  Future<void> _play() async {
    if (_inGame || !mounted || _service?.room?.state.isEmpty != false) return;
    _inGame = true;
    final controller = OnlineGameController(connection: _service!);
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        settings: const RouteSettings(name: LobbyMusicController.gameRoute),
        builder: (_) => GameScreen(
          controller: controller,
          online: true,
          canInteract: () => controller.canAct,
          onlineStatus: () =>
              '${_service!.room!.code}  ·  ${controller.status}',
        ),
      ),
    );
    controller.dispose();
    _inGame = false;
    if (mounted) setState(() {});
  }

  Future<void> _leave() async {
    final service = _service;
    if (service == null) {
      Navigator.pop(context);
      return;
    }
    if (service.isHost && service.room?.status != 'closed') {
      final close = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Close this room?'),
          content: const Text(
            'You are the host. Closing the room ends this match for everyone.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('KEEP PLAYING'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('CLOSE ROOM'),
            ),
          ],
        ),
      );
      if (close != true) return;
    }
    await _run((s) => s.leave().timeout(const Duration(seconds: 5)));
    // A disconnected or remotely closed room must never trap the player.
    if (mounted) Navigator.pop(context);
  }

  @override
  void dispose() {
    _refresh?.cancel();
    _service?.removeListener(_changed);
    _service?.dispose();
    _name.dispose();
    _code.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final room = _service?.room;
    return PopScope(
      canPop: room == null,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) unawaited(_leave());
      },
      child: Scaffold(
        appBar: AppBar(
          title: const Text('ONLINE ROOM'),
          actions: const [LobbyMusicButton()],
          leading: IconButton(
            icon: const Icon(Icons.arrow_back),
            onPressed: _busy ? null : _leave,
          ),
        ),
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
                      Center(
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(20),
                          child: Image.asset(
                            'assets/branding/spiral_survival.png',
                            width: 120,
                            height: 120,
                            semanticLabel: 'Spiral Survival',
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),
                      Text(
                        room == null
                            ? 'Play together, wherever you are.'
                            : 'Room ${room.code}',
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          color: AppTheme.gold,
                          fontSize: 26,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 12),
                      const Text(
                        '2–5 players · Private room code',
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 24),
                      if (room == null) ...[
                        _avatarChoice(_avatar),
                        const SizedBox(height: 12),
                        TextField(
                          controller: _name,
                          maxLength: 16,
                          textCapitalization: TextCapitalization.words,
                          decoration: const InputDecoration(
                            labelText: 'Your name',
                          ),
                        ),
                        const SizedBox(height: 12),
                        FilledButton.icon(
                          onPressed: _busy
                              ? null
                              : () => _run(
                                  (s) => s.create(_name.text, avatar: _avatar),
                                ),
                          icon: const Icon(Icons.add),
                          label: const Text('CREATE ROOM'),
                        ),
                        const Padding(
                          padding: EdgeInsets.symmetric(vertical: 20),
                          child: Text(
                            'or join your friends',
                            textAlign: TextAlign.center,
                          ),
                        ),
                        TextField(
                          controller: _code,
                          maxLength: 8,
                          textCapitalization: TextCapitalization.characters,
                          decoration: const InputDecoration(
                            labelText: '8-character room code',
                          ),
                        ),
                        OutlinedButton.icon(
                          onPressed: _busy
                              ? null
                              : () => _run(
                                  (s) => s.join(
                                    _code.text,
                                    _name.text,
                                    avatar: _avatar,
                                  ),
                                ),
                          icon: const Icon(Icons.login),
                          label: const Text('JOIN ROOM'),
                        ),
                        const SizedBox(height: 12),
                        TextButton(
                          onPressed: _busy
                              ? null
                              : () => _run((s) async {
                                  if (!await s.resume()) {
                                    throw StateError(
                                      'No active room to reconnect to.',
                                    );
                                  }
                                }),
                          child: const Text('RECONNECT TO MY ROOM'),
                        ),
                      ] else ...[
                        OutlinedButton.icon(
                          onPressed: () {
                            Clipboard.setData(ClipboardData(text: room.code));
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text('Room code copied')),
                            );
                          },
                          icon: const Icon(Icons.copy),
                          label: const Text('COPY ROOM CODE'),
                        ),
                        const SizedBox(height: 16),
                        Text(
                          '${room.members.length} / 5 players',
                          textAlign: TextAlign.center,
                          style: const TextStyle(color: AppTheme.muted),
                        ),
                        const SizedBox(height: 12),
                        if (room.status == 'waiting') ...[
                          _avatarChoice(room.avatarFor(_service!.uid ?? '')),
                          const SizedBox(height: 12),
                        ],
                        for (var i = 0; i < room.playerOrder.length; i++)
                          ListTile(
                            leading: PlayerAvatar(
                              icon: room.avatarFor(room.playerOrder[i]),
                              color: AppTheme.playerColors[i],
                              number: i + 1,
                            ),
                            title: Text(room.members[room.playerOrder[i]]!),
                            subtitle: Text(
                              room.avatarFor(room.playerOrder[i]).label,
                            ),
                            trailing: room.playerOrder[i] == room.hostId
                                ? const Text(
                                    'HOST',
                                    style: TextStyle(color: AppTheme.gold),
                                  )
                                : null,
                          ),
                        const SizedBox(height: 16),
                        if (room.status == 'closed')
                          const Text(
                            'This room has closed.',
                            textAlign: TextAlign.center,
                          )
                        else if (room.status == 'playing')
                          FilledButton.icon(
                            onPressed: _play,
                            icon: const Icon(Icons.play_arrow),
                            label: const Text('RETURN TO GAME'),
                          )
                        else if (_service!.isHost)
                          FilledButton.icon(
                            onPressed:
                                !_busy &&
                                    _service!.connected &&
                                    room.members.length >= 2
                                ? () => _run((s) => s.start())
                                : null,
                            icon: const Icon(Icons.casino),
                            label: Text(
                              room.members.length < 2
                                  ? 'WAITING FOR PLAYERS'
                                  : 'START GAME',
                            ),
                          )
                        else
                          Text(
                            room.hostAvailable
                                ? 'Waiting for the host to start…'
                                : 'Waiting for the host to reconnect…',
                            textAlign: TextAlign.center,
                          ),
                        const SizedBox(height: 16),
                        const Text(
                          'The host must keep the game open. Reconnect with this device to keep your seat.',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: AppTheme.muted),
                        ),
                        TextButton(
                          onPressed: _busy ? null : _leave,
                          child: Text(
                            _service!.isHost ? 'CLOSE ROOM' : 'LEAVE ROOM',
                          ),
                        ),
                      ],
                      if (_busy)
                        const Padding(
                          padding: EdgeInsets.all(16),
                          child: Center(child: CircularProgressIndicator()),
                        ),
                      if (_error != null || _service?.error != null)
                        Padding(
                          padding: const EdgeInsets.only(top: 16),
                          child: Text(
                            _error ?? _service!.error!,
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: Theme.of(context).colorScheme.error,
                            ),
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
}
