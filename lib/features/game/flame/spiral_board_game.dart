import 'dart:math' as math;
import 'dart:ui' as ui;
import 'package:flame/components.dart';
import 'package:flame/game.dart';
import 'package:flutter/material.dart';
import '../application/game_controller.dart';
import '../domain/board_definition.dart';
import '../domain/game_session.dart';
import '../domain/player_icon.dart';
import '../presentation/player_avatar.dart';
import '../vector/board_artwork.dart';

/// Flame owns drawing and movement ONLY. The controller owns the rules.
class SpiralBoardGame extends FlameGame {
  SpiralBoardGame({required this.controller})
    : super(camera: CameraComponent());

  final GameController controller;
  final Map<int, PlayerToken> _tokens = {};
  int _lastHandledSequence = 0;
  PlayerToken? _cameraToken;
  double _focusElapsed = 0;
  VoidCallback? _startMovement;
  double? _returnElapsed;
  double _returnZoom = 1;
  final Vector2 _returnPosition = Vector2.all(500);
  final Vector2 _movementFocusFrom = Vector2.all(500);
  final Vector2 _idleFocusFrom = Vector2.all(500);
  Vector2? _idleFocusTarget;
  double _idleFocusElapsed = 0;
  bool _wasReady = false;
  double _manualZoomScale = 1;
  double _movementZoomFrom = 1;

  double get _widthFitZoom => canvasSize.x / 1000;
  double get _minimumZoom => math.min(canvasSize.x, canvasSize.y) / 1000;
  double get _idleZoom =>
      (_widthFitZoom * _manualZoomScale).clamp(_minimumZoom, _widthFitZoom * 4);

  BoardTile? tileAtScreen(Offset point) {
    final offset = Vector2(
      point.dx - canvasSize.x / 2,
      point.dy - canvasSize.y / 2,
    );
    final worldPoint =
        camera.viewfinder.position + offset / camera.viewfinder.zoom;
    for (final tile in controller.board.tiles.reversed) {
      if (BoardArtwork.tileRect(
        tile,
      ).contains(Offset(worldPoint.x, worldPoint.y))) {
        return tile;
      }
    }
    return null;
  }

  void zoomBoard(double factor, {Offset? focalPoint}) {
    if (_cameraToken != null ||
        controller.session.phase != TurnPhase.ready ||
        !factor.isFinite ||
        factor <= 0 ||
        canvasSize.x <= 0) {
      return;
    }
    _idleFocusTarget = null;
    final oldZoom = camera.viewfinder.zoom;
    final zoom = (oldZoom * factor).clamp(_minimumZoom, _widthFitZoom * 4);
    final point = focalPoint ?? Offset(canvasSize.x / 2, canvasSize.y / 2);
    final screenOffset = Vector2(
      point.dx - canvasSize.x / 2,
      point.dy - canvasSize.y / 2,
    );
    final worldPoint = camera.viewfinder.position + screenOffset / oldZoom;
    camera.viewfinder.zoom = zoom;
    camera.viewfinder.position = _focusPosition(
      worldPoint - screenOffset / zoom,
      zoom,
    );
    _manualZoomScale = zoom / _widthFitZoom;
  }

  void fitBoardWidth() {
    if (_cameraToken != null || controller.session.phase != TurnPhase.ready) {
      return;
    }
    _manualZoomScale = 1;
    focusCurrentPlayer();
  }

  void focusCurrentPlayer({bool animate = true}) {
    if (_cameraToken != null || canvasSize.x <= 0) return;
    camera.viewfinder.zoom = _idleZoom;
    final target = _focusPosition(
      _positionForPlayer(
        controller.session.currentPlayer.position,
        controller.session.currentPlayerIndex,
      ),
      _idleZoom,
    );
    if (animate) {
      _idleFocusFrom.setFrom(camera.viewfinder.position);
      _idleFocusTarget = target;
      _idleFocusElapsed = 0;
    } else {
      _idleFocusTarget = null;
      camera.viewfinder.position = target;
    }
  }

