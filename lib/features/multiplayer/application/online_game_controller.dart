import 'dart:async';
import 'dart:convert';
import '../../game/application/game_controller.dart';
import '../../game/domain/board_definition.dart';
import '../../game/domain/game_session.dart';
import '../../game/domain/medical_item.dart';
import '../../game/domain/player_icon.dart';
import '../../game/domain/tile_summary.dart';
import '../../game/domain/weapon.dart';
import '../data/room_service.dart';

/// UI adapter: sends intentions and applies only host-committed snapshots.
class OnlineGameController extends GameController {
  OnlineGameController({required this.connection})
    : super(session: connection.visibleSession!, board: connection.board) {
    _revision = connection.room!.revision;
    connection.addListener(_receive);
  }
  final RoomService connection;
  late int _revision;
  TurnPhase? _afterAnimation;
  final _queuedMovements = <TurnOutcome>[];
  final _localResults = <GameSession>[];
  bool _pending = false;
  bool _disposed = false;
  String? actionError;
  @override
  GameSession? get localResult =>
      _afterAnimation == null && _localResults.isNotEmpty
      ? _localResults.first
      : null;
  @override
  String? get localPlayerId {
    final uid = connection.uid;
    if (uid == null) return null;
    final index = connection.room?.playerOrder.indexOf(uid) ?? -1;
    return index >= 0 && index < session.players.length
        ? session.players[index].id
        : null;
  }

  bool get canAct =>
      !_pending &&
      connection.privateViewReady &&
      _localResults.isEmpty &&
      connection.connected &&
      connection.room?.status == 'playing' &&
      connection.room!.hostAvailable &&
      !connection.room!.expired &&
      connection.room!.activeUid == connection.uid &&
      session.phase != TurnPhase.animating &&
      session.phase != TurnPhase.portalTravel;
  String get status {
    if (connection.room?.status == 'closed') return 'Room closed';
    if (session.phase == TurnPhase.completed) return 'Match finished';
    if (connection.room?.expired ?? false) {
      return 'Room expired. Create a new room.';
    }
    if (!connection.connected) return 'Reconnecting…';
    if (!connection.room!.hostAvailable) {
      return 'Waiting for the host to reconnect…';
    }
    if (actionError != null) return actionError!;
    if (!connection.privateViewReady) return 'Syncing your private details…';
    if (_pending) return 'Sending action…';
    return connection.room!.activeUid == connection.uid
        ? 'Your turn'
        : '${session.currentPlayer.name}’s turn';
  }

  void _receive() {
    final room = connection.room;
    if (room == null || _disposed) return;
    if (!connection.privateViewReady) {
      notifyListeners();
      return;
    }
    if (room.revision > _revision && room.state.isNotEmpty) {
      final previous = session;
      final next = connection.visibleSession!;
      _revision = room.revision;
      TurnOutcome? movement;
      var hasResults = false;
      var hasRecordedMove = false;
      if (connection.visibleOutcome.isNotEmpty) {
        final action =
            jsonDecode(connection.visibleOutcome) as Map<String, dynamic>;
        for (final result in action['results'] as List<dynamic>? ?? const []) {
          hasResults = true;
          _localResults.add(
            GameSession.fromJson(Map<String, dynamic>.from(result as Map)),
          );
        }
        if (action.containsKey('path')) {
          hasRecordedMove = true;
          movement = TurnOutcome(
            sequence: _revision,
            playerIndex: action['playerIndex'] as int,
            dice: action['dice'] as int,
            path: List<int>.from(action['path'] as List),
            description: action['description'] as String,
            landedType: TileType.values.byName(action['landedType'] as String),
            effectLabel: action['effectLabel'] as String,
            eventCardId: action['eventCardId'] as String?,
          );
        }
      }
      if (movement == null) {
        // Choices such as a free hospital restart can move a token too.
        for (var i = 0; i < next.players.length; i++) {
          if (previous.players[i].position != next.players[i].position) {
            movement = TurnOutcome(
              sequence: _revision,
              playerIndex: i,
              dice: next.lastDice ?? 1,
              path: [next.players[i].position],
              description: next.message,
              landedType: TileType.normal,
              effectLabel: '',
            );
            break;
          }
        }
      }
      // Keep special-tile decisions reviewable; ordinary movement needs no popup.
      if (!hasResults &&
          hasRecordedMove &&
          movement != null &&
          movement.path.isNotEmpty &&
          movement.landedType != TileType.normal &&
          movement.landedType != TileType.start &&
          movement.landedType != TileType.finish) {
        final review = GameSession.fromJson(next.toJson());
        review.currentPlayerIndex = movement.playerIndex;
        review.phase = TurnPhase.specialReview;
        final actor = review.currentPlayer;
        final from = previous.players[movement.playerIndex].position;
        final to = actor.position;
        final summary = next.currentPlayerIndex == movement.playerIndex
            ? next.tileSummary
            : null;
        review.tileSummary = TileSummary(
          title: summary?.title ?? '${actor.name} · MOVE RESULT',
          message:
              '${movement.description}\nMoved from space $from to space $to.',
          landedIndex: summary?.landedIndex ?? movement.path.last,
          finalPosition: to,
          changes: summary?.changes ?? const [],
        );
        _localResults.add(review);
      }
      session = next;
      if (_afterAnimation != null) {
        _afterAnimation = next.phase;
        if (movement?.path.isNotEmpty ?? false) {
          _queuedMovements.add(movement!);
        }
        session.phase = TurnPhase.animating;
      } else {
        lastOutcome = movement;
        if (movement?.path.isNotEmpty ?? false) {
          _afterAnimation = next.phase;
          session.phase = TurnPhase.animating;
        }
      }
      actionError = null;
    } else if (connection.privateViewReady && room.revision == _revision) {
      final next = connection.visibleSession;
      if (next != null) {
        session.hitmanOwnerId = next.hitmanOwnerId;
        session.hitmanTile = next.hitmanTile;
        if (session.currentPlayer.id == localPlayerId) {
          session.tileSummary = next.tileSummary;
        }
        for (var i = 0; i < session.players.length; i++) {
          if (session.players[i].id == localPlayerId) {
            session.players[i].cash = next.players[i].cash;
            session.players[i].debt = next.players[i].debt;
            final own = session.players[i].inventory;
            final updated = next.players[i].inventory;
            own.boats = updated.boats;
            own.antidotes = updated.antidotes;
            own.rawMeat = updated.rawMeat;
            own.healthPacks = updated.healthPacks;
            own.stabbers = updated.stabbers;
            own.pewPews = updated.pewPews;
            own.stars = updated.stars;
          }
        }
      }
    }
    notifyListeners();
  }

