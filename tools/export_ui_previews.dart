// Run: flutter test tools/export_ui_previews.dart
import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';
import 'package:spiral_pass_play/app/theme.dart';
import 'package:spiral_pass_play/features/setup/setup_screen.dart';
import 'package:spiral_pass_play/features/game/application/game_controller.dart';
import 'package:spiral_pass_play/features/game/data/board_repository.dart';
import 'package:spiral_pass_play/features/game/presentation/game_screen.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('Render release presentation previews', (tester) async {
    final font = File('/System/Library/Fonts/Supplemental/Arial.ttf');
    await tester.runAsync(() async {
      for (final family in ['Preview', 'Roboto', 'Ahem']) {
        final loader = FontLoader(family)
          ..addFont(font.readAsBytes().then((b) => ByteData.sublistView(b)));
        await loader.load();
      }
      final icons = File(
        '/Users/webdeveloper/flutter/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf',
      );
      final iconLoader = FontLoader('MaterialIcons')
        ..addFont(icons.readAsBytes().then((b) => ByteData.sublistView(b)));
      await iconLoader.load();
    });
    SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.empty();
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1100, 800);
    final key = GlobalKey();
    Future<void> capture(String name) async {
      await tester.pump();
      final boundary =
          key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
      await tester.runAsync(() async {
        final image = await boundary.toImage();
        final data = await image.toByteData(format: ui.ImageByteFormat.png);
        await File('docs/$name.png').writeAsBytes(data!.buffer.asUint8List());
        image.dispose();
      });
    }

    final previewTheme = AppTheme.dark.copyWith(
      textTheme: AppTheme.dark.textTheme.apply(fontFamily: 'Preview'),
      filledButtonTheme: FilledButtonThemeData(
        style: AppTheme.dark.filledButtonTheme.style!.copyWith(
          textStyle: const WidgetStatePropertyAll(
            TextStyle(
              fontFamily: 'Preview',
              fontWeight: FontWeight.w800,
              letterSpacing: 1,
            ),
          ),
        ),
      ),
      chipTheme: AppTheme.dark.chipTheme.copyWith(
        labelStyle: const TextStyle(
          fontFamily: 'Preview',
          fontWeight: FontWeight.w700,
        ),
      ),
    );
    Widget wrap(Widget child) => RepaintBoundary(
      key: key,
      child: DefaultTextStyle(
        style: const TextStyle(fontFamily: 'Preview'),
        child: child,
      ),
    );
    await tester.pumpWidget(
      wrap(
        MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: previewTheme,
          home: const GameSetupScreen(),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await capture('setup_preview');
    final board = (await tester.runAsync(
      () => const BoardRepository().loadReferenceBoard(),
    ))!;
    final game = GameController.newGame(
      names: ['Alex', 'Sam'],
      colors: AppTheme.playerColors.map((c) => c.toARGB32()).toList(),
      board: board,
      diceRoller: () => 1,
    );
    game.session.currentPlayer.position = 3;
    game.roll();
    game.finishAnimation();
    await tester.runAsync(() async {
      await tester.pumpWidget(
        wrap(
          MaterialApp(
            debugShowCheckedModeBanner: false,
            theme: previewTheme,
            home: GameScreen(controller: game),
          ),
        ),
      );
      await Future<void>.delayed(const Duration(milliseconds: 200));
    });
    await tester.pump(const Duration(milliseconds: 300));
    await capture('result_preview');
    await tester.pumpWidget(const SizedBox.shrink());
    game.dispose();
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  });
}