  void panBoard(Offset delta) {
    if (_cameraToken != null || controller.session.phase != TurnPhase.ready) {
      return;
    }
    _idleFocusTarget = null;
    camera.viewfinder.position = _focusPosition(
      camera.viewfinder.position -
          Vector2(delta.dx, delta.dy) / camera.viewfinder.zoom,
      camera.viewfinder.zoom,
    );
  }

  @override
  void onGameResize(Vector2 size) {
    super.onGameResize(size);
    if (_cameraToken == null) {
      focusCurrentPlayer(animate: false);
    }
  }

  Vector2 _focusPosition(Vector2 tokenPosition, double zoom) {
    // Keep the board's edges in view while leaving room around the token.
    final halfWidth = canvasSize.x / zoom / 2;
    final halfHeight = canvasSize.y / zoom / 2;
    return Vector2(
      halfWidth >= 500
          ? 500
          : tokenPosition.x.clamp(halfWidth, 1000 - halfWidth),
      halfHeight >= 500
          ? 500
          : tokenPosition.y.clamp(halfHeight, 1000 - halfHeight),
    );
  }

  @override
  void update(double dt) {
    super.update(dt);
    final token = _cameraToken;
    if (token == null) {
      final target = _idleFocusTarget;
      if (target != null) {
        _idleFocusElapsed += dt;
        final t = (_idleFocusElapsed / .4).clamp(0.0, 1.0);
        final eased = Curves.easeInOutCubic.transform(t);
        camera.viewfinder.position =
            _idleFocusFrom + (target - _idleFocusFrom) * eased;
        if (t >= 1) _idleFocusTarget = null;
      }
      return;
    }
    if (_returnElapsed != null) {
      _returnElapsed = _returnElapsed! + dt;
      final t = (_returnElapsed! / .45).clamp(0.0, 1.0);
      final eased = Curves.easeInOutCubic.transform(t);
      camera.viewfinder.zoom = _returnZoom + (_idleZoom - _returnZoom) * eased;
      camera.viewfinder.position =
          _returnPosition +
          (_focusPosition(
                    _positionForPlayer(
                      controller.session.currentPlayer.position,
                      controller.session.currentPlayerIndex,
                    ),
                    _idleZoom,
                  ) -
                  _returnPosition) *
              eased;
      if (t >= 1) {
        _cameraToken = null;
        _returnElapsed = null;
        controller.finishAnimation();
      }
      return;
    }
    _focusElapsed += dt;
    final t = (_focusElapsed / .35).clamp(0.0, 1.0);
    final eased = Curves.easeInOutCubic.transform(t);
    final zoom =
        _movementZoomFrom +
        (math.max(_idleZoom, _widthFitZoom * 2.4) - _movementZoomFrom) * eased;
    camera.viewfinder.zoom = zoom;
    final target = _focusPosition(token.position, zoom);
    if (t < 1) {
      camera.viewfinder.position =
          _movementFocusFrom + (target - _movementFocusFrom) * eased;
    } else {
      // Frame-rate-independent follow also softens teleports and route corners.
      camera.viewfinder.position +=
          (target - camera.viewfinder.position) * (1 - math.exp(-14 * dt));
    }
    if (t >= 1 && _startMovement != null) {
      final start = _startMovement!;
      _startMovement = null;
      start();
    }
  }

  void _returnToPlayer() {
    _returnElapsed = 0;
    _returnZoom = camera.viewfinder.zoom;
    _returnPosition.setFrom(camera.viewfinder.position);
  }

  @override
  Future<void> onLoad() async {
    await super.onLoad();
    focusCurrentPlayer(animate: false);

    await world.add(VectorBoardComponent(controller.board));
    for (final tile in controller.board.tiles) {
      if (tile.type == TileType.portal) {
        await world.add(
          PortalAura(
            tile,
            isActive: () =>
                controller.session.phase == TurnPhase.rolling ||
                controller.session.phase == TurnPhase.animating ||
                controller.session.phase == TurnPhase.portalTravel,
          ),
        );
      }
    }

    for (var i = 0; i < controller.session.players.length; i++) {
      final player = controller.session.players[i];
      final token = PlayerToken(
        number: i + 1,
        icon: player.icon,
        color: Color(player.colorValue),
        position: _positionForPlayer(player.position, i),
      );
      _tokens[i] = token;
      await world.add(token);
    }
  }

