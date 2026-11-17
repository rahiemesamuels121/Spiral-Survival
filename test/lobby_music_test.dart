import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:spiral_pass_play/app/platform/lobby_music.dart';
import 'package:spiral_pass_play/main.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final calls = <bool>[];
  setUp(() {
    calls.clear();
    SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.empty();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(LobbyMusicController.channel, (call) async {
          expectSync(call.method, 'setActive');
          calls.add(call.arguments as bool);
          return null;
        });
  });
  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(LobbyMusicController.channel, null);
  });

  test('Mute persists; backgrounding and gameplay silence the track', () async {
    final music = LobbyMusicController();
    music.setLobbyVisible(true);
    await music.initialize();
    await music.settled;
    expect(calls.last, isTrue);
    music.setForeground(false);
    await music.settled;
    expect(calls.last, isFalse);
    music.setForeground(true);
    await music.settled;
    expect(calls.last, isTrue);
    await music.toggleMuted();
    await music.settled;
    expect(calls.last, isFalse);
    expect(
      await SharedPreferencesAsync().getBool(LobbyMusicController.muteKey),
      isTrue,
    );
    music.setLobbyVisible(false);
    await music.settled;
    await music.toggleMuted();
    await music.settled;
    expect(calls.last, isFalse);
    music.setLobbyVisible(true);
    await music.settled;
    expect(calls.last, isTrue);
    music.dispose();
    await music.settled;
    expect(calls.last, isFalse);
  });

  test('Stored mute prevents an initial audible blip', () async {
    await SharedPreferencesAsync().setBool(LobbyMusicController.muteKey, true);
    final music = LobbyMusicController();
    music.setLobbyVisible(true);
    await music.initialize();
    await music.settled;
    expect(calls, isNot(contains(true)));
    music.dispose();
    await music.settled;
  });

  testWidgets('A dialog above a game cannot restart lobby music', (
    tester,
  ) async {
    final music = LobbyMusicController();
    await music.initialize();
    final key = GlobalKey<NavigatorState>();
    await tester.pumpWidget(
      MaterialApp(
        navigatorKey: key,
        navigatorObservers: [LobbyMusicObserver(music)],
        home: const SizedBox(),
      ),
    );
    await tester.pumpAndSettle();
    await music.settled;
    expect(calls.last, isTrue);
    key.currentState!.push(
      MaterialPageRoute<void>(
        settings: const RouteSettings(name: LobbyMusicController.gameRoute),
        builder: (_) => const Scaffold(body: SizedBox()),
      ),
    );
    await tester.pumpAndSettle();
    await music.settled;
    expect(music.lobbyVisible, isFalse);
    expect(calls.last, isFalse);
    showDialog<void>(
      context: key.currentContext!,
      builder: (_) => const AlertDialog(title: Text('Game dialog')),
    );
    await tester.pumpAndSettle();
    await music.settled;
    expect(calls.last, isFalse);
    key.currentState!.pop();
    await tester.pumpAndSettle();
    key.currentState!.pop();
    await tester.pumpAndSettle();
    await music.settled;
    expect(calls.last, isTrue);
    await tester.pumpWidget(const SizedBox());
    music.dispose();
    await music.settled;
  });

  testWidgets('Main menu offers a working mute control', (tester) async {
    await tester.pumpWidget(const SpiralApp());
    await tester.pumpAndSettle();
    expect(find.byTooltip('Mute lobby music'), findsOneWidget);
    await tester.tap(find.byTooltip('Mute lobby music'));
    await tester.pumpAndSettle();
    expect(find.byTooltip('Unmute lobby music'), findsOneWidget);
    expect(calls.last, isFalse);
    await tester.pumpWidget(const SizedBox());
    await tester.pump();
  });
}
