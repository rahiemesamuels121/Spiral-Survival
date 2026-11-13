// Run: flutter test tools/export_app_icon.dart
import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter_test/flutter_test.dart';
import 'package:spiral_pass_play/app/theme.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('Export branded launcher icons from vector geometry', () async {
    final outputs = {
      'android/app/src/main/res/mipmap-mdpi/ic_launcher.png': 48,
      'android/app/src/main/res/mipmap-hdpi/ic_launcher.png': 72,
      'android/app/src/main/res/mipmap-xhdpi/ic_launcher.png': 96,
      'android/app/src/main/res/mipmap-xxhdpi/ic_launcher.png': 144,
      'android/app/src/main/res/mipmap-xxxhdpi/ic_launcher.png': 192,
      'docs/app_icon.png': 512,
    };
    for (final output in outputs.entries) {
      final recorder = ui.PictureRecorder();
      final canvas = ui.Canvas(recorder)..scale(output.value / 108);
      canvas.drawColor(AppTheme.navy, ui.BlendMode.src);
      final path = ui.Path()
        ..moveTo(30, 30)
        ..lineTo(78, 30)
        ..lineTo(78, 78)
        ..lineTo(30, 78)
        ..lineTo(30, 43)
        ..lineTo(65, 43)
        ..lineTo(65, 65)
        ..lineTo(43, 65)
        ..lineTo(43, 55)
        ..lineTo(54, 55);
      canvas.drawPath(
        path,
        ui.Paint()
          ..color = AppTheme.gold
          ..style = ui.PaintingStyle.stroke
          ..strokeWidth = 5
          ..strokeCap = ui.StrokeCap.round
          ..strokeJoin = ui.StrokeJoin.round,
      );
      final picture = recorder.endRecording();
      final image = await picture.toImage(output.value, output.value);
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      await File(output.key).writeAsBytes(bytes!.buffer.asUint8List());
      image.dispose();
      picture.dispose();
    }
  });
}