  @override
  void onMount() {
    super.onMount();
    // Responsive layout changes can remount the same game without reloading it.
    controller.addListener(_onControllerChanged);
    focusCurrentPlayer(animate: false);
    _onControllerChanged();
  }

  Vector2 _positionOf(BoardTile tile) => Vector2(tile.x * 1000, tile.y * 1000);

  Vector2 _positionForPlayer(int tileIndex, int playerIndex) {
    final tile = controller.board.tiles[tileIndex];
    final angle = playerIndex * math.pi * 2 / 5 - math.pi / 2;
    return _positionOf(tile) +
        Vector2(math.cos(angle) * 12, math.sin(angle) * 12);
  }

  void _onControllerChanged() {
    final ready = controller.session.phase == TurnPhase.ready;
    if (ready && !_wasReady ||
        controller.session.phase == TurnPhase.rolling && _wasReady) {
      focusCurrentPlayer();
    }
    _wasReady = ready;
    final action = controller.lastOutcome;
    final movingIndex = action != null && action.sequence > _lastHandledSequence
        ? action.playerIndex
        : null;
    for (final entry in _tokens.entries) {
      entry.value.setIcon(controller.session.players[entry.key].icon);
      if (entry.key != movingIndex && entry.value != _cameraToken) {
        entry.value.position.setFrom(
          _positionForPlayer(
            controller.session.players[entry.key].position,
            entry.key,
          ),
        );
      }
    }
    if (action == null || action.sequence <= _lastHandledSequence) return;
    _lastHandledSequence = action.sequence;
    if (action.path.isEmpty) {
      controller.finishAnimation();
      return;
    }
    final token = _tokens[action.playerIndex];
    if (token == null) {
      controller.finishAnimation();
      return;
    }
    final route = [
      for (final index in action.path)
        _positionForPlayer(index, action.playerIndex),
    ];
    _cameraToken = token;
    _idleFocusTarget = null;
    _movementFocusFrom.setFrom(camera.viewfinder.position);
    _movementZoomFrom = camera.viewfinder.zoom;
    _focusElapsed = 0;
    _returnElapsed = null;
    final mineDeath =
        action.landedType == TileType.mine && action.path.last == 0;
    final walkingRoute = mineDeath ? route.sublist(0, route.length - 1) : route;
    _startMovement = () => token.walk(walkingRoute, () {
      if (mineDeath) {
        world.add(
          LandingPulse(
            position: token.position.clone(),
            color: const Color(0xFFFF7043),
            label: 'BOOM! YOU DIED',
            onComplete: () {},
          ),
        );
        token.dieAndRespawn(route.last, _returnToPlayer);
        return;
      }
      // A temporary glowing pulse makes cash, jail, portals, and events
      // visually distinct. Effects do not change any gameplay state.
      if (action.landedType != TileType.normal &&
          action.landedType != TileType.start) {
        world.add(
          LandingPulse(
            position: _positionForPlayer(
              controller.session.players[action.playerIndex].position,
              action.playerIndex,
            ),
            color: _effectColor(action.landedType),
            label: action.effectLabel,
            onComplete: _returnToPlayer,
          ),
        );
      } else {
        _returnToPlayer();
      }
    });
  }

  Color _effectColor(TileType type) => switch (type) {
    TileType.cash || TileType.star => const Color(0xFF5CF2A4),
    TileType.snake ||
    TileType.police ||
    TileType.fine ||
    TileType.jail ||
    TileType.goToJail => const Color(0xFFFF6868),
    TileType.antidote => const Color(0xFF5CF2A4),
    TileType.hospital => const Color(0xFF5CF2A4),
    TileType.fire || TileType.trapDoor => const Color(0xFFFF8C56),
    TileType.boat || TileType.sea => const Color(0xFF45D6EF),
    TileType.portal || TileType.confusion => const Color(0xFFA76DFF),
    TileType.event => const Color(0xFFFFD36A),
    TileType.mine => const Color(0xFFFF7043),
    _ => const Color(0xFFE6B65A),
  };

