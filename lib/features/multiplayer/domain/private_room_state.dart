import 'dart:convert';

/// The host keeps authoritative state separately from member-readable views.
/// Public room documents must never contain contracts or player finances.
Map<String, dynamic> publicSession(Map<String, dynamic> state) {
  final view = Map<String, dynamic>.from(jsonDecode(jsonEncode(state)) as Map);
  view.remove('hitmanOwnerId');
  view.remove('hitmanTile');
  view['privateViews'] = true;
  for (final player in view['players'] as List) {
    final p = player as Map;
    p['cash'] = 0;
    p['debt'] = 0;
    p['inventory'] = <String, dynamic>{'cash': 0};
  }
  final summary = view['tileSummary'] as Map?;
  if (summary != null) summary['changes'] = <String>[];
  return view;
}

Map<String, dynamic> privateSessionView(
  Map<String, dynamic> state,
  String playerId,
) => {
  'player': (state['players'] as List).cast<Map>().singleWhere(
    (p) => p['id'] == playerId,
  ),
  if (state['hitmanOwnerId'] == playerId) ...{
    'hitmanOwnerId': playerId,
    'hitmanTile': state['hitmanTile'],
  },
  if ((state['players'] as List)[state['currentPlayerIndex'] as int]['id'] ==
      playerId)
    'tileSummary': state['tileSummary'],
};

Map<String, dynamic> applyPrivateView(
  Map<String, dynamic> public,
  Map<String, dynamic> private,
) {
  final view = Map<String, dynamic>.from(jsonDecode(jsonEncode(public)) as Map);
  final own = private['player'] as Map?;
  if (own != null) {
    final players = view['players'] as List;
    final index = players.indexWhere((p) => p['id'] == own['id']);
    if (index >= 0) {
      // Preserve public positions, icons and animation state.
      for (final key in ['cash', 'debt', 'inventory']) {
        (players[index] as Map)[key] = own[key];
      }
    }
  }
  if (private['hitmanOwnerId'] != null) {
    view['hitmanOwnerId'] = private['hitmanOwnerId'];
    view['hitmanTile'] = private['hitmanTile'];
  }
  if (private.containsKey('tileSummary')) {
    view['tileSummary'] = private['tileSummary'];
  }
  return view;
}

String publicOutcome(String outcome) {
  if (outcome.isEmpty) return '';
  final view = jsonDecode(outcome) as Map<String, dynamic>;
  if (view['results'] != null) {
    view['results'] = [
      for (final result in view['results'] as List)
        publicSession(Map<String, dynamic>.from(result as Map)),
    ];
  }
  return jsonEncode(view);
}

String playerOutcome(String outcome, String playerId) {
  if (outcome.isEmpty) return '';
  final view = jsonDecode(outcome) as Map<String, dynamic>;
  if (view['results'] != null) {
    view['results'] = [
      for (final result in view['results'] as List)
        applyPrivateView(
          publicSession(Map<String, dynamic>.from(result as Map)),
          privateSessionView(Map<String, dynamic>.from(result), playerId),
        ),
    ];
  }
  return jsonEncode(view);
}
