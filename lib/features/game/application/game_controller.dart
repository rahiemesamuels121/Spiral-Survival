import 'dart:math';
import 'package:flutter/foundation.dart';
import '../domain/board_definition.dart';
import '../domain/event_card.dart';
import '../domain/game_session.dart';
import '../domain/player_state.dart';
import '../domain/tile_summary.dart';
import '../domain/weapon.dart';

typedef DiceRoller = int Function();

/// Immutable instruction delivered to the renderer after the dice animation.
class TurnOutcome {
  const TurnOutcome({
    required this.sequence,
    required this.playerIndex,
    required this.dice,
    required this.path,
    required this.description,
    required this.landedType,
    required this.effectLabel,
    this.eventCardId,
  });
  final int sequence;
  final int playerIndex;
  final int dice;
  final List<int> path;
  final String description;
  final TileType landedType;
  final String effectLabel;
  final String? eventCardId;
}

/// Authoritative local game logic. Flame and Flutter consume its state only.
class GameController extends ChangeNotifier {
  GameController({
    required this.session,
    required this.board,
    DiceRoller? diceRoller,
  }) : _rollDie = diceRoller ?? _secureRoll {
    if (session.boardId != board.id) {
      throw StateError('This save belongs to another board map.');
    }
    if (session.weaponRules.stabberPrice < 0 ||
        session.weaponRules.pewPewPrice < 0) {
      throw ArgumentError('Weapon prices cannot be negative');
    }
    for (final player in session.players) {
      if (player.position < 0 || player.position > board.lastIndex) {
        throw StateError('A saved player position is outside the board.');
      }
    }
    for (final card in [
      ...session.eventDrawPile,
      ...session.eventDiscardPile,
    ]) {
      EventCards.byId(card); // Invalid saved decks must be rejected.
    }
    if (session.pendingCardId != null) EventCards.byId(session.pendingCardId!);
    if (session.pendingPoliceFine != null &&
        board.tiles[session.currentPlayer.position].type != TileType.jail) {
      throw StateError('A police choice must take place at a jail.');
    }
    if (session.pendingShopTile != null &&
        (session.pendingShopTile! < 0 ||
            session.pendingShopTile! > board.lastIndex ||
            board.tiles[session.pendingShopTile!].type != TileType.shop ||
            session.currentPlayer.position != session.pendingShopTile)) {
      throw StateError('A shop visit must belong to a SHOP tile.');
    }
    if (session.pendingPortalTile != null &&
        (session.pendingPortalTile! < 0 ||
            session.pendingPortalTile! > board.lastIndex ||
            board.tiles[session.pendingPortalTile!].type != TileType.portal ||
            session.currentPlayer.position != session.pendingPortalTile ||
            session.portalCardDirections.length != 2 ||
            !session.portalCardDirections.contains(-1) ||
            !session.portalCardDirections.contains(1))) {
      throw StateError(
        'A portal choice requires two cards and a player on a portal.',
      );
    }
  }

  factory GameController.newGame({
    required List<String> names,
    required List<int> colors,
    required BoardDefinition board,
    DiceRoller? diceRoller,
    List<String>? eventCardOrder,
    WeaponRules weaponRules = const WeaponRules(),
  }) {
    if (names.length < 2 || names.length > 5 || colors.length < names.length) {
      throw ArgumentError('Provide 2 to 5 player names and matching colors');
    }
    if (names.any((name) => name.trim().isEmpty)) {
      throw ArgumentError('Player names must not be empty');
    }
    final deck =
        eventCardOrder?.toList() ??
        (EventCards.all.map((card) => card.id).toList()
          ..shuffle(Random.secure()));
    if (deck.isEmpty) throw ArgumentError('Event deck cannot be empty');
    for (final cardId in deck) {
      EventCards.byId(cardId);
    }
    return GameController(
      session: GameSession(
        boardId: board.id,
        players: [
          for (var i = 0; i < names.length; i++)
            PlayerState(
              id: 'p${i + 1}',
              name: names[i].trim(),
              colorValue: colors[i],
            ),
        ],
        eventDrawPile: deck,
        weaponRules: weaponRules,
      ),
      board: board,
      diceRoller: diceRoller,
    );
  }

  final GameSession session;
  final BoardDefinition board;
  final DiceRoller _rollDie;
  int _sequence = 0;
  bool _policeArrestThisResolution = false;
  TurnOutcome? lastOutcome;

  static int _secureRoll() => Random.secure().nextInt(6) + 1;

  /// Phase 1. Lock the turn and choose one die result; no token moves yet.
  int? beginDiceRoll() {
    if (session.phase != TurnPhase.ready || session.winnerId != null) {
      return null;
    }
    final dice = _rollDie();
    if (dice < 1 || dice > 6) {
      throw StateError('A six-sided die must produce 1..6');
    }
    session.lastDice = dice;
    session.weaponActionTaken = false;
    session.pendingShopTile = null;
    session.pendingPortalTile = null;
    session.portalCardDirections.clear();
    session.phase = TurnPhase.rolling;
    notifyListeners();
    return dice;
  }