  @override
  void onRemove() {
    controller.removeListener(_onControllerChanged);
    super.onRemove();
  }
}

/// Record immutable board geometry once; frames replay native drawing commands.
class VectorBoardComponent extends PositionComponent {
  VectorBoardComponent(this.board) : super(size: Vector2.all(1000));
  final BoardDefinition board;
  ui.Picture? _picture;

  void _recordBoard() {
    final recorder = ui.PictureRecorder();
    BoardArtwork(board).scene.paint(Canvas(recorder));
    _picture = recorder.endRecording();
  }

  @override
  Future<void> onLoad() async {
    await super.onLoad();
    _recordBoard();
  }

  @override
  void render(Canvas canvas) {
    super.render(canvas);
    if (_picture == null) _recordBoard();
    canvas.drawPicture(_picture!);
  }

  @override
  void onRemove() {
    _picture?.dispose();
    _picture = null;
    super.onRemove();
  }
}

/// Frame-driven portal artwork stays sharp at every camera zoom. Effects sit
/// below tokens and the route overlay and never change the game rules.
class PortalAura extends PositionComponent {
  PortalAura(BoardTile tile, {required this.isActive})
    : _phase = tile.index * .7,
      super(
        position: Vector2(
          BoardArtwork.tileRect(tile).left,
          BoardArtwork.tileRect(tile).top,
        ),
        size: Vector2(
          BoardArtwork.tileRect(tile).width,
          BoardArtwork.tileRect(tile).height,
        ),
        priority: 1,
      );

  final bool Function() isActive;
  double _phase;
  static const _violet = Color(0xFFAD73FF);
  static const _cyan = Color(0xFF80F2FF);

  @override
  void update(double dt) {
    super.update(dt);
    if (isActive()) {
      _phase = (_phase + dt) % (math.pi * 20);
    }
  }

  @override
  void render(Canvas canvas) {
    super.render(canvas);
    // The board already includes the static portal illustration.
    if (!isActive()) return;
    final centre = Offset(size.x / 2, size.y * .34);
    final radius = math.min(size.x - 12, size.y * .56) / 2;
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeWidth = 1.5;
    for (var ring = 0; ring < 2; ring++) {
      paint.color = ring == 0 ? _violet : _cyan;
      canvas.drawArc(
        Rect.fromCircle(center: centre, radius: radius * (1 + ring * .2)),
        _phase * (ring == 0 ? 1.7 : -1.3),
        math.pi * 1.25,
        false,
        paint,
      );
    }
  }
}

class PlayerToken extends CircleComponent {
  PlayerToken({
    required this.number,
    required Color color,
    required super.position,
    PlayerIcon icon = PlayerIcon.number,
  }) : super(
         radius: 17,
         anchor: Anchor.center,
         paint: Paint()..color = color,
         priority: 10,
       ) {
    _caption = TextComponent(anchor: Anchor.center, position: Vector2.all(17));
    add(_caption);
    setIcon(icon);
  }

  final int number;
  late final TextComponent _caption;
  PlayerIcon? _icon;

  void setIcon(PlayerIcon icon) {
    if (_icon == icon) return;
    _icon = icon;
    final symbol = icon.symbol;
    _caption.text = icon == PlayerIcon.number
        ? '$number'
        : String.fromCharCode(symbol.codePoint);
    _caption.textRenderer = TextPaint(
      style: TextStyle(
        fontFamily: icon == PlayerIcon.number ? null : symbol.fontFamily,
        package: icon == PlayerIcon.number ? null : symbol.fontPackage,
        fontSize: 22,
        color: const Color(0xFF101E29),
        fontWeight: FontWeight.w900,
      ),
    );
  }

  final List<Vector2> _queue = [];
  Vector2? _from;
  Vector2? _to;
  Vector2? _previous;
  bool _firstStep = true;
  Vector2? _respawnAt;
  double _deathElapsed = 0;
  double _elapsed = 0;
  VoidCallback? _onComplete;
  static const double secondsPerSpace = 0.32;

