import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../domain/game_session.dart';

class SessionStore {
  static const _key = 'spiral_pass_play_v2';
  final SharedPreferencesAsync _preferences = SharedPreferencesAsync();

  Future<void> save(GameSession session) =>
      saveEncoded(jsonEncode(session.toJson()));

  // Accept an immutable snapshot so queued writes cannot observe later turns.
  Future<void> saveEncoded(String snapshot) =>
      _preferences.setString(_key, snapshot);

  Future<GameSession?> load() async {
    final raw = await _preferences.getString(_key);
    if (raw == null) return null;
    try {
      return GameSession.fromJson(
        Map<String, dynamic>.from(jsonDecode(raw) as Map),
      );
    } catch (_) {
      return null;
    }
  }

  Future<void> clear() => _preferences.remove(_key);
}