  /// Phase 2. Called by Flutter after the visual dice animation ends.
  TurnOutcome? resolveDiceRoll({bool offerSameTileChoice = true}) {
    if (session.phase != TurnPhase.rolling) return null;
    final dice = session.lastDice!;
    if (offerSameTileChoice &&
        dice > 3 &&
        session.currentPlayer.inventory.hasWeapons &&
        _nearbyPolice(session.currentPlayer.position) == null &&
        session.players.asMap().entries.any(
          (entry) =>
              entry.key != session.currentPlayerIndex &&
              entry.value.position == session.currentPlayer.position,
        )) {
      session.phase = TurnPhase.preMoveWeaponChoice;
      notifyListeners();
      return null;
    }
    _policeArrestThisResolution = false;
    final playerIndex = session.currentPlayerIndex;
    final player = session.currentPlayer;
    final backwards = player.reverseNextMove;
    final remaining = board.lastIndex - player.position;
    if (!backwards && dice > remaining) {
      session.message =
          '${player.name} rolled $dice, but only $remaining space(s) remain. '
          'Roll $remaining to finish, or less to move. You stay on tile ${player.position}.';
      session.weaponActionTaken = true;
      session.tileSummary = null;
      session.phase = TurnPhase.animating;
      lastOutcome = TurnOutcome(
        sequence: ++_sequence,
        playerIndex: playerIndex,
        dice: dice,
        path: const [],
        description: session.message,
        landedType: TileType.normal,
        effectLabel: 'EXACT ROLL NEEDED',
      );
      notifyListeners();
      return lastOutcome;
    }
    player.reverseNextMove = false;
    final cashBefore = player.cash;
    final debtBefore = player.debt;
    final boatsBefore = player.inventory.boats;
    final antidotesBefore = player.inventory.antidotes;
    final meatBefore = player.inventory.rawMeat;
    final stabbersBefore = player.inventory.stabbers;
    final pewPewsBefore = player.inventory.pewPews;
    final starsBefore = player.inventory.stars;
    final skipsBefore = player.skipTurns;
    final path = <int>[];
    final start = player.position;
    if (player.inventory.hasPoliceRisk && _nearbyPolice(start) != null) {
      path.add(start);
    } else {
      for (var i = 1; i <= dice; i++) {
        final next = backwards ? max(start - i, 0) : start + i;
        if (path.isEmpty || path.last != next) path.add(next);
        if (next == 0 ||
            next == board.lastIndex ||
            player.inventory.hasPoliceRisk && _nearbyPolice(next) != null) {
          break;
        }
      }
    }
    player.position = path.last;
    final effectTile = board.tiles[player.position];
    final effectMessage = _resolveLandingEffects(player, path);
    if (player.position >= board.lastIndex) {
      session.winnerId = player.id;
    }
    session.message =
        '${player.name} rolled $dice. '
        '${backwards ? 'CONFUSION: moving backwards this turn. ' : ''}$effectMessage';
    final changes = <String>[];
    void record(String name, int before, int after, {bool money = false}) {
      if (before == after) return;
      final delta = after - before;
      changes.add(
        '$name: ${delta > 0 ? '+' : '−'}${money ? '\$' : ''}${delta.abs()} '
        '($before → $after)',
      );
    }

    record('Cash', cashBefore, player.cash, money: true);
    record('Debt', debtBefore, player.debt, money: true);
    record('Boats', boatsBefore, player.inventory.boats);
    record('Antidotes', antidotesBefore, player.inventory.antidotes);
    record('Raw meat', meatBefore, player.inventory.rawMeat);
    record('Stabbers', stabbersBefore, player.inventory.stabbers);
    record('Pew pews', pewPewsBefore, player.inventory.pewPews);
    record('Stars', starsBefore, player.inventory.stars);
    record('Turns to miss', skipsBefore, player.skipTurns);
    if (backwards) changes.add('Confusion: backwards move used');
    if (player.reverseNextMove) changes.add('Next move: BACKWARDS');
    final policeCaught =
        _policeArrestThisResolution || session.pendingPoliceFine != null;
    final diedOnMine =
        player.position == 0 &&
        path.length >= 2 &&
        board.tiles[path[path.length - 2]].type == TileType.mine;
    session.tileSummary =
        !diedOnMine &&
            !policeCaught &&
            (effectTile.type == TileType.normal ||
                effectTile.type == TileType.start ||
                effectTile.type == TileType.finish)
        ? null
        : TileSummary(
            title: diedOnMine
                ? 'MINE · YOU DIED'
                : policeCaught
                ? 'POLICE'
                : backwards && effectTile.type == TileType.normal
                ? 'CONFUSION'
                : effectTile.label.isEmpty
                ? effectTile.typeLabel
                : effectTile.label,
            message: session.message,
            landedIndex: diedOnMine ? path[path.length - 2] : effectTile.index,
            finalPosition: player.position,
            changes: List.unmodifiable(changes),
          );
    session.phase = TurnPhase.animating;
    lastOutcome = TurnOutcome(
      sequence: ++_sequence,
      playerIndex: playerIndex,
      dice: dice,
      path: List.unmodifiable(path),
      description: session.message,
      landedType: diedOnMine
          ? TileType.mine
          : policeCaught
          ? TileType.police
          : effectTile.type,
      effectLabel: policeCaught
          ? 'POLICE · GO TO JAIL'
          : effectTile.label.isEmpty
          ? effectTile.type.name
          : effectTile.label,
      eventCardId: session.pendingCardId,
    );
    notifyListeners();
    return lastOutcome;
  }

