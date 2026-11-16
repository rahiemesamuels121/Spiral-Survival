import 'player_state.dart';
import 'tile_summary.dart';
import 'weapon.dart';

/// Each phase is explicit, making pass-and-play hand-offs and saves reliable.
enum TurnPhase {
  ready,
  rolling,
  animating,
  specialReview,
  jailChoice,
  hospitalChoice,
  shopping,
  weaponAction,
  preMoveWeaponChoice,
  eventReveal,
  portalChoice,
  portalTravel,
  handoff,
  completed,
}

class GameSession {
  GameSession({
    required this.players,
    required this.boardId,
    this.currentPlayerIndex = 0,
    this.round = 1,
    this.lastDice,
    this.message = 'Tap ROLL DICE to begin.',
    this.winnerId,
    this.phase = TurnPhase.ready,
    this.pendingCardId,
    this.tileSummary,
    this.pendingPoliceFine,
    this.pendingPoliceJail,
    this.pendingHospital = false,
    this.pendingShopTile,
    this.pendingPortalTile,
    List<int>? portalCardDirections,
    this.weaponActionTaken = false,
    this.weaponRules = const WeaponRules(),
    this.handoffMessage = 'Pass the device to the next player.',
    List<String>? eventDrawPile,
    List<String>? eventDiscardPile,
  }) : portalCardDirections = portalCardDirections ?? <int>[],
       eventDrawPile = eventDrawPile ?? <String>[],
       eventDiscardPile = eventDiscardPile ?? <String>[];

  final String boardId;
  final List<PlayerState> players;
  int currentPlayerIndex;
  int round;
  int? lastDice;
  String message;
  String? winnerId;
  TurnPhase phase;
  String? pendingCardId;
  TileSummary? tileSummary;
  int? pendingPoliceFine;
  int? pendingPoliceJail;
  bool pendingHospital;
  int? pendingShopTile;
  int? pendingPortalTile;
  final List<int> portalCardDirections;
  bool weaponActionTaken;
  final WeaponRules weaponRules;
  String handoffMessage;
  final List<String> eventDrawPile;
  final List<String> eventDiscardPile;

  PlayerState get currentPlayer => players[currentPlayerIndex];

  Map<String, dynamic> toJson() => {
    'schemaVersion': 3,
    'boardId': boardId,
    'players': players.map((p) => p.toJson()).toList(),
    'currentPlayerIndex': currentPlayerIndex,
    'round': round,
    'lastDice': lastDice,
    'message': message,
    'winnerId': winnerId,
    'phase': phase.name,
    'pendingCardId': pendingCardId,
    'tileSummary': tileSummary?.toJson(),
    'pendingPoliceFine': pendingPoliceFine,
    'pendingPoliceJail': pendingPoliceJail,
    'pendingHospital': pendingHospital,
    'pendingShopTile': pendingShopTile,
    'pendingPortalTile': pendingPortalTile,
    'portalCardDirections': portalCardDirections,
    'weaponActionTaken': weaponActionTaken,
    'weaponRules': weaponRules.toJson(),
    'handoffMessage': handoffMessage,
    'eventDrawPile': eventDrawPile,
    'eventDiscardPile': eventDiscardPile,
  };

