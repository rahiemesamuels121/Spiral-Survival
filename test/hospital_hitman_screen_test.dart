import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';
import 'package:spiral_pass_play/app/theme.dart';
import 'package:spiral_pass_play/features/game/application/game_controller.dart';
import 'package:spiral_pass_play/features/game/domain/board_definition.dart';
import 'package:spiral_pass_play/features/game/domain/game_session.dart';
import 'package:spiral_pass_play/features/game/presentation/game_screen.dart';

BoardDefinition _board() => BoardDefinition([
  for (var i = 0; i < 30; i++)
    BoardTile(
      index: i,
      x: .1 + (i % 5) * .15,
      y: .1 + (i ~/ 5) * .15,
      type: switch (i) {
        0 => TileType.start,
        2 => TileType.hospital,
        4 => TileType.secretSociety,
        29 => TileType.finish,
        _ => TileType.normal,
      },
    ),
]);

void main() {
  for (final size in [const Size(320, 640), const Size(800, 360)]) {
    for (final hospital in [true, false]) {
      testWidgets(
        '${hospital ? 'Hospital' : 'Secret Society'} works at $size with enlarged text',
        (tester) async {
          tester.view.physicalSize = size;
          tester.view.devicePixelRatio = 1;
          tester.platformDispatcher.textScaleFactorTestValue = 1.25;
          addTearDown(tester.view.resetPhysicalSize);
          addTearDown(tester.view.resetDevicePixelRatio);
          addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
          if (Platform.environment['EXPORT_SOCIETY_PREVIEWS'] == '1') {
            await tester.runAsync(() async {
              final font = File('/System/Library/Fonts/Supplemental/Arial.ttf');
              for (final family in ['Roboto', 'Ahem']) {
                await (FontLoader(family)..addFont(
                      font.readAsBytes().then((b) => ByteData.sublistView(b)),
                    ))
                    .load();
              }
              final icons = File(
                '/Users/webdeveloper/flutter/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf',
              );
              await (FontLoader('MaterialIcons')..addFont(
                    icons.readAsBytes().then((b) => ByteData.sublistView(b)),
                  ))
                  .load();
            });
          }
          SharedPreferencesAsyncPlatform.instance =
              InMemorySharedPreferencesAsync.empty();
          var now = DateTime.utc(2026, 11, 16);
          final game = GameController.newGame(
            names: ['One', 'Two'],
            colors: [1, 2],
            board: _board(),
            clock: () => now,
          );
          game.session.currentPlayer.position = hospital ? 2 : 4;
          game.session.currentPlayer.cash = 500;
          game.session.pendingShopTile = game.session.currentPlayer.position;
          game.session.phase = TurnPhase.shopping;
          game.session.players[1].position = 10;
          await tester.runAsync(() async {
            await tester.pumpWidget(
              MaterialApp(
                theme: AppTheme.dark,
                home: RepaintBoundary(
                  key: const ValueKey('preview'),
                  child: GameScreen(controller: game),
                ),
              ),
            );
            await Future<void>.delayed(const Duration(milliseconds: 100));
          });
          await tester.pump();
          if (hospital) {
            final label = find.text('BUY HEALTH PACK · \$10');
            expect(
              find.byKey(const ValueKey('hospital-stock')),
              findsOneWidget,
            );
            expect(
              find.textContaining('Health kits in stock: 2'),
              findsOneWidget,
            );
            await tester.ensureVisible(label);
            await tester.tap(label);
            await tester.pump();
            await tester.tap(label);
            await tester.pump();
            expect(game.hospitalKitsAvailable, 0);
            expect(game.session.currentPlayer.inventory.healthPacks, 2);
            expect(find.textContaining('Out of stock'), findsOneWidget);
            await tester.tap(label);
            await tester.pump();
            expect(game.session.currentPlayer.inventory.healthPacks, 2);
            now = now.add(const Duration(minutes: 5));
            await tester.runAsync(
              () => Future<void>.delayed(const Duration(milliseconds: 1100)),
            );
            await tester.pump();
            expect(
              find.textContaining('Health kits in stock: 1'),
              findsOneWidget,
            );
            await tester.tap(label);
            await tester.pump();
            expect(game.session.currentPlayer.inventory.healthPacks, 3);
          } else {
            final hire = find.byKey(const ValueKey('hire-hitman'));
            await tester.ensureVisible(hire);
            await tester.tap(hire);
            await tester.pump();
            expect(game.session.currentPlayer.cash, 300);
            expect(game.session.hitmanTile, 4);
            expect(find.text('YOUR HITMAN · SPACE 4'), findsOneWidget);
            expect(
              find.textContaining('This turn was used for movement'),
              findsOneWidget,
            );
            final leave = find.text('LEAVE SECRET SOCIETY');
            await tester.ensureVisible(leave);
            await tester.tap(leave);
            await tester.pump();
            game.session.currentPlayerIndex = 0;
            game.acknowledgeHandoff();
            await tester.pump();
            await tester.tap(find.byTooltip('Hitman contract'));
            await tester.pump();
            await tester.pump(const Duration(milliseconds: 400));
            final target = find.text('TARGET Two · SPACE 10');
            await tester.ensureVisible(target);
            await tester.tap(target);
            await tester.pump();
            expect(game.session.players[1].position, 0);
            expect(game.session.hitmanHired, isFalse);
            expect(game.beginDiceRoll(), isNull);
            await tester.tap(find.text('CLOSE'));
            await tester.pump();
            for (var i = 0; i < 30; i++) {
              await tester.pump(const Duration(milliseconds: 100));
            }
            expect(find.text('CONTINUE'), findsOneWidget);
            await tester.ensureVisible(find.text('CONTINUE'));
            await tester.tap(find.text('CONTINUE'));
            await tester.pump();
            expect(game.session.currentPlayerIndex, 1);
          }
          expect(tester.takeException(), isNull);
          if (Platform.environment['EXPORT_SOCIETY_PREVIEWS'] == '1') {
            final boundary = tester.renderObject<RenderRepaintBoundary>(
              find.byKey(const ValueKey('preview')),
            );
            await tester.runAsync(() async {
              final image = await boundary.toImage();
              final bytes = await image.toByteData(
                format: ui.ImageByteFormat.png,
              );
              await File(
                '/private/tmp/spiral-${hospital ? 'stock' : 'society'}-${size.width.toInt()}.png',
              ).writeAsBytes(bytes!.buffer.asUint8List());
              image.dispose();
            });
          }
          await tester.pumpWidget(const SizedBox.shrink());
          game.dispose();
        },
      );
    }
  }
}