  /// Convenience entry point for pure-Dart rules tests; UI uses both phases.
  TurnOutcome? roll() {
    if (beginDiceRoll() == null) return null;
    return resolveDiceRoll();
  }

  EventCard _drawCard() {
    if (session.eventDrawPile.isEmpty) {
      // Recycle the discard pile only after the full current deck is used.
      final refill = session.eventDiscardPile.isEmpty
          ? EventCards.all.map((card) => card.id).toList()
          : session.eventDiscardPile.toList();
      refill.shuffle(Random.secure());
      session.eventDrawPile.addAll(refill);
      session.eventDiscardPile.clear();
    }
    final id = session.eventDrawPile.removeLast();
    session.eventDiscardPile.add(id);
    return EventCards.byId(id);
  }

  String _resolveLandingEffects(PlayerState player, List<int> path) {
    final visited = <int>{};
    final messages = <String>[];
    while (visited.add(player.position)) {
      final nearby = player.inventory.hasPoliceRisk
          ? _nearbyPolice(player.position)
          : null;
      if (nearby != null) {
        messages.add(_arrestForContraband(player, nearby, path));
        return messages.join(' ');
      }
      final tile = board.tiles[player.position];
      if (tile.type == TileType.event && session.pendingCardId != null) {
        messages.add(
          'Another EVENT tile reached; only one event card is drawn per turn.',
        );
        return messages.join(' ');
      }
      final from = player.position;
      messages.add(_applyEffect(player, tile, path));
      if (player.inventory.hasPoliceRisk) {
        final police = _nearbyPolice(player.position);
        if (police != null) {
          messages.add(_arrestForContraband(player, police, path));
          return messages.join(' ');
        }
      }
      // Police has a pending choice, go-to-jail already applies its penalty,
      // and snake return explicitly collects its antidote. Do not apply those
      // arrival effects twice.
      if (player.position == from ||
          session.pendingPoliceFine != null ||
          _policeArrestThisResolution ||
          tile.type == TileType.police ||
          tile.type == TileType.goToJail ||
          tile.type == TileType.snake) {
        return messages.join(' ');
      }
    }
    messages.add(
      'This tile was already resolved this turn; the movement loop stops here.',
    );
    return messages.join(' ');
  }