  void walk(List<Vector2> steps, VoidCallback onComplete) {
    _queue
      ..clear()
      ..addAll(steps);
    _firstStep = true;
    _previous = null;
    _onComplete = onComplete;
    _beginNextStep();
  }

  void _beginNextStep() {
    if (_queue.isEmpty) {
      _from = null;
      _to = null;
      final done = _onComplete;
      _onComplete = null;
      done?.call();
      return;
    }
    _previous = _from?.clone();
    _from = position.clone();
    _to = _queue.removeAt(0);
    _elapsed = 0;
  }

  void dieAndRespawn(Vector2 destination, VoidCallback onComplete) {
    _respawnAt = destination.clone();
    _deathElapsed = 0;
    _onComplete = onComplete;
  }

  @override
  void update(double dt) {
    super.update(dt);
    if (_respawnAt != null) {
      _deathElapsed += dt;
      final t = (_deathElapsed / .95).clamp(0.0, 1.0);
      if (t < .5) {
        scale.setAll(1 - Curves.easeInCubic.transform(t * 2));
      } else {
        position.setFrom(_respawnAt!);
        scale.setAll(Curves.easeOutCubic.transform((t - .5) * 2));
      }
      if (t >= 1) {
        _respawnAt = null;
        scale.setAll(1);
        final done = _onComplete;
        _onComplete = null;
        done?.call();
      }
      return;
    }
    if (_from == null || _to == null) return;
    _elapsed += dt;
    // Carry spare frame time into the next segment instead of losing it.
    while (_from != null && _to != null) {
      final t = (_elapsed / secondsPerSpace).clamp(0.0, 1.0);
      final start = _from!;
      final end = _to!;
      final incoming = _firstStep ? Vector2.zero() : (end - _previous!) * .5;
      final outgoing = _queue.isEmpty
          ? Vector2.zero()
          : (_queue.first - start) * .5;
      final t2 = t * t;
      final t3 = t2 * t;
      // Hermite tangents keep velocity continuous through adjacent spaces.
      position.setFrom(
        start * (2 * t3 - 3 * t2 + 1) +
            incoming * (t3 - 2 * t2 + t) +
            end * (-2 * t3 + 3 * t2) +
            outgoing * (t3 - t2),
      );
      if (t < 1) break;
      position.setFrom(end);
      final remainder = _elapsed - secondsPerSpace;
      _firstStep = false;
      _beginNextStep();
      _elapsed = remainder;
    }
  }
}

/// A short-lived, frame-driven ring and caption. No external assets needed.
class LandingPulse extends PositionComponent {
  LandingPulse({
    required super.position,
    required this.color,
    required this.label,
    required this.onComplete,
  }) : super(size: Vector2.all(160), anchor: Anchor.center, priority: 9);

  final Color color;
  final String label;
  final VoidCallback onComplete;
  double _age = 0;
  bool _finished = false;
  static const double _duration = 1.1;

  @override
  void update(double dt) {
    super.update(dt);
    _age += dt;
    if (_age >= _duration && !_finished) {
      _finished = true;
      onComplete();
      removeFromParent();
    }
  }

  @override
  void render(Canvas canvas) {
    super.render(canvas);
    final progress = (_age / _duration).clamp(0.0, 1.0);
    final centre = const Offset(80, 80);
    for (var ring = 0; ring < 3; ring++) {
      final phase = (progress + ring / 3) % 1.0;
      canvas.drawCircle(
        centre,
        22 + 52 * phase,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = (5 - phase * 3).clamp(1, 5).toDouble()
          ..color = color.withValues(
            alpha: (1 - phase) * (1 - progress) * 0.85,
          ),
      );
    }
    // Render labels just long enough to read on a phone.
    final painter = TextPainter(
      text: TextSpan(
        text: label,
        style: TextStyle(
          color: color.withValues(alpha: 1 - progress),
          fontSize: 21,
          fontWeight: FontWeight.w900,
          shadows: const [Shadow(color: Colors.black, blurRadius: 5)],
        ),
      ),
      maxLines: 1,
      textDirection: TextDirection.ltr,
    )..layout(maxWidth: 150);
    painter.paint(canvas, Offset(80 - painter.width / 2, 5 - 25 * progress));
  }
}
