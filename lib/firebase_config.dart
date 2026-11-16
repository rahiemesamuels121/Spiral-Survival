import 'package:firebase_core/firebase_core.dart';
import 'firebase_client_defaults.dart';

/// Default public Firebase client options; build-time overrides remain optional.
abstract final class FirebaseConfig {
  static const projectId = FirebaseClientDefaults.projectId;
  static const apiKey = String.fromEnvironment(
    'FIREBASE_API_KEY',
    defaultValue: FirebaseClientDefaults.apiKey,
  );
  static const appId = String.fromEnvironment(
    'FIREBASE_APP_ID',
    defaultValue: FirebaseClientDefaults.appId,
  );
  static const senderId = String.fromEnvironment(
    'FIREBASE_MESSAGING_SENDER_ID',
    defaultValue: FirebaseClientDefaults.senderId,
  );
  static const emulatorHost = String.fromEnvironment('FIREBASE_EMULATOR_HOST');
  static bool get configured =>
      apiKey.isNotEmpty && appId.isNotEmpty && senderId.isNotEmpty;
  static FirebaseOptions get options => FirebaseOptions(
    apiKey: apiKey,
    appId: appId,
    messagingSenderId: senderId,
    projectId: projectId,
  );
}
