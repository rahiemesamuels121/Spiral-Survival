import 'dart:async';
import 'package:flutter/material.dart';
import 'app/theme.dart';
import 'app/platform/lobby_music.dart';
import 'features/setup/main_menu_screen.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const SpiralApp());
}

class SpiralApp extends StatefulWidget {
  const SpiralApp({super.key});
  @override
  State<SpiralApp> createState() => _SpiralAppState();
}

class _SpiralAppState extends State<SpiralApp> with WidgetsBindingObserver {
  late final LobbyMusicController _music;
  late final LobbyMusicObserver _musicObserver;

  @override
  void initState() {
    super.initState();
    _music = LobbyMusicController();
    _musicObserver = LobbyMusicObserver(_music);
    WidgetsBinding.instance.addObserver(this);
    final state = WidgetsBinding.instance.lifecycleState;
    _music.setForeground(state == null || state == AppLifecycleState.resumed);
    unawaited(_music.initialize());
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _music.setForeground(state == AppLifecycleState.resumed);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _music.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'Spiral Survival',
    debugShowCheckedModeBanner: false,
    theme: AppTheme.dark,
    navigatorObservers: [_musicObserver],
    builder: (context, child) => LobbyMusicScope(
      controller: _music,
      child: child ?? const SizedBox.shrink(),
    ),
    home: const MainMenuScreen(),
  );
}
