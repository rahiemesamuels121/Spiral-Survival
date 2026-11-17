import '../domain/hospital_stock.dart';
import 'dart:math';
import 'package:flutter/foundation.dart';
import '../domain/board_definition.dart';
import '../domain/event_card.dart';
import '../domain/game_session.dart';
import '../domain/medical_item.dart';
import '../domain/player_state.dart';
import '../domain/player_icon.dart';
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
    DateTime Function()? clock,
  }) : _clock = clock ?? DateTime.now,
       _rollDie = diceRoller ?? _secureRoll {
    if (session.computerPlayerIds.isNotEmpty &&
            session.computerPlayerIds.length != session.players.length - 1 ||
        session.computerPlayerIds.any(
          (id) => !session.players.any((p) => p.id == id),
        )) {
      throw ArgumentError('Computer games require exactly one human player.');
    }
    if (session.boardId != board.id) {
      throw StateError('This save belongs to another board map.');
    }
    if (session.weaponRules.stabberPrice < 0 ||
        session.weaponRules.pewPewPrice < 0) {
      throw ArgumentError('Weapon prices cannot be negative');
    }
    final now = _clock();
    for (final tile in board.tiles.where((t) => t.type == TileType.hospital)) {
      session.hospitalStocks.putIfAbsent(
        tile.index,
        () => HospitalStock(updatedAt: now),
      );
    }
    if (session.hospitalStocks.keys.any(
      (index) =>
          index < 0 ||
          index > board.lastIndex ||
          board.tiles[index].type != TileType.hospital,
    )) {
      throw StateError('Hospital supplies must belong to a hospital.');
    }
    if ((session.hitmanOwnerId == null) != (session.hitmanTile == null) ||
        session.hitmanTile != null &&
            (!session.hitmanHired ||
                session.hitmanTile! < 0 ||
                session.hitmanTile! > board.lastIndex ||
                !session.players.any((p) => p.id == session.hitmanOwnerId))) {
      throw StateError('Invalid hitman contract.');
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
    if (session.pendingPoliceFine != null) {
      final position = session.currentPlayer.position;
      // Older saves already moved the token to jail before offering payment.
      // Keep that recorded location; the original interception is unknown.
      if (session.pendingPoliceJail == null &&
          board.tiles[position].type == TileType.jail) {
        session.pendingPoliceJail = position;
      }
      final destination = session.pendingPoliceJail;
      if (session.pendingPoliceFine! <= 0 ||
          destination == null ||
          destination < 0 ||
          destination > board.lastIndex ||
          board.tiles[destination].type != TileType.jail ||
          !((position == destination &&
                  board.tiles[position].type == TileType.jail) ||
              _nearbyPolice(position) != null)) {
        throw StateError(
          'A police choice requires an encounter and a JAIL destination.',
        );
      }
    } else if (session.pendingPoliceJail != null) {
      throw StateError('A pending JAIL destination requires a police choice.');
    }
    if (session.pendingHospital &&
        (!session.currentPlayer.isInjured ||
            board.tiles[session.currentPlayer.position].type !=
                TileType.hospital)) {
      throw StateError(
        'Hospital treatment requires an injured player at HOSPITAL.',
      );
    }
    if (session.pendingShopTile != null &&
        (session.pendingShopTile! < 0 ||
            session.pendingShopTile! > board.lastIndex ||
            (board.tiles[session.pendingShopTile!].type != TileType.shop &&
                board.tiles[session.pendingShopTile!].type !=
                    TileType.hospital &&
                board.tiles[session.pendingShopTile!].type !=
                    TileType.secretSociety) ||
            session.currentPlayer.position != session.pendingShopTile)) {
      throw StateError(
        'A shop visit must belong to a SHOP, HOSPITAL or SECRET SOCIETY tile.',
      );
    }
    if (session.phase == TurnPhase.secretSocietyAccess &&
        (session.currentPlayer.icon != PlayerIcon.secretAgent ||
            !withinSecretSocietyRange)) {
      throw StateError(
        'Nearby Secret Society access requires a Secret Agent within three route spaces.',
      );
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
    DateTime Function()? clock,
    Set<String> computerPlayerIds = const {},
    List<PlayerIcon>? icons,
    List<String>? eventCardOrder,
    WeaponRules weaponRules = const WeaponRules(),
  }) {
    if (names.length < 2 || names.length > 5 || colors.length < names.length) {
      throw ArgumentError('Provide 2 to 5 player names and matching colors');
    }
    if (icons != null &&
        (icons.length != names.length ||
            icons.any((icon) => !icon.isSelectable))) {
      throw ArgumentError(
        'Choose one of the three characters for every player.',
      );
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
        computerPlayerIds: computerPlayerIds,
        players: [
          for (var i = 0; i < names.length; i++)
            PlayerState(
              id: 'p${i + 1}',
              name: names[i].trim(),
              colorValue: colors[i],
              icon: icons?[i] ?? PlayerIcon.number,
            ),
        ],
        eventDrawPile: deck,
        weaponRules: weaponRules,
      ),
      board: board,
      diceRoller: diceRoller,
      clock: clock,
    );
  }

  GameSession session;
  final BoardDefinition board;
  final DiceRoller _rollDie;
  final DateTime Function() _clock;
  int _sequence = 0;
  bool _policeArrestThisResolution = false;
  TurnOutcome? lastOutcome;

  /// Online presentation and identity belong to one device, not the turn owner.
  GameSession? get localResult => null;
  String? get localPlayerId => session.isComputerGame
      ? session.players
            .firstWhere((p) => !session.computerPlayerIds.contains(p.id))
            .id
      : null;
  void dismissLocalResult() {}

  // Characters are fixed at construction/start; old mutation APIs cannot
  // change a class during a saved or active match.
  bool get canChangePlayerIcon => false;
  void changePlayerIcon(PlayerIcon icon) {}

  int weaponRange(WeaponType type) =>
      type.range + session.currentPlayer.icon.weaponRangeBonus;
  int get hitmanHirePrice =>
      session.currentPlayer.icon.secretSocietyPrice(hitmanPrice);

  bool get isHospitalShopping =>
      session.pendingShopTile != null &&
      board.tiles[session.pendingShopTile!].type == TileType.hospital;

  bool get isSecretSocietyShopping =>
      session.pendingShopTile != null &&
      board.tiles[session.pendingShopTile!].type == TileType.secretSociety;

  int get hospitalKitsAvailable => session.pendingShopTile == null
      ? 0
      : session.hospitalStocks[session.pendingShopTile!]?.available(_clock()) ??
            0;

  Duration get hospitalRefillRemaining => session.pendingShopTile == null
      ? HospitalStock.refillInterval
      : session.hospitalStocks[session.pendingShopTile!]?.untilNext(_clock()) ??
            HospitalStock.refillInterval;

  static const hitmanPrice = 200;
  static const hitmanRange = 20;
  static const secretSocietyAccessRange = 3;

  bool get withinSecretSocietyRange => board.tiles.any((tile) {
    if (tile.type != TileType.secretSociety) return false;
    final distance = (tile.index - session.currentPlayer.position).abs();
    return distance == 0 ||
        session.currentPlayer.icon == PlayerIcon.secretAgent &&
            distance <= secretSocietyAccessRange;
  });

  bool get canAccessSecretSociety =>
      session.winnerId == null &&
      (session.isBoardInteractive && withinSecretSocietyRange ||
          session.phase == TurnPhase.shopping && isSecretSocietyShopping);

  bool get canHireHitman =>
      canAccessSecretSociety &&
      !session.hitmanHired &&
      session.currentPlayer.cash >= hitmanHirePrice;

  bool hireHitman(int tileIndex) {
    if (!canHireHitman || tileIndex < 0 || tileIndex > board.lastIndex) {
      return false;
    }
    session.currentPlayer.cash -= hitmanHirePrice;
    session.hitmanHired = true;
    session.hitmanOwnerId = session.currentPlayer.id;
    session.hitmanTile = tileIndex;
    // Do not put the hirer's identity or location in public messages/results.
    notifyListeners();
    return true;
  }

  List<int> get hitmanTargets {
    if (session.phase != TurnPhase.ready ||
        session.hitmanOwnerId != session.currentPlayer.id ||
        session.hitmanTile == null ||
        session.winnerId != null) {
      return const [];
    }
    return [
      for (var i = 0; i < session.players.length; i++)
        if (i != session.currentPlayerIndex &&
            session.players[i].position > 0 &&
            (session.players[i].position - session.hitmanTile!).abs() <=
                hitmanRange)
          i,
    ];
  }

  bool useHitman(int targetIndex) {
    if (!hitmanTargets.contains(targetIndex)) return false;
    final target = session.players[targetIndex];
    final from = target.position;
    target.position = 0;
    session.hitmanOwnerId = null;
    session.hitmanTile = null;
    session.hitmanHired = false;
    session.weaponActionTaken = true;
    session.attackReplacesMove = true;
    session.pendingShopTile = null;
    session.lastDice = null;
    session.message =
        'An anonymous hitman sent ${target.name} back to START. The hirer stays in place and their turn is over.';
    // No stars, money or public contract details identify the hirer.
    session.tileSummary = TileSummary(
      title: 'ANONYMOUS HITMAN',
      message: session.message,
      landedIndex: session.currentPlayer.position,
      finalPosition: session.currentPlayer.position,
      changes: ['${target.name}: tile $from → START'],
    );
    session.phase = TurnPhase.animating;
    lastOutcome = TurnOutcome(
      sequence: ++_sequence,
      playerIndex: targetIndex,
      dice: 1,
      path: const [0],
      description: session.message,
      landedType: TileType.normal,
      effectLabel: 'ANONYMOUS HITMAN',
    );
    notifyListeners();
    return true;
  }

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
    session.attackReplacesMove = false;
    session.pendingShopTile = null;
    session.pendingPortalTile = null;
    session.portalCardDirections.clear();
    session.phase = TurnPhase.rolling;
    notifyListeners();
    return dice;
  }

  /// Phase 2. Called by Flutter after the visual dice animation ends.
  TurnOutcome? resolveDiceRoll({bool offerAttackChoice = true}) {
    if (session.phase != TurnPhase.rolling) return null;
    final dice = session.lastDice!;
    if (offerAttackChoice &&
        WeaponType.values.any((type) => _targetsForRoll(type).isNotEmpty)) {
      session.phase = TurnPhase.preMoveWeaponChoice;
      notifyListeners();
      return null;
    }
    // Committing the roll to movement closes every weapon attack for this turn.
    session.weaponActionTaken = true;
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
    final healthPacksBefore = player.inventory.healthPacks;
    final injuredBefore = player.isInjured;
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
    record('Health packs', healthPacksBefore, player.inventory.healthPacks);
    record('Raw meat', meatBefore, player.inventory.rawMeat);
    record('Stabbers', stabbersBefore, player.inventory.stabbers);
    record('Pew pews', pewPewsBefore, player.inventory.pewPews);
    record('Stars', starsBefore, player.inventory.stars);
    record('Turns to miss', skipsBefore, player.skipTurns);
    if (injuredBefore != player.isInjured) {
      changes.add('Health: ${player.isInjured ? 'INJURED' : 'HEALTHY'}');
    }
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
          ? session.pendingPoliceFine != null
                ? 'POLICE · BRIBE CHOICE'
                : 'POLICE · GO TO JAIL'
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
      case TileType.surf:
        if (player.icon.canSwim || player.inventory.boats > 0) {
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
          } while (board.tiles[destination].isWater);
          player.position = destination;
          if (player.icon.canSwim) {
            return 'SWIMMER: swam safely to space $destination, after the water. No boat needed.';
          }
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
        if (player.icon.ignoresLions) {
          return 'CAT WHISPERER: passed the lion safely. No raw meat or health kit was used.';
        }
        if (player.inventory.rawMeat > 0) {
          player.inventory.rawMeat--;
          return 'LION: fed the lion one raw meat. You are safe!';
        }
        player.isInjured = true;
        if (_consumeHealthPack(player)) {
          return 'LION: No raw meat, the lion injured you. Used one health pack '
              'and recovered here. No hospital visit or treatment fee.';
        }
        player.position = tile.destination!;
        path.add(player.position);
        return 'LION: No raw meat, the lion injured you. Go to HOSPITAL.';
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
        session.pendingPoliceFine = fine;
        session.pendingPoliceJail = destination;
        session.weaponActionTaken = true;
        session.pendingShopTile = null;
        return 'POLICE: stopped here. Choose whether to pay a \$$fine bribe to stay.';
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
        session.weaponActionTaken = true;
        // A broken blue mine has an equal chance of death or treatable injury.
        final fatal =
            tile.mineColor == MineColor.red ||
            (tile.mineColor == MineColor.blue && _rollDie() <= 3);
        if (!fatal) {
          player.isInjured = true;
          final color = tile.mineColor.name.toUpperCase();
          if (_consumeHealthPack(player)) {
            return '$color MINE: injured, but used one health pack and recovered here. '
                'No hospital visit or treatment fee.';
          }
          player.position = tile.destination!;
          path.add(player.position);
          return '$color MINE: injured and sent to HOSPITAL at space ${player.position}.';
        }
        player.isInjured = false;
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
      case TileType.secretSociety:
        session.pendingShopTile = tile.index;
        return 'SECRET SOCIETY: private contracts are available here.';
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
        if (!player.isInjured) {
          session.pendingShopTile = tile.index;
          return 'HOSPITAL: You are healthy. No treatment fee. '
              'You may buy health packs and antidotes.';
        }
        if (player.cash < 10 && player.inventory.healthPacks == 0) {
          player.isInjured = false;
          player.position = 0;
          path.add(0);
          return 'HOSPITAL: Treatment costs 10 coins. You do not have enough coins '
              'or a health pack, so you recovered at START. Your turn is over.';
        }
        session.pendingHospital = true;
        return 'HOSPITAL: You are injured. Pay 10 coins, use a health pack, '
            'or recover at START for free.';
      case TileType.fire:
      case TileType.trapDoor:
        final trap = tile.type == TileType.trapDoor;
        if (trap) player.skipTurns++;
        player.isInjured = true;
        session.weaponActionTaken = true;
        if (_consumeHealthPack(player)) {
          return '${trap ? 'TRAP DOOR' : 'FIRE'}: injured, but used one health pack '
              'and recovered here. No hospital visit or treatment fee.'
              '${trap ? ' Miss one turn.' : ''}';
        }
        player.position = tile.destination!;
        path.add(player.position);
        return trap
            ? 'TRAP DOOR: injured, miss one turn and go to HOSPITAL at space ${player.position}.'
            : 'FIRE: injured and sent straight to HOSPITAL at space ${player.position}.';
      case TileType.finish:
        return 'Finished the board!';
    }
  }

  bool _consumeHealthPack(PlayerState player) {
    if (player.inventory.healthPacks <= 0) return false;
    player.inventory.healthPacks--;
    player.isInjured = false;
    return true;
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
    session.pendingPoliceFine = stars > 0
        ? null
        : police.amount == 0
        ? 20
        : police.amount;
    session.pendingPoliceJail = stars > 0 ? null : destination;
    if (stars > 0) {
      player.position = destination;
      path.add(destination);
      player.skipTurns += stars;
    }
    session.pendingShopTile = null;
    session.weaponActionTaken = true;
    if (stars > 0) {
      return 'POLICE: caught with $stars star(s) within 3 spaces of police tile ${police.index}. '
          'Moved to JAIL at space $destination. Miss $stars turn(s). Stars cleared.'
          '${hadWeapons ? ' All weapons were confiscated.' : ''}';
    }
    return 'POLICE: carrying weapons within 3 spaces of police tile ${police.index}. '
        'All weapons were confiscated. Choose whether to pay a '
        '\$${session.pendingPoliceFine} bribe to stay here.';
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
    _completeAfterEffects();
  }

  void chooseHospitalTreatment({required bool pay}) {
    if (session.phase != TurnPhase.hospitalChoice ||
        !session.pendingHospital ||
        !session.currentPlayer.isInjured) {
      return;
    }
    final player = session.currentPlayer;
    if (pay && player.cash < 10) return;
    if (pay) {
      player.cash -= 10;
      session.message =
          'HOSPITAL: You paid 10 coins for treatment and are healthy. '
          'You may buy health packs and antidotes before leaving.';
    } else {
      player.position = 0;
      session.message =
          'HOSPITAL: You recovered at START. No coins were charged. Your turn is over.';
    }
    _finishHospitalTreatment(
      title: pay ? 'HOSPITAL · TREATED' : 'HOSPITAL · RESTART',
      change: pay ? 'Treatment: −10 coins' : 'Returned to START',
      stay: pay,
    );
  }

  void useHealthPack() {
    if (session.phase != TurnPhase.hospitalChoice ||
        !session.pendingHospital ||
        !session.currentPlayer.isInjured ||
        session.currentPlayer.inventory.healthPacks == 0) {
      return;
    }
    _consumeHealthPack(session.currentPlayer);
    session.message =
        'HOSPITAL: You used one health pack and are healthy. No coins were charged. '
        'You may buy health packs and antidotes before leaving.';
    _finishHospitalTreatment(
      title: 'HOSPITAL · TREATED',
      change: 'Health packs: −1',
      stay: true,
    );
  }

  void _finishHospitalTreatment({
    required String title,
    required String change,
    required bool stay,
  }) {
    final player = session.currentPlayer;
    session.pendingHospital = false;
    player.isInjured = false;
    final previous = session.tileSummary;
    session.tileSummary = TileSummary(
      title: title,
      message: session.message,
      landedIndex: previous?.landedIndex ?? player.position,
      finalPosition: player.position,
      changes: [...?previous?.changes, change, 'Health: HEALTHY'],
    );
    session.pendingShopTile = stay ? player.position : null;
    session.phase = stay ? TurnPhase.shopping : TurnPhase.specialReview;
    notifyListeners();
  }

  void dismissTileSummary() {
    if (session.phase != TurnPhase.specialReview) return;
    session.tileSummary = null;
    _completeAfterEffects();
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
    _completeAfterEffects();
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

  List<int> _targetsForRoll(WeaponType type) {
    final dice = session.lastDice ?? 0;
    if (session.winnerId != null ||
        session.weaponActionTaken ||
        dice < 4 ||
        weaponCount(type) < 1 ||
        _nearbyPolice(session.currentPlayer.position) != null) {
      return const [];
    }
    final from = session.currentPlayer.position;
    return [
      for (var i = 0; i < session.players.length; i++)
        if (i != session.currentPlayerIndex &&
            session.players[i].position > 0 &&
            (session.players[i].position == from ||
                dice == 6 &&
                    (session.players[i].position - from).abs() <=
                        weaponRange(type)))
          i,
    ];
  }

  List<int> weaponTargets(WeaponType type) =>
      session.phase == TurnPhase.preMoveWeaponChoice
      ? _targetsForRoll(type)
      : const [];

  void chooseMovement() {
    if (session.phase != TurnPhase.preMoveWeaponChoice ||
        session.weaponActionTaken) {
      return;
    }
    session.phase = TurnPhase.rolling;
    resolveDiceRoll(offerAttackChoice: false);
  }

  void _completeAfterEffects() {
    final nearby = session.currentPlayer.inventory.hasPoliceRisk
        ? _nearbyPolice(session.currentPlayer.position)
        : null;
    if (nearby != null) {
      _animateContrabandArrest(nearby);
      return;
    }
    if (session.winnerId == null &&
        !session.attackReplacesMove &&
        session.currentPlayer.icon == PlayerIcon.secretAgent &&
        withinSecretSocietyRange &&
        board.tiles[session.currentPlayer.position].type !=
            TileType.secretSociety) {
      session.phase = TurnPhase.secretSocietyAccess;
      notifyListeners();
      return;
    }
    _completeTurn();
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
    if (session.phase == TurnPhase.secretSocietyAccess) {
      session.pendingShopTile = null;
      _completeTurn();
      return;
    }
    if (session.phase != TurnPhase.shopping) return;
    session.pendingShopTile = null;
    if (session.tileSummary != null) {
      session.phase = TurnPhase.specialReview;
      notifyListeners();
    } else {
      _completeAfterEffects();
    }
  }

  bool buyWeapon(WeaponType type) {
    if (session.phase != TurnPhase.shopping ||
        isHospitalShopping ||
        isSecretSocietyShopping) {
      return false;
    }
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

  bool buyMedicalItem(MedicalItem item) {
    if (session.phase != TurnPhase.shopping || !isHospitalShopping) {
      return false;
    }
    final player = session.currentPlayer;
    if (player.cash < item.price) return false;
    final beforeCash = player.cash;
    final beforeCount = item == MedicalItem.healthPack
        ? player.inventory.healthPacks
        : player.inventory.antidotes;
    if (item == MedicalItem.healthPack &&
        !session.hospitalStocks[session.pendingShopTile!]!.take(_clock())) {
      return false;
    }
    player.cash -= item.price;
    if (item == MedicalItem.healthPack) {
      player.inventory.healthPacks++;
    } else {
      player.inventory.antidotes++;
    }
    session.message += ' Bought a ${item.label} for \$${item.price}.';
    final old = session.tileSummary;
    session.tileSummary = TileSummary(
      title: 'HOSPITAL · SUPPLIES',
      message: session.message,
      landedIndex: old?.landedIndex ?? player.position,
      finalPosition: player.position,
      changes: [
        ...?old?.changes,
        'Cash: −\$${item.price} ($beforeCash → ${player.cash})',
        '${item.label}: +1 ($beforeCount → ${beforeCount + 1})',
      ],
    );
    notifyListeners();
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
    if (session.phase != TurnPhase.preMoveWeaponChoice ||
        !weaponTargets(type).contains(targetIndex)) {
      return false;
    }
    final nearby = _nearbyPolice(session.currentPlayer.position);
    if (nearby != null) {
      _animateContrabandArrest(nearby);
      return true;
    }
    final target = session.players[targetIndex];
    final attacker = session.currentPlayer;
    final from = target.position;
    final countBefore = weaponCount(type);
    final starsBefore = attacker.inventory.stars;
    if (type == WeaponType.stabber) {
      session.currentPlayer.inventory.stabbers--;
    } else {
      session.currentPlayer.inventory.pewPews--;
    }
    target.position = 0;
    session.attackReplacesMove = true;
    attacker.inventory.stars += 3;
    session.weaponActionTaken = true;
    session.message =
        '${attacker.name} used a ${type.label} on ${target.name}. '
        '${target.name} returned to START. One ${type.label} was used up. '
        '${attacker.name} gained 3 stars and no cash. The roll was used for the attack; no movement.';
    session.tileSummary = TileSummary(
      title: type.label.toUpperCase(),
      message: session.message,
      landedIndex: session.currentPlayer.position,
      finalPosition: session.currentPlayer.position,
      changes: [
        '${type.label}: −1 ($countBefore → ${weaponCount(type)})',
        '${target.name}: tile $from → START',
        'Stars: +3 ($starsBefore → ${attacker.inventory.stars})',
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

  /// Paying the bribe keeps the interception position; refusing transfers the
  /// player to jail. Both choices commit once and cannot create debt.
  void choosePolicePenalty({required bool payFine}) {
    if (session.phase != TurnPhase.jailChoice ||
        session.pendingPoliceFine == null) {
      return;
    }
    final fine = session.pendingPoliceFine!;
    final player = session.currentPlayer;
    if (payFine && player.cash < fine) return;
    final from = player.position;
    final destination =
        session.pendingPoliceJail ??
        (board.tiles[from].type == TileType.jail ? from : null);
    if (destination == null) return;
    final changes = [...?session.tileSummary?.changes];
    if (payFine) {
      final before = player.cash;
      player.cash -= fine;
      changes.add('Cash: −\$$fine ($before → ${player.cash})');
      session.message +=
          ' Paid the \$$fine bribe and stayed here; no turn is missed.';
    } else {
      final before = player.skipTurns;
      player.skipTurns++;
      player.position = destination;
      changes.add('Turns to miss: +1 ($before → ${player.skipTurns})');
      if (from != destination) changes.add('Jail: tile $from → $destination');
      session.message +=
          ' Declined the bribe. Sent to JAIL at space $destination '
          'to miss one turn; no bribe was charged.';
    }
    final previous = session.tileSummary;
    session.tileSummary = TileSummary(
      title: payFine ? 'POLICE · BRIBE PAID' : 'POLICE · JAILED',
      message: session.message,
      landedIndex: previous?.landedIndex ?? player.position,
      finalPosition: player.position,
      changes: List.unmodifiable(changes),
    );
    session.pendingPoliceFine = null;
    session.pendingPoliceJail = null;
    if (!payFine && from != destination) {
      session.phase = TurnPhase.animating;
      lastOutcome = TurnOutcome(
        sequence: ++_sequence,
        playerIndex: session.currentPlayerIndex,
        dice: session.lastDice ?? 1,
        path: [destination],
        description: session.message,
        landedType: TileType.jail,
        effectLabel: 'POLICE · GO TO JAIL',
      );
    } else {
      session.phase = TurnPhase.specialReview;
    }
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
    session.phase = session.isComputerGame
        ? TurnPhase.ready
        : TurnPhase.handoff;
    if (session.isComputerGame) {
      session.message =
          '${skipped.isEmpty ? '' : '${skipped.join(', ')} missed a turn. '}${session.currentPlayer.name}, it is your turn. Roll the dice!';
    }
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
