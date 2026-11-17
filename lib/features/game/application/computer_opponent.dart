import 'dart:async';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'game_controller.dart';
import '../domain/game_session.dart';
import '../domain/medical_item.dart';
import '../domain/weapon.dart';

/// Plays through the same public actions as a human. It never chooses dice,
/// reads opponents' inventories, or looks at hidden portal cards/event decks.
class ComputerStrategy {
  ComputerStrategy({int Function(int)? chooseCard})
    : _chooseCard = chooseCard ?? Random.secure().nextInt;
  final int Function(int) _chooseCard;

  int? _leadingTarget(GameController game, Iterable<int> targets) {
    int? best;
    for (final index in targets) {
      if (game.session.players[index].position > 0 &&
          (best == null ||
              game.session.players[index].position >
                  game.session.players[best].position)) {
        best = index;
      }
    }
    return best;
  }

  void takeAction(GameController game, {VoidCallback? rollDice}) {
    final session = game.session;
    if (!session.isComputerTurn || session.winnerId != null) return;
    final player = session.currentPlayer;
    switch (session.phase) {
      case TurnPhase.ready:
        final target = _leadingTarget(game, game.hitmanTargets);
        if (target != null) {
          game.useHitman(target);
        } else {
          final hireTarget = game.canHireHitman
              ? _leadingTarget(game, [
                  for (var i = 0; i < session.players.length; i++)
                    if (i != session.currentPlayerIndex) i,
                ])
              : null;
          if (hireTarget != null) {
            game.hireHitman(session.players[hireTarget].position);
          } else {
            (rollDice ?? game.roll)();
          }
        }
      case TurnPhase.hospitalChoice:
        if (player.inventory.healthPacks > 0) {
          game.useHealthPack();
        } else {
          game.chooseHospitalTreatment(pay: player.cash >= 10);
        }
      case TurnPhase.jailChoice:
        game.choosePolicePenalty(
          payFine: player.cash >= (session.pendingPoliceFine ?? 20),
        );
      case TurnPhase.portalChoice:
        game.choosePortalCard(_chooseCard(2));
      case TurnPhase.shopping:
      case TurnPhase.secretSocietyAccess:
        if (game.isHospitalShopping) {
          // Keep ten coins for a later treatment; never wait for sold-out stock.
          for (
            var i = player.inventory.healthPacks;
            i < 2 && player.cash >= 20 && game.hospitalKitsAvailable > 0;
            i++
          ) {
            if (!game.buyMedicalItem(MedicalItem.healthPack)) break;
          }
          if (player.inventory.antidotes == 0 && player.cash >= 15) {
            game.buyMedicalItem(MedicalItem.antidote);
          }
        } else if (game.isSecretSocietyShopping ||
            session.phase == TurnPhase.secretSocietyAccess) {
          if (game.canHireHitman) {
            final target = _leadingTarget(game, [
              for (var i = 0; i < session.players.length; i++)
                if (i != session.currentPlayerIndex) i,
            ]);
            if (target != null) {
              game.hireHitman(session.players[target].position);
            }
          }
          final target = _leadingTarget(game, game.hitmanTargets);
          if (target != null) game.useHitman(target);
        } else {
          for (final weapon in WeaponType.values.reversed) {
            if (game.weaponCount(weapon) == 0 &&
                player.cash >= session.weaponRules.price(weapon) + 10) {
              game.buyWeapon(weapon);
            }
          }
        }
        game.finishShopping();
      case TurnPhase.weaponAction:
      case TurnPhase.preMoveWeaponChoice:
        int? bestTarget;
        WeaponType? bestWeapon;
        for (final weapon in WeaponType.values) {
          final target = _leadingTarget(game, game.weaponTargets(weapon));
          if (target != null &&
              (bestTarget == null ||
                  session.players[target].position >
                      session.players[bestTarget].position)) {
            bestTarget = target;
            bestWeapon = weapon;
          }
        }
        if (bestTarget != null) {
          game.useWeapon(bestWeapon!, bestTarget);
        } else if (session.phase == TurnPhase.preMoveWeaponChoice) {
          game.chooseMovement();
        } else {
          game.skipWeaponAction();
        }
      case TurnPhase.specialReview:
        game.dismissTileSummary();
      case TurnPhase.eventReveal:
        game.dismissEventCard();
      case TurnPhase.handoff:
        game.acknowledgeHandoff();
      case TurnPhase.rolling:
      case TurnPhase.animating:
      case TurnPhase.portalTravel:
      case TurnPhase.completed:
        break; // The dice and Flame finish their animations before we act.
    }
  }
}

/// Schedules readable turns without advancing behind Help or after leaving play.
class ComputerTurnDriver {
  ComputerTurnDriver({
    required this.game,
    required this.rollDice,
    ComputerStrategy? strategy,
  }) : strategy = strategy ?? ComputerStrategy() {
    game.addListener(_schedule);
    _schedule();
  }
  final GameController game;
  final VoidCallback rollDice;
  final ComputerStrategy strategy;
  Timer? _timer;
  bool _disposed = false;
  bool _acting = false;
  int _pauses = 0;

  void pause() {
    _pauses++;
    _timer?.cancel();
  }

  void resume() {
    if (_pauses > 0) _pauses--;
    _schedule();
  }

  void _schedule() {
    _timer?.cancel();
    if (_disposed || _acting || _pauses > 0 || !game.session.isComputerGame) {
      return;
    }
    final phase = game.session.phase;
    if (phase == TurnPhase.handoff) {
      _timer = Timer(
        const Duration(milliseconds: 300),
        game.acknowledgeHandoff,
      );
      return;
    }
    if (!game.session.isComputerTurn ||
        phase == TurnPhase.rolling ||
        phase == TurnPhase.animating ||
        phase == TurnPhase.portalTravel ||
        phase == TurnPhase.completed) {
      return;
    }
    final reviewing =
        phase == TurnPhase.specialReview || phase == TurnPhase.eventReveal;
    _timer = Timer(Duration(milliseconds: reviewing ? 2200 : 750), () {
      if (_disposed || _pauses > 0) return;
      _acting = true;
      try {
        strategy.takeAction(game, rollDice: rollDice);
      } finally {
        _acting = false;
        _schedule();
      }
    });
  }

  void dispose() {
    _disposed = true;
    _timer?.cancel();
    game.removeListener(_schedule);
  }
}