  String _applyEffect(PlayerState player, BoardTile tile, List<int> path) {
    switch (tile.type) {
      case TileType.sea:
        if (player.inventory.boats > 0) {
          var destination = tile.index;
          do {
            destination++;
            path.add(destination);
            if (player.inventory.hasPoliceRisk) {
              final police = _nearbyPolice(destination);
              if (police != null) {
                player.position = destination;
                return _arrestForContraband(player, police, path);
              }
            }
          } while (board.tiles[destination].type == TileType.sea);
          player.position = destination;
          return 'SEA: your boat carried you safely to space $destination, '
              'after the sea. Your boat stays in your inventory.';
        }
        player.position = 0;
        session.weaponActionTaken = true;
        path.add(0);
        return 'SEA: No boat, you drowned. You returned to START. Your turn is over.';
      case TileType.boat:
        final count = tile.amount > 0 ? tile.amount : 1;
        player.inventory.boats += count;
        return 'Collected $count boat(s). Added to inventory.';
      case TileType.antidote:
        final count = tile.amount > 0 ? tile.amount : 1;
        player.inventory.antidotes += count;
        return 'Collected $count antidote(s). Added to inventory.';
      case TileType.rawMeat:
        final count = tile.amount > 0 ? tile.amount : 1;
        player.inventory.rawMeat += count;
        return 'RAW MEAT: collected $count portion(s) to feed lions.';
      case TileType.lion:
        if (player.inventory.rawMeat > 0) {
          player.inventory.rawMeat--;
          return 'LION: fed the lion one raw meat. You are safe!';
        }
        player.position = tile.destination!;
        path.add(player.position);
        return 'LION: No raw meat, the lion attacked you. Go to HOSPITAL.';
      case TileType.snake:
        if (player.inventory.antidotes > 0) {
          if (tile.consumesAntidote) player.inventory.antidotes--;
          return tile.consumesAntidote
              ? 'SNAKE: used one antidote. You are safe!'
              : 'SNAKE: your antidote protects you.';
        }
        player.position = tile.destination!;
        path.add(player.position);
        final pickup = board.tiles[player.position];
        final count = pickup.amount > 0 ? pickup.amount : 1;
        player.inventory.antidotes += count;
        return 'SNAKE: No antidote, the snake bit you. Returned to space ${player.position} '
            'and collected $count antidote(s).';
      case TileType.start:
      case TileType.normal:
        return tile.label.isEmpty
            ? 'Normal space.'
            : 'Landed on ${tile.label}.';
      case TileType.cash:
        player.cash += tile.amount;
        return 'Collected \$${tile.amount}!';
      case TileType.police:
        final fine = tile.amount == 0 ? 20 : tile.amount;
        final destination = _nearestJail(tile.index);
        player.position = destination;
        path.add(destination);
        session.pendingPoliceFine = fine;
        session.weaponActionTaken = true;
        session.pendingShopTile = null;
        return 'POLICE: caught and moved to the nearest JAIL at space $destination.';
      case TileType.fine:
        final fine = tile.amount == 0 ? 20 : tile.amount;
        player.pay(fine);
        return '\$$fine fine charged; unpaid balance becomes debt.';
      case TileType.jail:
        session.weaponActionTaken = true;
        final turns = tile.amount > 0 ? tile.amount : 1;
        player.skipTurns += turns;
        return 'JAIL: miss $turns turn(s).';
      case TileType.goToJail:
        return _sendToJail(player, tile.destination!, path);
      case TileType.mine:
        player.position = 0;
        path.add(0);
        session.weaponActionTaken = true;
        return 'MINE: The mine exploded; you died. You returned to START. Your turn is over.';
      case TileType.portal:
        session.pendingPortalTile = tile.index;
        session.portalCardDirections
          ..clear()
          ..addAll(<int>[-1, 1]..shuffle(Random.secure()));
        return 'PORTAL: tap one of two mystery cards to reveal your destination.';
      case TileType.setBack:
        final destination = max(
          0,
          player.position - (tile.amount == 0 ? 3 : tile.amount),
        );
        final arrest = _moveForEffect(player, destination, path);
        return arrest ?? 'Moved back to space ${player.position}.';
      case TileType.moveForward:
        final spaces = tile.amount == 0 ? 2 : tile.amount;
        if (player.position + spaces > board.lastIndex) {
          return 'Cannot advance $spaces spaces past FINISH. Stay on space ${player.position}.';
        }
        final destination = min(
          board.lastIndex,
          player.position + (tile.amount == 0 ? 2 : tile.amount),
        );
        final arrest = _moveForEffect(player, destination, path);
        return arrest ?? 'Moved forward to space ${player.position}.';
      case TileType.shop:
        session.pendingShopTile = tile.index;
        return 'SHOP: choose whether to buy a Stabber or Pew pew. No entry fee.';
      case TileType.event:
        final card = _drawCard();
        session.pendingCardId = card.id;
        final result = _applyCard(player, card, path);
        return 'EVENT CARD: ${card.title}. $result';
      case TileType.confusion:
        player.reverseNextMove = true;
        return 'CONFUSION: your next dice move goes backwards instead of forwards.';
      case TileType.star:
        final count = tile.amount > 0 ? tile.amount : 1;
        player.inventory.stars += count;
        player.cash += 25;
        return 'Collected $count star(s) and a \$25 bonus. '
            'Carrying stars within 3 spaces of POLICE causes a jail sentence.';
      case TileType.hospital:
        session.weaponActionTaken = true;
        if (player.cash < 10) {
          player.position = 0;
          path.add(0);
          return 'HOSPITAL: Treatment costs 10 coins. You do not have enough coins, so you returned to START. Your turn is over.';
        }
        session.pendingHospital = true;
        return 'HOSPITAL: Pay 10 coins for treatment, or restart at START for free.';
      case TileType.fire:
      case TileType.trapDoor:
        final trap = tile.type == TileType.trapDoor;
        if (trap) player.skipTurns++;
        player.position = tile.destination!;
        path.add(player.position);
        session.weaponActionTaken = true;
        return trap
            ? 'TRAP DOOR: miss one turn and go to HOSPITAL at space ${player.position}.'
            : 'FIRE: sent straight to HOSPITAL at space ${player.position}.';
      case TileType.finish:
        return 'Finished the board!';
    }
  }

