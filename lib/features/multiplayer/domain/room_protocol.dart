import 'dart:convert';
import '../../game/application/game_controller.dart';
import '../../game/domain/board_definition.dart';
import '../../game/domain/game_session.dart';
import '../../game/domain/medical_item.dart';
import '../../game/domain/player_icon.dart';
import '../../game/domain/weapon.dart';

const maxRoomPlayers = 5;

/// Membership order is fixed when a match starts and maps Firebase UIDs to seats.
class OnlineRoom {
  const OnlineRoom({
    required this.code,
    required this.hostId,
    required this.members,
    required this.playerOrder,
    required this.status,
    required this.revision,
    required this.state,
    required this.outcome,
    required this.lastRequestId,
    required this.lastError,
    required this.hostSeen,
    required this.expiresAt,
  });
  final String code, hostId, status, state, outcome, lastRequestId, lastError;
  final Map<String, String> members;
  final List<String> playerOrder;
  final int revision;
  final DateTime hostSeen, expiresAt;
  bool get full => members.length >= maxRoomPlayers;
  bool get expired => DateTime.now().isAfter(expiresAt);
  bool get hostAvailable => DateTime.now().difference(hostSeen).inSeconds < 120;
  GameSession? get session => state.isEmpty
      ? null
      : GameSession.fromJson(jsonDecode(state) as Map<String, dynamic>);
  String? get activeUid {
    final game = session;
    return game == null ? null : playerOrder[game.currentPlayerIndex];
  }
}

/// Reuses the offline rules on the host. No guest can supply dice or state.
class RoomCommandResult {
  const RoomCommandResult(this.state, this.outcome);
  final String state, outcome;
}

RoomCommandResult executeRoomCommand({
  required OnlineRoom room,
  required String senderId,
  required int expectedRevision,
  required String action,
  required Map<String, dynamic> args,
  required BoardDefinition board,
  DiceRoller? diceRoller,
}) {
  if (room.status != 'playing' ||
      room.expired ||
      !room.playerOrder.contains(senderId) ||
      (action != 'playerIcon' && room.activeUid != senderId) ||
      expectedRevision != room.revision) {
    throw StateError(
      'That turn has changed. Wait for your turn and try again.',
    );
  }
  if (action == 'playerIcon') {
    if (args.length != 1 || args['icon'] is! String) {
      throw StateError('Choose a player icon.');
    }
    final icon = PlayerIcon.values.where((icon) => icon.name == args['icon']);
    if (icon.isEmpty) throw StateError('Choose a valid player icon.');
    final state = room.session!;
    state.players[room.playerOrder.indexOf(senderId)].icon = icon.single;
    return RoomCommandResult(jsonEncode(state.toJson()), '');
  }
  const allowed = <String, Set<String>>{
    'roll': {},
    'move': {},
    'review': {},
    'event': {},
    'shopDone': {},
    'endTurn': {},
    'hospital': {'pay'},
    'healthPack': {},
    'police': {'pay'},
    'portal': {'card'},
    'buy': {'weapon'},
    'medicalBuy': {'item'},
    'attack': {'weapon', 'target'},
  };
  if (!allowed.containsKey(action) ||
      !args.keys.every(allowed[action]!.contains)) {
    throw StateError('Invalid game action.');
  }
  final game = GameController(
    session: room.session!,
    board: board,
    diceRoller: diceRoller,
  );
  try {
    final before = jsonEncode(game.session.toJson());
    switch (action) {
      case 'roll':
        game.roll();
      case 'move':
        game.chooseMovement();
      case 'review':
        game.dismissTileSummary();
      case 'event':
        game.dismissEventCard();
      case 'hospital':
        if (args.length != 1 || args['pay'] is! bool) {
          throw StateError('Choose one hospital treatment.');
        }
        game.chooseHospitalTreatment(pay: args['pay'] as bool);
      case 'healthPack':
        game.useHealthPack();
      case 'police':
        game.choosePolicePenalty(payFine: args['pay'] == true);
      case 'portal':
        final card = args['card'];
        if (card is! int || card < 0 || card > 1) {
          throw StateError('Choose one portal card.');
        }
        game.choosePortalCard(card);
      case 'buy':
        game.buyWeapon(WeaponType.values.byName(args['weapon'] as String));
      case 'medicalBuy':
        final item = MedicalItem.values.where(
          (item) => item.name == args['item'],
        );
        if (item.isEmpty) throw StateError('Choose a hospital item.');
        game.buyMedicalItem(item.single);
      case 'attack':
        game.useWeapon(
          WeaponType.values.byName(args['weapon'] as String),
          args['target'] as int,
        );
      case 'shopDone':
        game.finishShopping();
      case 'endTurn':
        game.skipWeaponAction();
      default:
        throw StateError('Unknown game action.');
    }
    if (jsonEncode(game.session.toJson()) == before) {
      throw StateError('That action is not available now.');
    }
    // Result screens belong to each device. Commit the next actual decision
    // immediately, carrying the passive screens separately for local viewing.
    final results = <Map<String, dynamic>>[];
    while (true) {
      switch (game.session.phase) {
        case TurnPhase.animating:
        case TurnPhase.portalTravel:
          game.finishAnimation();
        case TurnPhase.specialReview:
          results.add(game.session.toJson());
          game.dismissTileSummary();
        case TurnPhase.eventReveal:
          results.add(game.session.toJson());
          game.dismissEventCard();
        case TurnPhase.handoff:
          game.acknowledgeHandoff();
        default:
          break;
      }
      if (game.session.phase != TurnPhase.animating &&
          game.session.phase != TurnPhase.portalTravel &&
          game.session.phase != TurnPhase.specialReview &&
          game.session.phase != TurnPhase.eventReveal &&
          game.session.phase != TurnPhase.handoff) {
        break;
      }
    }
    final state = jsonEncode(game.session.toJson());
    final movement = game.lastOutcome;
    final outcome = movement == null && results.isEmpty
        ? ''
        : jsonEncode({
            if (movement != null) ...{
              'playerIndex': movement.playerIndex,
              'dice': movement.dice,
              'path': movement.path,
              'description': movement.description,
              'landedType': movement.landedType.name,
              'effectLabel': movement.effectLabel,
              'eventCardId': movement.eventCardId,
            },
            if (results.isNotEmpty) 'results': results,
          });
    return RoomCommandResult(state, outcome);
  } finally {
    game.dispose();
  }
}