  void _send(String action, [Map<String, dynamic> args = const {}]) {
    if (!canAct) return;
    _pending = true;
    actionError = null;
    notifyListeners();
    unawaited(() async {
      try {
        await connection.send(action, args);
      } catch (_) {
        if (!_disposed) {
          actionError = 'Action not confirmed. Reconnect or try again.';
        }
      } finally {
        if (!_disposed) {
          _pending = false;
          notifyListeners();
        }
      }
    }());
  }

  @override
  bool get canChangePlayerIcon => false;
  @override
  void changePlayerIcon(PlayerIcon icon) {}

  @override
  int? beginDiceRoll() {
    if (!canAct || session.phase != TurnPhase.ready) return null;
    _send('roll');
    return null; // Host chooses the die; all clients animate its committed move.
  }

  @override
  TurnOutcome? resolveDiceRoll({bool offerAttackChoice = true}) => null;
  @override
  TurnOutcome? roll() {
    beginDiceRoll();
    return null;
  }

  @override
  void finishAnimation() {
    if (_afterAnimation == null) return;
    if (_queuedMovements.isNotEmpty) {
      lastOutcome = _queuedMovements.removeAt(0);
      notifyListeners();
      return;
    }
    session.phase = _afterAnimation!;
    _afterAnimation = null;
    notifyListeners();
  }

  @override
  void dismissLocalResult() {
    if (localResult == null) return;
    _localResults.removeAt(0);
    notifyListeners();
  }

  @override
  void chooseMovement() => _send('move');
  @override
  void dismissTileSummary() {
    if (localResult != null) {
      dismissLocalResult();
    } else {
      _send('review');
    }
  }

  @override
  void dismissEventCard() {
    if (localResult != null) {
      dismissLocalResult();
    } else {
      _send('event');
    }
  }

  @override
  void chooseHospitalTreatment({required bool pay}) =>
      _send('hospital', {'pay': pay});
  @override
  void useHealthPack() => _send('healthPack');
  @override
  void choosePolicePenalty({required bool payFine}) =>
      _send('police', {'pay': payFine});
  @override
  void choosePortalCard(int cardIndex) => _send('portal', {'card': cardIndex});
  @override
  bool buyWeapon(WeaponType type) {
    if (!canAct) return false;
    _send('buy', {'weapon': type.name});
    return true;
  }

  @override
  bool get canHireHitman => canAct && super.canHireHitman;
  @override
  List<int> get hitmanTargets => canAct ? super.hitmanTargets : const [];

  @override
  bool hireHitman(int tileIndex) {
    if (!canAct || !canHireHitman) return false;
    _send('hitmanHire', {'tile': tileIndex});
    return true;
  }

  @override
  bool useHitman(int targetIndex) {
    if (!canAct || !hitmanTargets.contains(targetIndex)) return false;
    _send('hitmanAttack', {'target': targetIndex});
    return true;
  }

  @override
  bool buyMedicalItem(MedicalItem item) {
    if (!canAct) return false;
    _send('medicalBuy', {'item': item.name});
    return true;
  }

  @override
  bool useWeapon(WeaponType type, int targetIndex) {
    if (!canAct) return false;
    _send('attack', {'weapon': type.name, 'target': targetIndex});
    return true;
  }

  @override
  void finishShopping() => _send('shopDone');
  @override
  void skipWeaponAction() => _send('endTurn');
  @override
  void acknowledgeHandoff() {} // The host advances directly to the next seat.
  @override
  void dispose() {
    _disposed = true;
    connection.removeListener(_receive);
    super.dispose();
  }
}
