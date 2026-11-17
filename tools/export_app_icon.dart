// Run: flutter test tools/export_app_icon.dart
import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'Export launcher icons from the supplied Spiral Survival artwork',
    () async {
      final source = await File(
        'assets/branding/spiral_survival.png',
      ).readAsBytes();
      final outputs = {
        'android/app/src/main/res/mipmap-mdpi/ic_launcher.png': 48,
        'android/app/src/main/res/mipmap-hdpi/ic_launcher.png': 72,
        'android/app/src/main/res/mipmap-xhdpi/ic_launcher.png': 96,
        'android/app/src/main/res/mipmap-xxhdpi/ic_launcher.png': 144,
        'android/app/src/main/res/mipmap-xxxhdpi/ic_launcher.png': 192,
        'android/app/src/main/res/drawable-nodpi/brand_art.png': 512,
        'docs/app_icon.png': 512,
      };
      for (final output in outputs.entries) {
        final codec = await ui.instantiateImageCodec(
          source,
          targetWidth: output.value,
          targetHeight: output.value,
        );
        final frame = await codec.getNextFrame();
        final bytes = await frame.image.toByteData(
          format: ui.ImageByteFormat.png,
        );
        await File(output.key).writeAsBytes(bytes!.buffer.asUint8List());
        frame.image.dispose();
        codec.dispose();
      }
    },
  );
}
