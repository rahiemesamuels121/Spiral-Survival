// dart tools/configure_firebase.dart /path/to/google-services.json
import 'dart:convert';
import 'dart:io';

void main(List<String> args) {
  if (args.length != 1) {
    stderr.writeln(
      'Usage: dart tools/configure_firebase.dart /path/to/google-services.json',
    );
    exitCode = 64;
    return;
  }
  final data =
      jsonDecode(File(args.single).readAsStringSync()) as Map<String, dynamic>;
  final project = data['project_info'] as Map<String, dynamic>;
  if (project['project_id'] != 'spiral-survival-c4ff0') {
    throw StateError('Expected Firebase project spiral-survival-c4ff0.');
  }
  final clients = (data['client'] as List).cast<Map<String, dynamic>>();
  final package = RegExp(r'applicationId\s*=\s*"([^"]+)"')
      .firstMatch(File('android/app/build.gradle.kts').readAsStringSync())!
      .group(1);
  final client = clients.firstWhere(
    (c) => c['client_info']['android_client_info']['package_name'] == package,
    orElse: () => throw StateError(
      'Register Android package $package in spiral-survival-c4ff0, then download its configuration.',
    ),
  );
  final config = {
    'FIREBASE_API_KEY': client['api_key'][0]['current_key'],
    'FIREBASE_APP_ID': client['client_info']['mobilesdk_app_id'],
    'FIREBASE_MESSAGING_SENDER_ID': project['project_number'],
  };
  File('firebase_client.json').writeAsStringSync(
    '${const JsonEncoder.withIndent('  ').convert(config)}\n',
  );
  // Firebase client identifiers are public app configuration, not Admin secrets.
  // Keep normal flutter run/build commands connected without extra flags.
  final defaults = <String, dynamic>{
    'projectId': project['project_id'],
    'apiKey': config['FIREBASE_API_KEY'],
    'appId': config['FIREBASE_APP_ID'],
    'senderId': config['FIREBASE_MESSAGING_SENDER_ID'],
  };
  if (defaults.values.any((value) => value is! String || value.isEmpty)) {
    throw StateError('The Firebase client configuration is incomplete.');
  }
  final lines = defaults.entries
      .map(
        (entry) => '  static const ${entry.key} = ${jsonEncode(entry.value)};',
      )
      .join('\n');
  File('lib/firebase_client_defaults.dart').writeAsStringSync(
    '// Generated from the public Android Firebase client configuration.\n'
    '// Regenerate with tools/configure_firebase.dart; never use service-account keys.\n'
    'abstract final class FirebaseClientDefaults {\n$lines\n}\n',
  );
  stdout.writeln(
    'Configured Firebase defaults for spiral-survival-c4ff0 ($package). Normal flutter run/build commands now enable online play.',
  );
}