  int _nearestJail(int from) {
    int? nearest;
    for (final tile in board.tiles) {
      if (tile.type != TileType.jail) continue;
      if (nearest == null ||
          (tile.index - from).abs() < (nearest - from).abs()) {
        nearest = tile.index;
      }
    }
    if (nearest != null) return nearest;
    throw StateError('POLICE requires a JAIL tile on the board.');
  }

  String? _moveForEffect(PlayerState player, int destination, List<int> path) {
    if (player.inventory.hasPoliceRisk && destination != player.position) {
      final step = destination > player.position ? 1 : -1;
      while (player.position != destination) {
        player.position += step;
        path.add(player.position);
        final police = _nearbyPolice(player.position);
        if (police != null) return _arrestForContraband(player, police, path);
      }
    } else {
      player.position = destination;
      path.add(destination);
    }
    return null;
  }

  BoardTile? _nearbyPolice(int from) {
    BoardTile? nearest;
    for (final tile in board.tiles) {
      if (tile.type == TileType.police &&
          (tile.index - from).abs() <= 3 &&
          (nearest == null ||
              (tile.index - from).abs() < (nearest.index - from).abs())) {
        nearest = tile;
      }
    }
    return nearest;
  }

  String _arrestForContraband(
    PlayerState player,
    BoardTile police,
    List<int> path,
  ) {
    final destination = _nearestJail(player.position);
    _policeArrestThisResolution = true;
    final stars = player.inventory.stars;
    final hadWeapons = player.inventory.hasWeapons;
    player.inventory.stars = 0;
    player.inventory.stabbers = 0;
    player.inventory.pewPews = 0;
    player.position = destination;
    path.add(destination);
    session.pendingPoliceFine = stars > 0
        ? null
        : police.amount == 0
        ? 20
        : police.amount;
    if (stars > 0) player.skipTurns += stars;
    session.pendingShopTile = null;
    session.weaponActionTaken = true;
    if (stars > 0) {
      return 'POLICE: caught with $stars star(s) within 3 spaces of police tile ${police.index}. '
          'Moved to JAIL at space $destination. Miss $stars turn(s). Stars cleared.'
          '${hadWeapons ? ' All weapons were confiscated.' : ''}';
    }
    return 'POLICE: carrying weapons within 3 spaces of police tile ${police.index}. '
        'All weapons were confiscated. Moved to JAIL at space $destination.';
  }

  String _sendToJail(PlayerState player, int destination, List<int> path) {
    session.weaponActionTaken = true;
    player.position = destination;
    path.add(destination);
    if (player.inventory.hasPoliceRisk) {
      final police = _nearbyPolice(destination);
      if (police != null) return _arrestForContraband(player, police, path);
    }
    final jail = board.tiles[destination];
    final turns = jail.amount > 0 ? jail.amount : 1;
    player.skipTurns += turns;
    return 'GO TO JAIL: moved to space $destination. Miss $turns turn(s).';
  }

  String _applyCard(PlayerState player, EventCard card, List<int> path) {
    switch (card.effect) {
      case EventEffect.receiveCash:
        player.cash += card.value;
        return 'Collected \$${card.value}.';
      case EventEffect.payFine:
        player.pay(card.value);
        return 'Paid \$${card.value} (or added unpaid amount to debt).';
      case EventEffect.forward:
        if (player.position + card.value > board.lastIndex) {
          return 'Cannot advance ${card.value} spaces past FINISH. Stay on space ${player.position}.';
        }
        final destination = min(board.lastIndex, player.position + card.value);
        return _moveForEffect(player, destination, path) ??
            'Advanced ${card.value} spaces.';
      case EventEffect.backward:
        final destination = max(0, player.position - card.value);
        return _moveForEffect(player, destination, path) ??
            'Retreated ${card.value} spaces.';
      case EventEffect.skipTurn:
        player.skipTurns += card.value;
        return 'Will miss ${card.value} turn(s).';
      case EventEffect.repayDebt:
        player.debt = max(0, player.debt - card.value);
        return 'Debt reduced by up to \$${card.value}.';
    }
  }

  /// Flame calls this only when all movement frames have played.
  void finishAnimation() {
    if (session.phase != TurnPhase.animating &&
        session.phase != TurnPhase.portalTravel) {
      return;
    }
    if (session.pendingCardId != null) {
      session.phase = TurnPhase.eventReveal;
      notifyListeners();
      return;
    }
    if (session.pendingHospital) {
      session.phase = TurnPhase.hospitalChoice;
      notifyListeners();
      return;
    }
    if (session.pendingPoliceFine != null) {
      session.phase = TurnPhase.jailChoice;
      notifyListeners();
      return;
    }
    if (session.pendingPortalTile != null) {
      session.phase = TurnPhase.portalChoice;
      notifyListeners();
      return;
    }
    if (session.pendingShopTile != null) {
      session.phase = TurnPhase.shopping;
      notifyListeners();
      return;
    }
    if (session.tileSummary != null) {
      session.phase = TurnPhase.specialReview;
      notifyListeners();
      return;
    }
    _offerWeaponActionOrComplete();
  }

