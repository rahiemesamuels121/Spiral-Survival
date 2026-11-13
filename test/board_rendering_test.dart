import 'dart:ui' as ui;
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:spiral_pass_play/features/game/data/board_repository.dart';
import 'package:spiral_pass_play/features/game/domain/board_definition.dart';
import 'package:spiral_pass_play/features/game/flame/spiral_board_game.dart';
import 'package:spiral_pass_play/features/game/vector/board_artwork.dart';

Future<Uint8List> pixels(void Function(ui.Canvas) draw, int size) async {
  final recorder = ui.PictureRecorder();
  final canvas = ui.Canvas(recorder)..scale(size / 1000);
  draw(canvas);
  final picture = recorder.endRecording();
  final image = await picture.toImage(size, size);
  final bytes = await image.toByteData();
  final result = Uint8List.fromList(bytes!.buffer.asUint8List());
  image.dispose();
  picture.dispose();
  return result;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'Cached drawing preserves board pixels, custom artwork and remounts',
    () async {
      final reference = await const BoardRepository().loadReferenceBoard();
      final tiles = reference.tiles.toList();
      tiles[1] = tiles[1].withChanges({
        'label': 'CUSTOM',
        'fillColor': 0xFF123456,
      });
      final board = BoardDefinition(tiles);
      final artwork = BoardArtwork(board);
      final component = VectorBoardComponent(board);
      await component.onLoad();
      for (final size in [256, 768]) {
        final expected = await pixels(artwork.scene.paint, size);
        final actual = await pixels(component.render, size);
        expect(
          listEquals(actual, expected),
          isTrue,
          reason: 'Cached board at $size px',
        );
      }
      component.onRemove();
      final remounted = await pixels(component.render, 256);
      final expected = await pixels(artwork.scene.paint, 256);
      expect(listEquals(remounted, expected), isTrue);
      component.onRemove();
    },
  );
}
