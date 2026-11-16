import 'package:flutter_test/flutter_test.dart';
import 'package:spiral_pass_play/firebase_config.dart';

void main() {
  test('Standard builds enable online play without dart-define flags', () {
    expect(FirebaseConfig.configured, isTrue);
    expect(FirebaseConfig.options.projectId, 'spiral-survival-c4ff0');
    expect(FirebaseConfig.options.apiKey, isNotEmpty);
    expect(FirebaseConfig.options.appId, contains(':android:'));
    expect(FirebaseConfig.options.messagingSenderId, matches(RegExp(r'^\d+$')));
  });
}