  void chooseHospitalTreatment({required bool pay}) {
    if (session.phase != TurnPhase.hospitalChoice) return;
    final player = session.currentPlayer;
    if (pay && player.cash < 10) return;
    session.pendingHospital = false;
    if (pay) {
      player.cash -= 10;
      session.message =
          'HOSPITAL: You paid 10 coins for treatment. Stay at HOSPITAL. Your turn is over.';
    } else {
      player.position = 0;
      session.message =
          'HOSPITAL: You chose to restart at START. No coins were charged. Your turn is over.';
    }
    final previous = session.tileSummary;
    session.tileSummary = TileSummary(
      title: pay ? 'HOSPITAL · TREATED' : 'HOSPITAL · RESTART',
      message: session.message,
      landedIndex: previous?.landedIndex ?? player.position,
      finalPosition: player.position,
      changes: [
        ...?previous?.changes,
        if (pay) 'Treatment: −10 coins' else 'Returned to START',
      ],
    );
    session.phase = TurnPhase.specialReview;
    notifyListeners();
  }

  void dismissTileSummary() {
    if (session.phase != TurnPhase.specialReview) return;
    session.tileSummary = null;
    _offerWeaponActionOrComplete();
  }

  void dismissEventCard() {
    if (session.phase != TurnPhase.eventReveal) return;
    session.pendingCardId = null;
    if (session.pendingHospital) {
      session.phase = TurnPhase.hospitalChoice;
      notifyListeners();
      return;
    }
    if (session.pendingPoliceFine != null) {
      session.phase = TurnPhase.jailChoice;
      notifyListeners();
      return;
    }
    if (session.pendingPortalTile != null) {
      session.phase = TurnPhase.portalChoice;
      notifyListeners();
      return;
    }
    if (session.pendingShopTile != null) {
      session.phase = TurnPhase.shopping;
      notifyListeners();
      return;
    }
    session.tileSummary = null;
    _offerWeaponActionOrComplete();
  }

  int? _closestPortal(int from, int direction) {
    for (
      var index = from + direction;
      index >= 0 && index <= board.lastIndex;
      index += direction
    ) {
      if (board.tiles[index].type == TileType.portal) return index;
    }
    return null;
  }

  void choosePortalCard(int cardIndex) {
    if (session.phase != TurnPhase.portalChoice ||
        cardIndex < 0 ||
        cardIndex > 1) {
      return;
    }
    final origin = session.pendingPortalTile!;
    final chosenDirection = session.portalCardDirections[cardIndex];
    final preferred = _closestPortal(origin, chosenDirection);
    final destination = preferred ?? _closestPortal(origin, -chosenDirection);
    session.pendingPortalTile = null;
    session.portalCardDirections.clear();
    final chosenName = chosenDirection < 0 ? 'BACKWARDS' : 'FORWARDS';
    final player = session.currentPlayer;
    final old = session.tileSummary;
    session.message = '${player.name} revealed $chosenName. ';
    if (destination == null) {
      session.message +=
          'There is no other portal, so you stay on tile $origin.';
    } else {
      final actualName = destination < origin ? 'backwards' : 'forwards';
      session.message +=
          '${preferred == null ? 'No portal in that direction; use the other direction. ' : ''}'
          'Travel $actualName to the closest portal at tile $destination.';
      player.position = destination;
    }
    session.tileSummary = TileSummary(
      title: 'MYSTERY PORTAL · $chosenName',
      message: session.message,
      landedIndex: origin,
      finalPosition: player.position,
      changes: [
        ...?old?.changes,
        'Mystery card: $chosenName',
        if (destination != null) 'Portal: tile $origin → $destination',
      ],
    );
    if (destination == null) {
      session.phase = TurnPhase.specialReview;
      notifyListeners();
      return;
    }
    final nearby = player.inventory.hasPoliceRisk
        ? _nearbyPolice(destination)
        : null;
    if (nearby != null) {
      _animateContrabandArrest(
        nearby,
        leadingPath: [destination],
        commitPortalTravel: true,
      );
      return;
    }
    // Arrival does not draw another pair of cards on the same turn.
    session.phase = TurnPhase.portalTravel;
    lastOutcome = TurnOutcome(
      sequence: ++_sequence,
      playerIndex: session.currentPlayerIndex,
      dice: session.lastDice!,
      path: [destination],
      description: session.message,
      landedType: TileType.portal,
      effectLabel: chosenName,
    );
    notifyListeners();
  }

  int weaponCount(WeaponType type) => type == WeaponType.stabber
      ? session.currentPlayer.inventory.stabbers
      : session.currentPlayer.inventory.pewPews;