  factory GameSession.fromJson(Map<String, dynamic> json) {
    final version = (json['schemaVersion'] as num?)?.toInt();
    if (version != 2 && version != 3) {
      throw const FormatException('Unsupported save format. Start a new game.');
    }
    final boardId = json['boardId'] as String?;
    if (boardId == null || boardId.isEmpty) {
      throw const FormatException('Missing board identifier');
    }
    final players = (json['players'] as List<dynamic>)
        .map((p) => PlayerState.fromJson(Map<String, dynamic>.from(p as Map)))
        .toList();
    if (players.length < 2 || players.length > 5) {
      throw const FormatException('Game requires 2–5 players');
    }
    final current = (json['currentPlayerIndex'] as num?)?.toInt() ?? 0;
    if (current < 0 || current >= players.length) {
      throw const FormatException('Invalid player index');
    }
    final winnerId = json['winnerId'] as String?;
    TurnPhase loadedPhase = TurnPhase.ready;
    if (version == 3) {
      loadedPhase = TurnPhase.values.byName(
        json['phase'] as String? ?? 'ready',
      );
    } else if (winnerId != null) {
      loadedPhase = TurnPhase.completed;
    }
    // No half-played dice roll may be restored. Normal saved states are
    // ready, eventReveal, handoff or completed; discard interrupted animations.
    if (loadedPhase == TurnPhase.rolling ||
        loadedPhase == TurnPhase.animating) {
      loadedPhase = TurnPhase.ready;
    }
    // A selected mystery card is committed even if its animation is interrupted.
    if (loadedPhase == TurnPhase.portalTravel) {
      loadedPhase = (json['pendingHospital'] as bool? ?? false)
          ? TurnPhase.hospitalChoice
          : json['pendingPoliceFine'] != null
          ? TurnPhase.jailChoice
          : TurnPhase.specialReview;
    }
    if (winnerId != null &&
        loadedPhase != TurnPhase.eventReveal &&
        loadedPhase != TurnPhase.specialReview) {
      loadedPhase = TurnPhase.completed;
    }
    final pendingCard = json['pendingCardId'] as String?;
    if (loadedPhase == TurnPhase.eventReveal && pendingCard == null) {
      throw const FormatException('Saved card reveal is missing its card.');
    }
    final summary = json['tileSummary'] == null
        ? null
        : TileSummary.fromJson(
            Map<String, dynamic>.from(json['tileSummary'] as Map),
          );
    if (loadedPhase == TurnPhase.specialReview && summary == null) {
      throw const FormatException(
        'Saved special tile review is missing its summary.',
      );
    }
    final pendingFine = (json['pendingPoliceFine'] as num?)?.toInt();
    final pendingJail = (json['pendingPoliceJail'] as num?)?.toInt();
    if (loadedPhase == TurnPhase.jailChoice &&
        (pendingFine == null || pendingFine <= 0)) {
      throw const FormatException('Saved police choice is missing its fine.');
    }
    final pendingShop = (json['pendingShopTile'] as num?)?.toInt();
    if (loadedPhase == TurnPhase.shopping && pendingShop == null) {
      throw const FormatException('Saved shop visit is missing its tile.');
    }
    // Older matches charged every hospital arrival. Preserve an outstanding
    // treatment choice while ordinary legacy players remain healthy.
    final currentPlayerJson =
        (json['players'] as List<dynamic>)[current] as Map;
    if (loadedPhase != TurnPhase.ready &&
        (json['pendingHospital'] as bool? ?? false) &&
        !currentPlayerJson.containsKey('isInjured')) {
      players[current].isInjured = true;
    }
    final pendingPortal = (json['pendingPortalTile'] as num?)?.toInt();
    final portalDirections =
        (json['portalCardDirections'] as List<dynamic>?)
            ?.map((value) => (value as num).toInt())
            .toList() ??
        <int>[];
    if (pendingPortal != null &&
            (portalDirections.length != 2 ||
                !portalDirections.contains(-1) ||
                !portalDirections.contains(1)) ||
        loadedPhase == TurnPhase.portalChoice && pendingPortal == null) {
      throw const FormatException(
        'Saved portal choice must have two mystery cards.',
      );
    }
    return GameSession(
      players: players,
      boardId: boardId,
      currentPlayerIndex: current,
      round: (json['round'] as num?)?.toInt() ?? 1,
      lastDice: (json['lastDice'] as num?)?.toInt(),
      message: json['message'] as String? ?? 'Game resumed.',
      winnerId: winnerId,
      phase: loadedPhase,
      pendingCardId: pendingCard,
      tileSummary: summary,
      pendingHospital:
          loadedPhase != TurnPhase.ready &&
          (json['pendingHospital'] as bool? ?? false),
      pendingPoliceFine: loadedPhase == TurnPhase.ready ? null : pendingFine,
      pendingPoliceJail: loadedPhase == TurnPhase.ready ? null : pendingJail,
      pendingShopTile: loadedPhase == TurnPhase.ready ? null : pendingShop,
      pendingPortalTile: loadedPhase == TurnPhase.ready ? null : pendingPortal,
      portalCardDirections: loadedPhase == TurnPhase.ready
          ? <int>[]
          : portalDirections,
      weaponActionTaken: json['weaponActionTaken'] as bool? ?? false,
      weaponRules: json['weaponRules'] == null
          ? const WeaponRules()
          : WeaponRules.fromJson(
              Map<String, dynamic>.from(json['weaponRules'] as Map),
            ),
      handoffMessage:
          json['handoffMessage'] as String? ??
          'Pass the device to the next player.',
      eventDrawPile:
          (json['eventDrawPile'] as List<dynamic>?)?.cast<String>().toList() ??
          <String>[],
      eventDiscardPile:
          (json['eventDiscardPile'] as List<dynamic>?)
              ?.cast<String>()
              .toList() ??
          <String>[],
    );
  }
}
