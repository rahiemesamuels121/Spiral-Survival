// Run from the project root: flutter test tools/export_vector_board.dart
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:spiral_pass_play/features/game/domain/board_definition.dart';
import 'package:spiral_pass_play/features/game/vector/board_artwork.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('Export the reference vector board and its preview', () async {
    // Flutter tests otherwise substitute Ahem, whose letters are solid blocks.
    final fontPath =
        Platform.environment['BOARD_PREVIEW_FONT'] ??
        '/System/Library/Fonts/Supplemental/Arial.ttf';
    final font = File(fontPath);
    if (!await font.exists()) {
      throw StateError('Set BOARD_PREVIEW_FONT to a readable .ttf font file.');
    }
    final loader = FontLoader(
      'Arial',
    )..addFont(font.readAsBytes().then((bytes) => ByteData.sublistView(bytes)));
    await loader.load();
    final board = BoardDefinition.fromJson(
      Map<String, dynamic>.from(
        jsonDecode(
              await File('assets/boards/spiral_board_map.json').readAsString(),
            )
            as Map,
      ),
    );
    final artwork = BoardArtwork(board);
    await File(
      'assets/boards/spiral_board.svg',
    ).writeAsString(artwork.scene.toSvg());
    final recorder = ui.PictureRecorder();
    final canvas = ui.Canvas(recorder)..scale(1.261);
    artwork.scene.paint(canvas);
    final picture = recorder.endRecording();
    final image = await picture.toImage(1261, 1261);
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    await File(
      'docs/vector_board_preview.png',
    ).writeAsBytes(bytes!.buffer.asUint8List());
    image.dispose();
    picture.dispose();
  });
}