  List<int> _targetsFor(WeaponType type) {
    if (session.winnerId != null ||
        session.weaponActionTaken ||
        session.lastDice != 6 ||
        weaponCount(type) < 1) {
      return const [];
    }
    final from = session.currentPlayer.position;
    return [
      for (var i = 0; i < session.players.length; i++)
        if (i != session.currentPlayerIndex &&
            session.players[i].position > 0 &&
            (session.players[i].position - from).abs() <= type.range)
          i,
    ];
  }

  List<int> weaponTargets(WeaponType type) {
    if (session.phase == TurnPhase.preMoveWeaponChoice) {
      if ((session.lastDice ?? 0) <= 3 ||
          weaponCount(type) < 1 ||
          session.weaponActionTaken) {
        return const [];
      }
      return [
        for (var i = 0; i < session.players.length; i++)
          if (i != session.currentPlayerIndex &&
              session.players[i].position == session.currentPlayer.position)
            i,
      ];
    }
    return session.phase == TurnPhase.weaponAction
        ? _targetsFor(type)
        : const [];
  }

  void chooseMovement() {
    if (session.phase != TurnPhase.preMoveWeaponChoice) return;
    session.phase = TurnPhase.rolling;
    resolveDiceRoll(offerSameTileChoice: false);
  }

  void _offerWeaponActionOrComplete() {
    final nearby = session.currentPlayer.inventory.hasPoliceRisk
        ? _nearbyPolice(session.currentPlayer.position)
        : null;
    if (nearby != null) {
      _animateContrabandArrest(nearby);
      return;
    }
    if (WeaponType.values.any((type) => _targetsFor(type).isNotEmpty)) {
      session.phase = TurnPhase.weaponAction;
      notifyListeners();
    } else {
      _completeTurn();
    }
  }

  void skipWeaponAction() {
    if (session.phase != TurnPhase.weaponAction) return;
    final nearby = session.currentPlayer.inventory.hasPoliceRisk
        ? _nearbyPolice(session.currentPlayer.position)
        : null;
    if (nearby != null) {
      _animateContrabandArrest(nearby);
      return;
    }
    session.weaponActionTaken = true;
    session.tileSummary = null;
    _completeTurn();
  }

  void finishShopping() {
    if (session.phase != TurnPhase.shopping) return;
    session.pendingShopTile = null;
    if (session.tileSummary != null) {
      session.phase = TurnPhase.specialReview;
      notifyListeners();
    } else {
      _offerWeaponActionOrComplete();
    }
  }

  bool buyWeapon(WeaponType type) {
    if (session.phase != TurnPhase.shopping) return false;
    final player = session.currentPlayer;
    final price = session.weaponRules.price(type);
    if (player.cash < price) return false;
    final beforeCash = player.cash;
    final beforeCount = weaponCount(type);
    player.cash -= price;
    if (type == WeaponType.stabber) {
      player.inventory.stabbers++;
    } else {
      player.inventory.pewPews++;
    }
    session.message += ' Bought a ${type.label} for \$$price.';
    final old = session.tileSummary;
    session.tileSummary = TileSummary(
      title: 'WEAPON SHOP',
      message: session.message,
      landedIndex: old?.landedIndex ?? player.position,
      finalPosition: player.position,
      changes: [
        ...?old?.changes,
        'Cash: −\$$price ($beforeCash → ${player.cash})',
        '${type.label}: +1 ($beforeCount → ${weaponCount(type)})',
      ],
    );
    final nearby = _nearbyPolice(player.position);
    if (nearby != null) {
      _animateContrabandArrest(nearby);
    } else {
      notifyListeners();
    }
    return true;
  }

  void _animateContrabandArrest(
    BoardTile police, {
    List<int> leadingPath = const [],
    bool commitPortalTravel = false,
  }) {
    final player = session.currentPlayer;
    final beforeStabbers = player.inventory.stabbers;
    final beforePewPews = player.inventory.pewPews;
    final beforeStars = player.inventory.stars;
    final beforeSkips = player.skipTurns;
    final from = player.position;
    final path = <int>[...leadingPath];
    session.message += ' ${_arrestForContraband(player, police, path)}';
    final old = session.tileSummary;
    session.tileSummary = TileSummary(
      title: 'POLICE',
      message: session.message,
      landedIndex: old?.landedIndex ?? from,
      finalPosition: player.position,
      changes: [
        ...?old?.changes,
        if (beforeStabbers > 0)
          'Stabbers: −$beforeStabbers ($beforeStabbers → 0)',
        if (beforePewPews > 0) 'Pew pews: −$beforePewPews ($beforePewPews → 0)',
        if (beforeStars > 0) 'Stars: −$beforeStars ($beforeStars → 0)',
        if (player.skipTurns != beforeSkips)
          'Turns to miss: +${player.skipTurns - beforeSkips} ($beforeSkips → ${player.skipTurns})',
      ],
    );
    session.phase = commitPortalTravel
        ? TurnPhase.portalTravel
        : TurnPhase.animating;
    lastOutcome = TurnOutcome(
      sequence: ++_sequence,
      playerIndex: session.currentPlayerIndex,
      dice: session.lastDice ?? 1,
      path: List.unmodifiable(path),
      description: session.message,
      landedType: TileType.police,
      effectLabel: beforeStars > 0
          ? 'STARS · JAIL SENTENCE'
          : 'WEAPONS CONFISCATED',
    );
    notifyListeners();
  }

