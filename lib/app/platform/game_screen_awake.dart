import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Android's window flag keeps a visible match awake without a background lock.
abstract final class GameScreenAwake {
  static const channel = MethodChannel('spiral_quest/screen');

  static Future<void> setEnabled(bool enabled) async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) return;
    try {
      await channel.invokeMethod<void>('setKeepScreenOn', enabled);
    } on MissingPluginException {
      // Widget tests and an older host during hot reload have no native bridge.
      debugPrint('Keep-screen-on requires the updated Android build.');
    } on PlatformException catch (error) {
      debugPrint('Could not update screen timeout: ${error.code}');
    }
  }
}
