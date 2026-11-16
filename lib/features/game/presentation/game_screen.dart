import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'package:flame/game.dart' show GameWidget;
import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import '../../../app/theme.dart';
import '../application/game_controller.dart';
import '../data/session_store.dart';
import '../domain/event_card.dart';
import '../domain/game_session.dart';
import '../domain/medical_item.dart';
import '../domain/player_state.dart';
import '../domain/weapon.dart';
import '../flame/spiral_board_game.dart';
import 'turn_result_visual.dart';
import 'player_avatar.dart';
import 'weapon_action_overlay.dart';

class GameScreen extends StatefulWidget {
  const GameScreen({
    required this.controller,
    this.online = false,
    this.canInteract,
    this.onlineStatus,
    super.key,
  });
  final GameController controller;
  final bool online;
  final bool Function()? canInteract;
  final String Function()? onlineStatus;

  @override
  State<GameScreen> createState() => _GameScreenState();
}

class _GameScreenState extends State<GameScreen>
    with SingleTickerProviderStateMixin {
  late final SpiralBoardGame _boardGame;
  late final AnimationController _diceAnimation;
  final _store = SessionStore();
  Future<void> _saveTail = Future<void>.value();
  String? _lastQueuedSave;
  bool _showDiceResult = false;
  double _gestureScale = 1;

  GameSession get _displaySession =>
      widget.controller.localResult ?? widget.controller.session;

  String? get _viewerId => widget.online
      ? widget.controller.localPlayerId
      : widget.controller.session.currentPlayer.id;

  bool _canSeePrivateDetails(PlayerState player) => player.id == _viewerId;

  bool get _hasVisibleOverlay {
    if (widget.controller.localResult != null) return true;
    final session = widget.controller.session;
    switch (session.phase) {
      case TurnPhase.ready:
      case TurnPhase.rolling:
      case TurnPhase.animating:
      case TurnPhase.portalTravel:
        return false;
      case TurnPhase.specialReview:
      case TurnPhase.eventReveal:
      case TurnPhase.completed:
        return true;
      default:
        return !widget.online || _canSeePrivateDetails(session.currentPlayer);
    }
  }

  @override
  void initState() {
    super.initState();
    _boardGame = SpiralBoardGame(controller: widget.controller);
    _diceAnimation = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    );
    widget.controller.addListener(_persistStablePhase);
    _queueSave(); // Allow resume before the first roll.
    _syncRendering();
    unawaited(
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky),
    );
    unawaited(
      SystemChrome.setPreferredOrientations(const [
        DeviceOrientation.landscapeLeft,
        DeviceOrientation.landscapeRight,
      ]),
    );
  }

  void _queueSave() {
    if (widget.online) return;
    // Serialize writes so a quick event dismissal/hand-off cannot cause an
    // older snapshot to finish writing after a newer one.
    final snapshot = jsonEncode(widget.controller.session.toJson());
    if (snapshot == _lastQueuedSave) return;
    _lastQueuedSave = snapshot;
    _saveTail = _saveTail.then((_) => _store.saveEncoded(snapshot)).catchError((
      Object error,
      StackTrace stack,
    ) {
      _lastQueuedSave = null;
      debugPrint('Could not save the game: $error');
    });
  }

  void _syncRendering() {
    final boardVisible = !_hasVisibleOverlay;
    if (boardVisible) {
      _boardGame.resumeEngine();
    } else {
      _boardGame.pauseEngine();
    }
  }

  void _persistStablePhase() {
    _syncRendering();
    final phase = widget.controller.session.phase;
    if (phase == TurnPhase.ready ||
        phase == TurnPhase.handoff ||
        phase == TurnPhase.specialReview ||
        phase == TurnPhase.jailChoice ||
        phase == TurnPhase.hospitalChoice ||
        phase == TurnPhase.shopping ||
        phase == TurnPhase.weaponAction ||
        phase == TurnPhase.preMoveWeaponChoice ||
        phase == TurnPhase.eventReveal ||
        phase == TurnPhase.portalChoice ||
        phase == TurnPhase.portalTravel ||
        phase == TurnPhase.completed) {
      _queueSave();
    }
    if (phase == TurnPhase.eventReveal ||
        phase == TurnPhase.jailChoice ||
        phase == TurnPhase.hospitalChoice ||
        phase == TurnPhase.specialReview ||
        phase == TurnPhase.handoff ||
        phase == TurnPhase.completed) {
      unawaited(HapticFeedback.mediumImpact());
    }
  }

  Future<void> _rollDice() async {
    final result = widget.controller.beginDiceRoll();
    if (result == null) return;
    unawaited(HapticFeedback.selectionClick());
    try {
      await _diceAnimation.forward(from: 0).orCancel;
    } on TickerCanceled {
      return; // GameScreen was disposed during the animation.
    }
    if (!mounted) return;
    setState(() => _showDiceResult = true);
    unawaited(SystemSound.play(SystemSoundType.click));
    await Future<void>.delayed(const Duration(milliseconds: 650));
    if (!mounted) return;
    _showDiceResult = false;
    widget.controller.resolveDiceRoll();
  }

  @override
  void dispose() {
    widget.controller.removeListener(_persistStablePhase);
    _diceAnimation.dispose();
    unawaited(SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge));
    unawaited(SystemChrome.setPreferredOrientations(DeviceOrientation.values));
    super.dispose();
  }

  Future<void> _newGame() async {
    if (widget.online) {
      Navigator.of(context).pop();
      return;
    }
    await _saveTail;
    await _store.clear();
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF101E29),
      body: Stack(
        fit: StackFit.expand,
        children: [
          Listener(
            onPointerSignal: (event) {
              if (event is PointerScrollEvent) {
                if (HardwareKeyboard.instance.isControlPressed ||
                    HardwareKeyboard.instance.isMetaPressed) {
                  _boardGame.zoomBoard(
                    math.exp(-event.scrollDelta.dy * .002),
                    focalPoint: event.localPosition,
                  );
                } else {
                  _boardGame.panBoard(-event.scrollDelta);
                }
              }
            },
            child: GestureDetector(
              onLongPressStart: (details) {
                if (widget.controller.session.phase != TurnPhase.ready) return;
                final tile = _boardGame.tileAtScreen(details.localPosition);
                if (tile != null) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(
                        'Tile ${tile.index} · ${tile.label.isEmpty ? tile.typeLabel : tile.label}\n${tile.typeLabel}',
                      ),
                    ),
                  );
                }
              },
              onScaleStart: (_) => _gestureScale = 1,
              onScaleUpdate: (details) {
                final factor = details.scale / _gestureScale;
                if ((factor - 1).abs() > .0001) {
                  _boardGame.zoomBoard(
                    factor,
                    focalPoint: details.localFocalPoint,
                  );
                }
                _boardGame.panBoard(details.focalPointDelta);
                _gestureScale = details.scale;
              },
              child: GameWidget(game: _boardGame),
            ),
          ),
          SafeArea(child: _buildHud()),
          // Privacy overlays cover both the board and floating controls.
          AnimatedBuilder(
            animation: widget.controller,
            builder: (context, _) => IgnorePointer(
              ignoring:
                  widget.controller.localResult == null &&
                  !(widget.canInteract?.call() ?? true) &&
                  widget.controller.session.phase != TurnPhase.completed,
              child: _buildStateOverlay(),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _changePlayerIcon() async {
    final game = widget.controller;
    final index = widget.online
        ? game.session.players.indexWhere((p) => p.id == game.localPlayerId)
        : game.session.currentPlayerIndex;
    if (index < 0 || !game.canChangePlayerIcon) return;
    final player = game.session.players[index];
    final icon = await pickPlayerIcon(
      context,
      selected: player.icon,
      color: Color(player.colorValue),
      number: index + 1,
    );
    if (mounted && icon != null) game.changePlayerIcon(icon);
  }

  Widget _buildHud() {
    return AnimatedBuilder(
      animation: widget.controller,
      builder: (context, _) {
        final session = widget.controller.session;
        final player = session.currentPlayer;
        final moving =
            session.phase == TurnPhase.animating ||
            session.phase == TurnPhase.portalTravel;
        return Stack(
          children: [
            if (session.phase == TurnPhase.ready)
              Positioned(
                right: 12,
                top: 80,
                child: _hudCard(
                  Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        tooltip: 'Zoom in',
                        icon: const Icon(Icons.add),
                        onPressed: () => _boardGame.zoomBoard(1.3),
                      ),
                      IconButton(
                        tooltip: 'Zoom out',
                        icon: const Icon(Icons.remove),
                        onPressed: () => _boardGame.zoomBoard(1 / 1.3),
                      ),
                      IconButton(
                        tooltip: 'Fit board to width',
                        icon: const Icon(Icons.fit_screen),
                        onPressed: _boardGame.fitBoardWidth,
                      ),
                    ],
                  ),
                ),
              ),
            if (_showDiceResult)
              Center(
                child: _hudCard(
                  Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 36,
                      vertical: 20,
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Text(
                          'YOU ROLLED',
                          style: TextStyle(
                            color: AppTheme.gold,
                            fontWeight: FontWeight.bold,
                            letterSpacing: 2,
                          ),
                        ),
                        Text(
                          '${session.lastDice}',
                          style: const TextStyle(
                            fontSize: 76,
                            fontWeight: FontWeight.w900,
                            color: Colors.white,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            Positioned(
              top: 8,
              left: 8,
              right: 8,
              child: Row(
                children: [
                  Flexible(
                    child: _hudCard(
                      Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 8,
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            PlayerAvatar(
                              icon: player.icon,
                              color: Color(player.colorValue),
                              number: session.currentPlayerIndex + 1,
                              radius: 12,
                            ),
                            const SizedBox(width: 8),
                            Flexible(
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    '${player.name} · ROUND ${session.round}',
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                  if (widget.online)
                                    Text(
                                      widget.onlineStatus?.call() ??
                                          'Online room',
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                        color: AppTheme.gold,
                                        fontSize: 11,
                                      ),
                                    ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  _hudCard(
                    IconButton(
                      tooltip: 'Focus current player',
                      onPressed: session.phase == TurnPhase.ready
                          ? _boardGame.focusCurrentPlayer
                          : null,
                      icon: const Icon(Icons.center_focus_strong),
                    ),
                  ),
                  const SizedBox(width: 8),
                  _hudCard(
                    IconButton(
                      tooltip: 'Change player icon',
                      onPressed:
                          !moving &&
                              !_hasVisibleOverlay &&
                              widget.controller.canChangePlayerIcon
                          ? _changePlayerIcon
                          : null,
                      icon: const Icon(Icons.face),
                    ),
                  ),
                  const SizedBox(width: 8),
                  _hudCard(
                    IconButton(
                      tooltip: 'Players and inventory',
                      onPressed: !moving && !_hasVisibleOverlay
                          ? _showGameDetails
                          : null,
                      icon: const Icon(Icons.inventory_2_outlined),
                    ),
                  ),
                  const SizedBox(width: 8),
                  _hudCard(
                    IconButton(
                      tooltip: 'Exit game',
                      onPressed: () => Navigator.of(context).pop(),
                      icon: const Icon(Icons.close),
                    ),
                  ),
                ],
              ),
            ),
            if (!moving)
              Positioned(
                bottom: 12,
                left: 12,
                right: 12,
                child: Align(
                  alignment:
                      widget.controller.board.tiles[player.position].x > .65
                      ? Alignment.bottomLeft
                      : Alignment.bottomRight,
                  child: _hudCard(
                    Padding(
                      padding: const EdgeInsets.all(10),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          _buildDie(),
                          const SizedBox(width: 12),
                          FilledButton.icon(
                            onPressed:
                                session.phase == TurnPhase.ready &&
                                    (widget.canInteract?.call() ?? true)
                                ? _rollDice
                                : null,
                            icon: const Icon(Icons.casino),
                            label: Text(
                              session.phase == TurnPhase.rolling
                                  ? 'ROLLING...'
                                  : player.reverseNextMove
                                  ? 'ROLL BACKWARDS'
                                  : 'ROLL DICE',
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            if (moving)
              Positioned(
                bottom: 12,
                left: 12,
                right: 12,
                child: Center(
                  child: _hudCard(
                    Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 8,
                      ),
                      child: Text(
                        widget.online
                            ? '${session.players[widget.controller.lastOutcome?.playerIndex ?? session.currentPlayerIndex].name} is moving.'
                            : _withoutTileNumbers(session.message),
                        textAlign: TextAlign.center,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 12),
                      ),
                    ),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }

  Widget _hudCard(Widget child) => Material(
    color: AppTheme.panel.withValues(alpha: .92),
    borderRadius: BorderRadius.circular(14),
    child: child,
  );

  Widget _buildDie() => AnimatedBuilder(
    animation: _diceAnimation,
    builder: (context, _) {
      final rolling =
          widget.controller.session.phase == TurnPhase.rolling &&
          !_showDiceResult;
      final face = rolling
          ? ((_diceAnimation.value * 23).floor() % 6) + 1
          : widget.controller.session.lastDice ?? 1;
      final progress = Curves.easeInOutCubic.transform(_diceAnimation.value);
      final angle = rolling ? progress * math.pi * 4 : 0.0;
      return Transform(
        alignment: Alignment.center,
        transform: Matrix4.identity()
          ..setEntry(3, 2, .001)
          ..rotateY(angle)
          ..rotateX(angle),
        child: Container(
          width: 48,
          height: 48,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: const Color(0xFFF5F0E4),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Text(
            const ['⚀', '⚁', '⚂', '⚃', '⚄', '⚅'][face - 1],
            style: const TextStyle(
              fontSize: 38,
              color: Color(0xFF102139),
              height: 1,
            ),
          ),
        ),
      );
    },
  );

  void _showGameDetails() {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppTheme.panel,
      showDragHandle: true,
      builder: (context) => StatefulBuilder(
        builder: (context, updateSheet) {
          return AnimatedBuilder(
            animation: widget.controller,
            builder: (context, _) => SafeArea(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Text(
                      'PLAYERS & INVENTORY',
                      style: TextStyle(
                        color: AppTheme.gold,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 12),
                    for (final player in widget.controller.session.players)
                      _playerRow(player),
                    const SizedBox(height: 12),
                    Text(
                      widget.online
                          ? '${widget.controller.session.currentPlayer.name}’s turn.'
                          : _withoutTileNumbers(
                              widget.controller.session.message,
                            ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      widget.online
                          ? 'Current tile: ${widget.controller.session.currentPlayer.position}'
                          : widget
                                .controller
                                .board
                                .tiles[widget
                                    .controller
                                    .session
                                    .currentPlayer
                                    .position]
                                .typeLabel,
                      style: const TextStyle(color: AppTheme.gold),
                    ),
                    OutlinedButton.icon(
                      onPressed: () {
                        Navigator.of(context).pop();
                        _newGame();
                      },
                      icon: const Icon(Icons.restart_alt),
                      label: const Text('NEW GAME'),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _playerRow(PlayerState p) {
    if (!_canSeePrivateDetails(p)) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Row(
          children: [
            PlayerAvatar(
              icon: p.icon,
              color: Color(p.colorValue),
              number:
                  widget.controller.session.players.indexWhere(
                    (player) => player.id == p.id,
                  ) +
                  1,
              radius: 12,
            ),
            const SizedBox(width: 7),
            Expanded(child: Text(p.name)),
            Text(
              'Tile ${p.position}',
              style: const TextStyle(color: Colors.white70),
            ),
          ],
        ),
      );
    }
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          PlayerAvatar(
            icon: p.icon,
            color: Color(p.colorValue),
            number:
                widget.controller.session.players.indexWhere(
                  (player) => player.id == p.id,
                ) +
                1,
            radius: 12,
          ),
          const SizedBox(width: 7),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(child: Text(p.name)),
                    if (p.skipTurns > 0) ...[
                      const Icon(
                        Icons.lock_clock,
                        color: Color(0xFFFFC66E),
                        size: 14,
                      ),
                      Text(
                        '${p.skipTurns}',
                        style: const TextStyle(fontSize: 12),
                      ),
                      const SizedBox(width: 6),
                    ],
                    Text(
                      '\$${p.cash}',
                      style: const TextStyle(color: AppTheme.gold),
                    ),
                  ],
                ),
                Text(
                  '${p.isInjured ? 'Injured' : 'Healthy'} · Health packs ${p.inventory.healthPacks}',
                  style: TextStyle(
                    color: p.isInjured
                        ? const Color(0xFFFFC66E)
                        : Colors.white70,
                    fontSize: 12,
                  ),
                ),
                Text(
                  'Boats ${p.inventory.boats} · Antidotes ${p.inventory.antidotes} · Raw meat ${p.inventory.rawMeat}',
                  style: const TextStyle(color: Colors.white70, fontSize: 10),
                ),
                Text(
                  'Stabbers ${p.inventory.stabbers} · Pew pews ${p.inventory.pewPews}',
                  style: const TextStyle(color: Colors.white70, fontSize: 10),
                ),
                Text(
                  'Stars ${p.inventory.stars}',
                  style: const TextStyle(color: AppTheme.gold, fontSize: 10),
                ),
                if (p.reverseNextMove)
                  const Text(
                    'Next move: BACKWARDS',
                    style: TextStyle(color: AppTheme.gold, fontSize: 10),
                  ),
                if (p.debt > 0)
                  Text(
                    'Debt \$${p.debt}',
                    style: const TextStyle(color: Colors.white60, fontSize: 10),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStateOverlay() {
    if (!_hasVisibleOverlay) return const SizedBox.shrink();
    final session = _displaySession;
    switch (session.phase) {
      case TurnPhase.portalChoice:
        return _portalChoiceOverlay();
      case TurnPhase.shopping:
        return _shoppingOverlay();
      case TurnPhase.preMoveWeaponChoice:
      case TurnPhase.weaponAction:
        return WeaponActionOverlay(controller: widget.controller);
      case TurnPhase.hospitalChoice:
        return _fullScreenMessage(
          icon: Icons.local_hospital_rounded,
          heading: 'HOSPITAL',
          subtitle:
              'You are injured. Pay 10 coins or use a health pack for treatment, then shop for medical supplies. You can also restart at START for free. Cash: \$${session.currentPlayer.cash}.',
          highlightedName: 'INJURY TREATMENT',
          highlightColor: AppTheme.gold,
          details: _summaryDetails(),
          extraContent: session.currentPlayer.inventory.healthPacks > 0
              ? _catalogButton(
                  label: 'USE HEALTH PACK',
                  details:
                      'Owned ${session.currentPlayer.inventory.healthPacks} · No treatment fee',
                  icon: Icons.medical_services_outlined,
                  onPressed: widget.controller.useHealthPack,
                )
              : null,
          buttonLabel: 'PAY 10 COINS',
          buttonIcon: Icons.payments_rounded,
          onPressed: session.currentPlayer.cash >= 10
              ? () => widget.controller.chooseHospitalTreatment(pay: true)
              : null,
          secondaryButtonLabel: 'RESTART FOR FREE',
          onSecondaryPressed: () =>
              widget.controller.chooseHospitalTreatment(pay: false),
        );
      case TurnPhase.jailChoice:
        final fine = session.pendingPoliceFine!;
        final player = session.currentPlayer;
        final canPay = player.cash >= fine;
        return _fullScreenMessage(
          icon: Icons.local_police_outlined,
          illustration: TurnResultVisual(
            session: session,
            board: widget.controller.board,
          ),
          heading: 'POLICE · CHOOSE YOUR PENALTY',
          subtitle:
              '${session.message}\n\nPay a \$$fine bribe to stay here, or go to jail and miss one turn. '
              'Your cash: \$${player.cash}.'
              '${canPay ? '' : '\nNot enough cash to pay the bribe.'}',
          highlightedName: 'BRIBE OR JAIL',
          highlightColor: AppTheme.gold,
          details: _summaryDetails(),
          buttonLabel: 'BRIBE \$$fine',
          buttonIcon: Icons.payments_rounded,
          onPressed: canPay
              ? () => widget.controller.choosePolicePenalty(payFine: true)
              : null,
          secondaryButtonLabel: 'GO TO JAIL',
          onSecondaryPressed: () =>
              widget.controller.choosePolicePenalty(payFine: false),
        );
      case TurnPhase.specialReview:
        final summary = session.tileSummary!;
        return _fullScreenMessage(
          icon: Icons.info_outline,
          illustration: TurnResultVisual(
            session: session,
            board: widget.controller.board,
          ),
          heading: '',
          descriptionOnly: true,
          subtitle: summary.message,
          details: _additionDetails(),
          highlightedName: summary.title,
          highlightColor: AppTheme.gold,
          buttonLabel: 'CONTINUE',
          onPressed: _dismissDisplayedResult,
        );
      case TurnPhase.handoff:
        return _fullScreenMessage(
          icon: Icons.phonelink_ring,
          heading: 'PASS THE DEVICE',
          subtitle: session.handoffMessage,
          highlightedName: session.currentPlayer.name,
          highlightColor: Color(session.currentPlayer.colorValue),
          buttonLabel: "I'M READY — SHOW BOARD",
          onPressed: widget.controller.acknowledgeHandoff,
        );
      case TurnPhase.eventReveal:
        final card = EventCards.byId(session.pendingCardId!);
        return _fullScreenMessage(
          icon: Icons.style,
          illustration: TurnResultVisual(
            session: session,
            board: widget.controller.board,
          ),
          heading: 'EVENT CARD',
          subtitle:
              '${card.description}\n\n${session.tileSummary?.message ?? session.message}',
          highlightedName: card.title,
          details: _summaryDetails(),
          highlightColor: AppTheme.gold,
          buttonLabel: 'CONTINUE',
          onPressed: _dismissDisplayedResult,
        );
      case TurnPhase.completed:
        final winner = session.players.firstWhere(
          (p) => p.id == session.winnerId,
        );
        return _fullScreenMessage(
          icon: Icons.emoji_events,
          heading: 'WINNER!',
          subtitle:
              '${winner.name} reached the centre of the board. '
              'Congratulations! 🏆',
          highlightedName: winner.name,
          highlightColor: Color(winner.colorValue),
          buttonLabel: widget.online ? 'BACK TO ROOM' : 'PLAY AGAIN',
          onPressed: _newGame,
        );
      case TurnPhase.ready:
      case TurnPhase.rolling:
      case TurnPhase.animating:
      case TurnPhase.portalTravel:
        return const SizedBox.shrink();
    }
  }

  void _dismissDisplayedResult() {
    if (widget.controller.localResult != null) {
      widget.controller.dismissLocalResult();
    } else if (widget.controller.session.phase == TurnPhase.eventReveal) {
      widget.controller.dismissEventCard();
    } else {
      widget.controller.dismissTileSummary();
    }
  }

  String _withoutTileNumbers(String text) => text
      .replaceAll(RegExp(r'Portal: tile \d+ → \d+'), 'Portal travel')
      .replaceAll(RegExp(r': tile \d+ → START'), ': returned to START')
      .replaceAll(RegExp(r' at (?:tile|space) \d+'), '')
      .replaceAll(RegExp(r'police tile \d+'), 'police')
      .replaceAll(RegExp(r'on (?:tile|space) \d+'), 'in place')
      .replaceAll(RegExp(r'to (?:tile|space) \d+'), 'to the destination');

  String _conciseOutcome(String message) => _withoutTileNumbers(message)
      .replaceFirst(RegExp(r'^.*? rolled [1-6]\.\s*'), '')
      .replaceAll('Your turn is over.', '')
      .replaceAll('Landed on START · SPIRAL.', '')
      .replaceAll('You returned to START.', 'Restart at START.')
      .replaceAll('Added to inventory.', '')
      .replaceAll('No additional missed turns.', '')
      .replaceAll(
        'Treatment costs 10 coins. You do not have enough coins or a health pack, so you recovered at START.',
        'No coins or health pack for treatment. Recovered at START.',
      )
      .replaceAll(
        'You paid 10 coins for treatment and are healthy.',
        'Paid 10 coins. You are healthy.',
      )
      .replaceAll(
        'You recovered at START. No coins were charged.',
        'Recovered at START for free.',
      )
      .replaceAll(
        'your boat carried you safely to space',
        'Your boat carried you safely to space',
      )
      .replaceAll(
        'after the sea. Your boat stays in your inventory.',
        'Keep your boat.',
      )
      .replaceAll(
        'Carrying stars within 3 spaces of POLICE causes a jail sentence.',
        '',
      )
      .replaceAll(
        RegExp(
          r'\b(?:SEA|MINE|LION|SNAKE|HOSPITAL|TRAP DOOR|FIRE|RAW MEAT|CONFUSION):\s*',
        ),
        '',
      )
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();

  // Saved summaries include the pre-pickup amount, so resumed results display
  // the same arithmetic rather than counting the gain twice.
  String _formatAddition(String detail) {
    final match = RegExp(
      r'^(Cash|Boats|Antidotes|Raw meat|Stabbers|Pew pews|Stars|Stabber|Pew pew|Health packs|Health pack|Antidote): \+\$?(\d+) \((\d+) → (\d+)\)$',
    ).firstMatch(detail);
    if (match == null) return _withoutTileNumbers(detail);
    return '${match[1]}: ${match[3]} + ${match[2]}';
  }

  List<String> _additionDetails() {
    final changes = _displaySession.tileSummary?.changes ?? const <String>[];
    return [
      for (final detail in changes)
        if (_formatAddition(detail) != _withoutTileNumbers(detail))
          _formatAddition(detail),
    ];
  }

  List<String> _summaryDetails() {
    final summary = _displaySession.tileSummary;
    if (summary == null) return const [];
    return [...summary.changes.map(_formatAddition)];
  }

  Widget _portalChoiceOverlay() => ColoredBox(
    color: const Color(0xFF101E29),
    child: SafeArea(
      child: LayoutBuilder(
        builder: (context, bounds) {
          final intro = Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.auto_awesome,
                color: Color(0xFFD4BFED),
                size: 40,
              ),
              const SizedBox(height: 12),
              const Text(
                'MYSTERY PORTAL',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 24,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 12),
              const Text(
                'Tap one card. Reveal a trip to the closest portal behind or ahead.',
                textAlign: TextAlign.center,
                style: TextStyle(color: Color(0xFFDDD2ED), fontSize: 15),
              ),
            ],
          );
          final cards = Row(
            children: [
              Expanded(child: _portalMysteryCard(0)),
              const SizedBox(width: 16),
              Expanded(child: _portalMysteryCard(1)),
            ],
          );
          return Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 780),
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: AppTheme.panel,
                    borderRadius: BorderRadius.circular(24),
                    border: Border.all(color: const Color(0xFF9580B1)),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: bounds.maxWidth > 650 && bounds.maxHeight < 600
                        ? Row(
                            children: [
                              Expanded(flex: 4, child: intro),
                              const SizedBox(width: 24),
                              Expanded(flex: 6, child: cards),
                            ],
                          )
                        : Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              intro,
                              const SizedBox(height: 24),
                              cards,
                            ],
                          ),
                  ),
                ),
              ),
            ),
          );
        },
      ),
    ),
  );

  Widget _portalMysteryCard(int index) => Semantics(
    label: 'Mystery portal card ${index + 1}',
    button: true,
    child: Material(
      color: Colors.transparent,
      child: InkWell(
        key: ValueKey('portal-card-$index'),
        onTap: () => widget.controller.choosePortalCard(index),
        borderRadius: BorderRadius.circular(18),
        child: Ink(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            gradient: const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [Color(0xFF7D6A9D), Color(0xFF594C78), Color(0xFF273E50)],
            ),
            border: Border.all(color: const Color(0xFFCBB8DE), width: 2),
            boxShadow: const [
              BoxShadow(color: Color(0x775F3AB4), blurRadius: 18),
            ],
          ),
          child: SizedBox(
            height: 174,
            child: Stack(
              alignment: Alignment.center,
              children: [
                const Positioned(
                  top: 12,
                  left: 12,
                  child: Icon(
                    Icons.auto_awesome,
                    color: Color(0xFFDDD2ED),
                    size: 20,
                  ),
                ),
                const Text(
                  '?',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 78,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                Positioned(
                  bottom: 12,
                  right: 14,
                  child: Text(
                    '${index + 1}',
                    style: const TextStyle(
                      color: Color(0xFFDDD2ED),
                      fontSize: 16,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );

  Widget _shoppingOverlay() {
    final game = widget.controller;
    final player = game.session.currentPlayer;
    final hospital = game.isHospitalShopping;
    return Container(
      color: AppTheme.navy,
      child: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            key: const ValueKey('shop-scroll'),
            padding: const EdgeInsets.all(12),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 860),
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: AppTheme.ivory,
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(color: AppTheme.gold),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        children: [
                          Icon(
                            hospital
                                ? Icons.local_hospital_outlined
                                : Icons.storefront_outlined,
                            color: AppTheme.teal,
                            size: 30,
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              hospital ? 'HOSPITAL SHOP' : 'WEAPON SHOP',
                              style: const TextStyle(
                                color: AppTheme.ink,
                                fontSize: 22,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Text(
                        '${player.name} · Cash: \$${player.cash}. Purchases are optional.${hospital ? ' You are healthy; no treatment fee.' : ''}',
                        style: const TextStyle(color: AppTheme.ink),
                      ),
                      const SizedBox(height: 14),
                      _shopChoices(),
                      if (hospital &&
                          game.session.tileSummary != null &&
                          game.session.tileSummary!.changes.any(
                            (change) =>
                                change.startsWith('Health pack: +') ||
                                change.startsWith('Antidote: +'),
                          )) ...[
                        const SizedBox(height: 12),
                        Text(
                          game.session.tileSummary!.changes
                              .where(
                                (change) =>
                                    change.startsWith('Health pack: +') ||
                                    change.startsWith('Antidote: +'),
                              )
                              .join(' · '),
                          key: const ValueKey('medical-purchase-confirmation'),
                          style: const TextStyle(color: AppTheme.teal),
                        ),
                      ],
                      const SizedBox(height: 12),
                      Text(
                        hospital
                            ? 'A health pack is used automatically after a green mine, a blue mine injury, a lion attack, fire or trap door so you stay on that tile. Antidotes protect against snakes; without one, return to the antidote tile.'
                            : 'Same-tile attacks need a 4, 5 or 6; ranged attacks need a 6 after moving. Each attack uses one weapon and earns 3 stars, with no cash reward. Police within 3 spaces arrest armed or starred players.',
                        style: const TextStyle(
                          color: Color(0xFF475959),
                          fontSize: 12,
                        ),
                      ),
                      const SizedBox(height: 14),
                      FilledButton.icon(
                        style: FilledButton.styleFrom(
                          backgroundColor: AppTheme.teal,
                          foregroundColor: AppTheme.ivory,
                          minimumSize: const Size.fromHeight(50),
                        ),
                        onPressed: game.finishShopping,
                        icon: const Icon(Icons.check_circle_outline),
                        label: const Text('DONE SHOPPING'),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _shopChoices() {
    final game = widget.controller;
    final player = game.session.currentPlayer;
    final choices = game.isHospitalShopping
        ? [
            for (final item in MedicalItem.values)
              _catalogButton(
                label: 'BUY ${item.label.toUpperCase()} · \$${item.price}',
                details:
                    'Owned ${item == MedicalItem.healthPack ? player.inventory.healthPacks : player.inventory.antidotes}'
                    '${player.cash < item.price ? ' · Need \$${item.price - player.cash} more' : ''}',
                icon: item == MedicalItem.healthPack
                    ? Icons.medical_services_outlined
                    : Icons.medication_outlined,
                onPressed: player.cash >= item.price
                    ? () => game.buyMedicalItem(item)
                    : null,
              ),
          ]
        : [
            for (final weapon in WeaponType.values)
              _catalogButton(
                label:
                    'BUY ${weapon.label.toUpperCase()} · \$${game.session.weaponRules.price(weapon)}',
                details:
                    'Range ${weapon.range} · Owned ${game.weaponCount(weapon)}',
                icon: weapon == WeaponType.stabber
                    ? Icons.hardware_outlined
                    : Icons.flash_on_outlined,
                onPressed: player.cash >= game.session.weaponRules.price(weapon)
                    ? () => game.buyWeapon(weapon)
                    : null,
              ),
          ];
    return LayoutBuilder(
      builder: (context, bounds) {
        if (bounds.maxWidth >= 500) {
          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: choices[0]),
              const SizedBox(width: 12),
              Expanded(child: choices[1]),
            ],
          );
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [choices[0], const SizedBox(height: 12), choices[1]],
        );
      },
    );
  }

  Widget _catalogButton({
    required String label,
    required String details,
    required IconData icon,
    required VoidCallback? onPressed,
  }) => OutlinedButton.icon(
    style: OutlinedButton.styleFrom(
      backgroundColor: const Color(0xFFE9DFC9),
      disabledBackgroundColor: const Color(0xFFE9E3D6),
      foregroundColor: AppTheme.ink,
      disabledForegroundColor: const Color(0xFF68716E),
      side: const BorderSide(color: Color(0xFF9B8C6E)),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 16),
      minimumSize: const Size(0, 76),
    ),
    onPressed: onPressed,
    icon: Icon(icon),
    label: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          label,
          textAlign: TextAlign.center,
          style: const TextStyle(fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 4),
        Text(
          details,
          textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 12),
        ),
      ],
    ),
  );

  IconData _detailIcon(String detail) {
    final text = detail.toLowerCase();
    if (text.contains('cash') || text.contains('debt')) {
      return Icons.payments_outlined;
    }
    if (text.contains('turn')) return Icons.hourglass_bottom_rounded;
    if (text.contains('tile') || text.contains('start')) {
      return Icons.location_on_outlined;
    }
    if (text.contains('boat')) return Icons.sailing;
    if (text.contains('raw meat')) return Icons.restaurant;
    if (text.contains('antidote')) return Icons.medication_outlined;
    if (text.contains('health') || text.contains('injur')) {
      return Icons.medical_services_outlined;
    }
    if (text.contains('star')) return Icons.star_rounded;
    return Icons.backpack_outlined;
  }

  Widget _fullScreenMessage({
    required IconData icon,
    required String heading,
    required String subtitle,
    required String highlightedName,
    required Color highlightColor,
    required String buttonLabel,
    required VoidCallback? onPressed,
    String? secondaryButtonLabel,
    VoidCallback? onSecondaryPressed,
    List<String> details = const [],
    Widget? extraContent,
    Widget? illustration,
    bool descriptionOnly = false,
    IconData buttonIcon = Icons.check_circle_outline,
  }) {
    return Container(
      decoration: const BoxDecoration(
        gradient: RadialGradient(
          colors: [Color(0xFF27454B), Color(0xFF101E29)],
          radius: 1.1,
        ),
      ),
      child: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(18),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 540),
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: const Color(0xFFF5EEDD),
                  borderRadius: BorderRadius.circular(28),
                  border: Border.all(color: const Color(0xFFD3BE94), width: 2),
                  boxShadow: const [
                    BoxShadow(
                      color: Colors.black38,
                      blurRadius: 18,
                      offset: Offset(0, 18),
                    ),
                  ],
                ),
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (!descriptionOnly) ...[
                        Row(
                          children: [
                            Icon(
                              Icons.person_rounded,
                              size: 16,
                              color: Color(
                                _displaySession.currentPlayer.colorValue,
                              ),
                            ),
                            const SizedBox(width: 6),
                            Expanded(
                              child: Text(
                                _displaySession.currentPlayer.name,
                                style: const TextStyle(
                                  color: Color(0xFF254849),
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                            ),
                            if (_displaySession.lastDice != null)
                              Text(
                                'ROLL  ${_displaySession.lastDice}',
                                style: const TextStyle(
                                  color: Color(0xFF254849),
                                  fontWeight: FontWeight.w900,
                                  letterSpacing: 1.5,
                                ),
                              ),
                          ],
                        ),
                        const Padding(
                          padding: EdgeInsets.symmetric(vertical: 16),
                          child: Divider(color: Color(0xFFD3BE94), height: 1),
                        ),
                        const SizedBox(height: 12),
                        Text(
                          heading,
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w900,
                            color: Color(0xFF725E3A),
                            letterSpacing: 2,
                          ),
                        ),
                        const SizedBox(height: 12),
                        Text(
                          highlightedName,
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 32,
                            fontWeight: FontWeight.w900,
                            color: const Color(0xFF203C43),
                          ),
                        ),
                        const SizedBox(height: 20),
                        illustration ??
                            Icon(icon, color: highlightColor, size: 54),
                        const SizedBox(height: 20),
                      ],
                      if (descriptionOnly && illustration != null) ...[
                        illustration,
                        const SizedBox(height: 20),
                      ],
                      Text(
                        descriptionOnly
                            ? _conciseOutcome(subtitle)
                            : _withoutTileNumbers(subtitle),
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          fontSize: 17,
                          color: Color(0xFF475959),
                          height: 1.5,
                        ),
                      ),
                      if (details.isNotEmpty) ...[
                        const SizedBox(height: 16),
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: const Color(0xFFE9DFC9),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              for (final detail in details)
                                Padding(
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 3,
                                  ),
                                  child: Row(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Icon(
                                        _detailIcon(detail),
                                        color: Color(0xFF725E3A),
                                        size: 20,
                                      ),
                                      const SizedBox(width: 9),
                                      Expanded(
                                        child: Text(
                                          detail,
                                          style: const TextStyle(
                                            color: Color(0xFF203C43),
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ],
                      const SizedBox(height: 20),
                      if (extraContent != null) ...[
                        extraContent,
                        const SizedBox(height: 20),
                      ],
                      SizedBox(
                        width: double.infinity,
                        child: FilledButton.icon(
                          style: FilledButton.styleFrom(
                            backgroundColor: const Color(0xFF245E5A),
                            foregroundColor: const Color(0xFFFFF4D9),
                            minimumSize: const Size.fromHeight(54),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14),
                            ),
                          ),
                          onPressed: onPressed,
                          icon: Icon(buttonIcon),
                          label: Text(buttonLabel, textAlign: TextAlign.center),
                        ),
                      ),
                      if (secondaryButtonLabel != null) ...[
                        const SizedBox(height: 10),
                        SizedBox(
                          width: double.infinity,
                          child: OutlinedButton.icon(
                            style: OutlinedButton.styleFrom(
                              foregroundColor: const Color(0xFF245E5A),
                              minimumSize: const Size.fromHeight(50),
                            ),
                            onPressed: onSecondaryPressed,
                            icon: const Icon(Icons.hourglass_bottom_rounded),
                            label: Text(
                              secondaryButtonLabel,
                              textAlign: TextAlign.center,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
