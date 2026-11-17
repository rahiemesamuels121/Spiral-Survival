import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// One lobby soundtrack shared across menu routes, never across a match.
class LobbyMusicController extends ChangeNotifier {
  static const channel = MethodChannel('spiral_survival/lobby_music');
  static const gameRoute = '/game';
  static const muteKey = 'spiral_survival_lobby_music_muted';
  final SharedPreferencesAsync _preferences = SharedPreferencesAsync();
  bool _ready = false, _muted = false, _visible = false, _disposed = false;
  bool _foreground = true;
  bool? _sent;
  Future<void> _tail = Future<void>.value();
  bool get ready => _ready;
  bool get muted => _muted;
  bool get lobbyVisible => _visible;
  Future<void> get settled => _tail;

  Future<void> initialize() async {
    try {
      _muted = await _preferences.getBool(muteKey) ?? false;
    } catch (error) {
      debugPrint('Could not load music preference: $error');
    }
    if (_disposed) return;
    _ready = true;
    notifyListeners();
    _sync();
  }

  void setLobbyVisible(bool visible) {
    if (_visible == visible) return;
    _visible = visible;
    // Initial route notifications can arrive during Navigator's build.
    scheduleMicrotask(() {
      if (!_disposed) notifyListeners();
    });
    _sync();
  }

  void setForeground(bool foreground) {
    _foreground = foreground;
    _sync();
  }

  Future<void> toggleMuted() async {
    _muted = !_muted;
    notifyListeners();
    _sync();
    try {
      await _preferences.setBool(muteKey, _muted);
    } catch (error) {
      debugPrint('Could not save music preference: $error');
    }
  }

  void _sync() {
    // Recheck the latest state when queued work runs, so a quick transition
    // cannot start stale lobby playback after entering a game.
    _tail = _tail.then((_) async {
      final active = !_disposed && _ready && _visible && _foreground && !_muted;
      if (active == _sent) return;
      if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
        try {
          await channel.invokeMethod<void>('setActive', active);
        } on MissingPluginException {
          // Non-Android previews and widget tests have no native audio host.
        } on PlatformException catch (error) {
          debugPrint(
            'Could not update lobby music: ${error.code}: ${error.message}',
          );
          return;
        }
      }
      _sent = active;
    });
  }

  @override
  void dispose() {
    _disposed = true;
    _sync();
    super.dispose();
  }
}

class LobbyMusicObserver extends NavigatorObserver {
  LobbyMusicObserver(this.music);
  final LobbyMusicController music;
  final List<Route<dynamic>> _routes = [];
  void _sync() => music.setLobbyVisible(
    _routes.isNotEmpty &&
        !_routes.any((r) => r.settings.name == LobbyMusicController.gameRoute),
  );
  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    _routes.add(route);
    _sync();
  }

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) {
    _routes.remove(route);
    _sync();
  }

  @override
  void didRemove(Route<dynamic> route, Route<dynamic>? previousRoute) {
    _routes.remove(route);
    _sync();
  }

  @override
  void didReplace({Route<dynamic>? newRoute, Route<dynamic>? oldRoute}) {
    final index = oldRoute == null ? -1 : _routes.indexOf(oldRoute);
    if (index >= 0) {
      if (newRoute == null) {
        _routes.removeAt(index);
      } else {
        _routes[index] = newRoute;
      }
    } else if (newRoute != null) {
      _routes.add(newRoute);
    }
    _sync();
  }
}

class LobbyMusicScope extends InheritedNotifier<LobbyMusicController> {
  const LobbyMusicScope({
    required LobbyMusicController controller,
    required super.child,
    super.key,
  }) : super(notifier: controller);
  static LobbyMusicController? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<LobbyMusicScope>()?.notifier;
}

class LobbyMusicButton extends StatelessWidget {
  const LobbyMusicButton({super.key});
  @override
  Widget build(BuildContext context) {
    final music = LobbyMusicScope.maybeOf(context);
    if (music == null) return const SizedBox.shrink();
    return IconButton(
      tooltip: music.muted ? 'Unmute lobby music' : 'Mute lobby music',
      onPressed: music.ready ? () => unawaited(music.toggleMuted()) : null,
      icon: Icon(
        music.muted ? Icons.volume_off : Icons.volume_up,
        color: Theme.of(context).colorScheme.primary,
      ),
    );
  }
}