  bool useWeapon(WeaponType type, int targetIndex) {
    if ((session.phase != TurnPhase.weaponAction &&
            session.phase != TurnPhase.preMoveWeaponChoice) ||
        !weaponTargets(type).contains(targetIndex)) {
      return false;
    }
    final nearby = _nearbyPolice(session.currentPlayer.position);
    if (nearby != null) {
      _animateContrabandArrest(nearby);
      return true;
    }
    final target = session.players[targetIndex];
    final from = target.position;
    final countBefore = weaponCount(type);
    if (type == WeaponType.stabber) {
      session.currentPlayer.inventory.stabbers--;
    } else {
      session.currentPlayer.inventory.pewPews--;
    }
    target.position = 0;
    session.weaponActionTaken = true;
    session.message =
        '${session.currentPlayer.name} used a ${type.label} on ${target.name}. '
        '${target.name} returned to START. One ${type.label} was used up.';
    session.tileSummary = TileSummary(
      title: type.label.toUpperCase(),
      message: session.message,
      landedIndex: session.currentPlayer.position,
      finalPosition: session.currentPlayer.position,
      changes: [
        '${type.label}: −1 ($countBefore → ${weaponCount(type)})',
        '${target.name}: tile $from → START',
      ],
    );
    session.phase = TurnPhase.animating;
    lastOutcome = TurnOutcome(
      sequence: ++_sequence,
      playerIndex: targetIndex,
      dice: session.lastDice!,
      path: const [0],
      description: session.message,
      landedType: TileType.normal,
      effectLabel: type.label,
    );
    notifyListeners();
    return true;
  }

  /// The arrest moves the player immediately; exactly one penalty is chosen
  /// after movement. Paying requires cash and never adds debt or a missed turn.
  void choosePolicePenalty({required bool payFine}) {
    if (session.phase != TurnPhase.jailChoice) return;
    final fine = session.pendingPoliceFine!;
    final player = session.currentPlayer;
    if (payFine && player.cash < fine) return;
    final changes = [...?session.tileSummary?.changes];
    if (payFine) {
      final before = player.cash;
      player.cash -= fine;
      changes.add('Cash: −\$$fine ($before → ${player.cash})');
      session.message += ' Paid the \$$fine fine; no turn is missed.';
    } else {
      final before = player.skipTurns;
      player.skipTurns++;
      changes.add('Turns to miss: +1 ($before → ${player.skipTurns})');
      session.message += ' Chose to miss one turn; no fine was charged.';
    }
    final previous = session.tileSummary;
    session.tileSummary = TileSummary(
      title: previous?.title ?? 'POLICE',
      message: session.message,
      landedIndex: previous?.landedIndex ?? player.position,
      finalPosition: player.position,
      changes: List.unmodifiable(changes),
    );
    session.pendingPoliceFine = null;
    session.phase = TurnPhase.specialReview;
    notifyListeners();
  }

  void _completeTurn() {
    if (session.winnerId != null) {
      session.phase = TurnPhase.completed;
      notifyListeners();
      return;
    }
    final skipped = _advanceToEligiblePlayer();
    session.handoffMessage = skipped.isEmpty
        ? 'Previous turn complete. Keep the board hidden until ready.'
        : '${skipped.join(', ')} missed a turn. Pass the device to the next player.';
    session.phase = TurnPhase.handoff;
    notifyListeners();
  }

  void acknowledgeHandoff() {
    if (session.phase != TurnPhase.handoff) return;
    session.phase = TurnPhase.ready;
    session.message =
        '${session.currentPlayer.name}, it is your turn. Roll the dice!';
    notifyListeners();
  }

  List<String> _advanceToEligiblePlayer() {
    final skipped = <String>[];
    final total = session.players.length;
    var next = session.currentPlayerIndex;
    // Each forfeited turn counts as a full player slot, including when every
    // player is jailed. The bounded sum ensures no endless skip scan.
    final maxAttempts =
        total +
        session.players.fold<int>(0, (sum, player) => sum + player.skipTurns);
    for (var attempt = 0; attempt < maxAttempts; attempt++) {
      next = (next + 1) % total;
      if (next == 0) session.round++;
      final player = session.players[next];
      if (player.skipTurns > 0) {
        player.skipTurns--;
        skipped.add(player.name);
        continue;
      }
      session.currentPlayerIndex = next;
      return skipped;
    }
    throw StateError('No eligible player found after skip-turn resolution.');
  }
}
