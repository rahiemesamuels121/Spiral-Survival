/// Immutable, ordered route definition. This file contains NO screen or Flame
/// code; coordinates and effects come from the board JSON asset.
enum TileType {
  start,
  normal,
  sea,
  surf,
  boat,
  antidote,
  rawMeat,
  lion,
  snake,
  cash,
  police,
  fine,
  jail,
  goToJail,
  mine,
  portal,
  setBack,
  moveForward,
  shop,
  event,
  confusion,
  star,
  hospital,
  secretSociety,
  fire,
  trapDoor,
  finish,
}

enum MineColor { red, blue, green }

class BoardTile {
  static const artworkValues = [
    'none',
    'spiral',
    'boat',
    'water',
    'skull',
    'antidote',
    'snake',
    'cash',
    'police',
    'jail',
    'mine',
    'portal',
    'back',
    'forward',
    'shop',
    'dice',
    'star',
    'stop',
    'jet',
    'fire',
    'diamond',
    'train',
    'surf',
    'lion',
    'rawMeat',
    'hospital',
    'secretSociety',
    'trapDoor',
    'confusion',
    'startFlag',
  ];
  const BoardTile({
    required this.index,
    required this.x,
    required this.y,
    this.type = TileType.normal,
    this.label = '',
    this.segment = '',
    this.amount = 0,
    this.destination,
    this.consumesAntidote = false,
    this.width,
    this.height,
    this.fillColor,
    this.textColor,
    this.artwork,
    this.mineColor = MineColor.red,
  });

  /// Coordinates normalized to [0, 1] against the ORIGINAL board image.
  final int index;
  final double x;
  final double y;
  final TileType type;
  final String label;
  final String segment;
  final int amount;
  final int? destination;
  final bool consumesAntidote;
  final double? width;
  final double? height;
  final int? fillColor;
  final int? textColor;
  final String? artwork;
  final MineColor mineColor;
  bool get isWater => type == TileType.sea || type == TileType.surf;

  Map<String, dynamic> toJson() => {
    'index': index,
    'x': x,
    'y': y,
    'type': type.name,
    'label': label,
    'segment': segment,
    'amount': amount,
    if (type == TileType.mine) 'mineColor': mineColor.name,
    'destination': type == TileType.police || type == TileType.portal
        ? null
        : destination,
    'consumesAntidote': consumesAntidote,
    if (width != null) 'width': width,
    if (height != null) 'height': height,
    if (fillColor != null) 'fillColor': fillColor,
    if (textColor != null) 'textColor': textColor,
    if (artwork != null) 'artwork': artwork,
  };

  BoardTile withChanges(Map<String, dynamic> changes) =>
      BoardTile.fromJson({...toJson(), ...changes});

  String get typeLabel => switch (type) {
    TileType.start => 'START',
    TileType.normal => 'NORMAL',
    TileType.sea => 'SEA',
    TileType.surf => 'SURF',
    TileType.boat => 'COLLECT BOAT',
    TileType.antidote => 'COLLECT ANTIDOTE',
    TileType.rawMeat => 'COLLECT RAW MEAT',
    TileType.lion => 'LION · RAW MEAT REQUIRED',
    TileType.snake => 'SNAKE · ANTIDOTE REQUIRED',
    TileType.jail => 'JAIL · MISS ${amount > 0 ? amount : 1} TURN(S)',
    TileType.goToJail => 'GO TO JAIL',
    TileType.setBack => 'GO BACK $amount SPACES',
    TileType.moveForward => 'MOVE FORWARD $amount SPACES',
    TileType.portal => 'PORTAL · PICK A MYSTERY CARD',
    TileType.cash => 'COLLECT \$$amount',
    TileType.police => 'POLICE',
    TileType.fine => 'FINE',
    TileType.mine => switch (mineColor) {
      MineColor.red => 'RED MINE · DEATH',
      MineColor.blue => 'BLUE MINE · DEATH OR INJURY',
      MineColor.green => 'GREEN MINE · HEALTH PACK OR HOSPITAL',
    },
    TileType.shop => 'SHOP',
    TileType.event => 'EVENT CARD',
    TileType.confusion => 'CONFUSION · NEXT MOVE BACKWARDS',
    TileType.star => 'COLLECT STAR',
    TileType.hospital => 'HOSPITAL',
    TileType.secretSociety => 'SECRET SOCIETY',
    TileType.fire => 'FIRE · GO TO HOSPITAL',
    TileType.trapDoor => 'TRAP DOOR · MISS ONE TURN',
    TileType.finish => 'FINISH',
  };

  factory BoardTile.fromJson(Map<String, dynamic> json) {
    // Legacy spiral spaces use the same choice and travel rules as portals.
    final spiral =
        json['type'] != 'start' &&
        json['type'] != 'finish' &&
        (json['type'] == 'spiral' ||
            json['artwork'] == 'spiral' ||
            (json['label'] as String? ?? '').trim().toUpperCase() == 'SPIRAL');
    return BoardTile(
      index: (json['index'] as num).toInt(),
      x: (json['x'] as num).toDouble(),
      y: (json['y'] as num).toDouble(),
      // Keep previously saved custom boards and JSON imports readable.
      type: spiral
          ? TileType.portal
          : json['type'] == 'normal' &&
                (json['label'] as String? ?? '').trim().toUpperCase() == 'SURF'
          ? TileType.surf
          : json['type'] == 'death'
          ? TileType.sea
          : json['type'] == 'loan'
          ? TileType.mine
          : TileType.values.byName(json['type'] as String),
      label: spiral
          ? 'PORTAL'
          : json['type'] == 'loan'
          ? 'MINE'
          : (json['type'] == 'death' || json['type'] == 'sea') &&
                (json['label'] == 'INSTANT DEATH · RETURN TO START' ||
                    json['label'] == 'RESTART')
          ? 'SEA'
          : json['label'] as String? ?? '',
      mineColor: MineColor.values.byName(json['mineColor'] as String? ?? 'red'),
      segment: json['segment'] as String? ?? '',
      amount: spiral || json['type'] == 'loan'
          ? 0
          : (json['amount'] as num?)?.toInt() ?? 0,
      destination:
          spiral || json['type'] == 'police' || json['type'] == 'portal'
          ? null
          : (json['destination'] as num?)?.toInt(),
      consumesAntidote: json['consumesAntidote'] as bool? ?? false,
      width: (json['width'] as num?)?.toDouble(),
      height: (json['height'] as num?)?.toDouble(),
      fillColor: (json['fillColor'] as num?)?.toInt(),
      textColor: (json['textColor'] as num?)?.toInt(),
      artwork: spiral
          ? 'portal'
          : json['artwork'] == 'loan'
          ? 'mine'
          : json['artwork'] as String?,
    );
  }
}

class BoardDefinition {
  BoardDefinition(this.tiles, {this.id = 'test-board'}) {
    if (tiles.length < 3) {
      throw ArgumentError('Board must have at least 3 tiles');
    }
    if (tiles.first.type != TileType.start ||
        tiles.last.type != TileType.finish) {
      throw ArgumentError('Board must begin with START and end with FINISH');
    }
    for (var i = 0; i < tiles.length; i++) {
      final tile = tiles[i];
      if (tile.index != i) {
        throw ArgumentError('Tile indices must be sequential from zero');
      }
      if (i > 0 &&
          i < tiles.length - 1 &&
          (tile.type == TileType.start || tile.type == TileType.finish)) {
        throw ArgumentError(
          'Only the first and last spaces may be START and FINISH',
        );
      }
      if (tile.artwork != null &&
          !BoardTile.artworkValues.contains(tile.artwork)) {
        throw ArgumentError('Tile $i has an unknown artwork symbol');
      }
      for (final color in [tile.fillColor, tile.textColor]) {
        if (color != null && (color < 0 || color > 0xFFFFFFFF)) {
          throw ArgumentError('Tile $i color must be a 32-bit color');
        }
      }
      if (!tile.x.isFinite ||
          !tile.y.isFinite ||
          tile.x < 0 ||
          tile.x > 1 ||
          tile.y < 0 ||
          tile.y > 1) {
        throw ArgumentError('Tile $i has invalid normalized coordinates');
      }
      if (tile.destination != null &&
          (tile.destination! < 0 || tile.destination! >= tiles.length)) {
        throw ArgumentError('Tile $i has an invalid portal destination');
      }
      if (tile.amount < 0 || tile.amount > 1000000) {
        throw ArgumentError('Tile $i amount must be between 0 and 1000000');
      }
      for (final dimension in [tile.width, tile.height]) {
        if (dimension != null &&
            (!dimension.isFinite || dimension < .02 || dimension > .2)) {
          throw ArgumentError('Tile $i size must be between 2% and 20%');
        }
      }
      if ((tile.type == TileType.setBack ||
              tile.type == TileType.moveForward) &&
          tile.amount < 1) {
        throw ArgumentError('Tile $i needs a positive number of spaces');
      }
      if (tile.type == TileType.goToJail &&
          (tile.destination == null ||
              tiles[tile.destination!].type != TileType.jail)) {
        throw ArgumentError('Tile $i must target a JAIL tile');
      }
      if (tile.type == TileType.police &&
          !tiles.any((candidate) => candidate.type == TileType.jail)) {
        throw ArgumentError('POLICE tile $i requires a JAIL on the board');
      }
      if (tile.type == TileType.snake &&
          (tile.destination == null ||
              tiles[tile.destination!].type != TileType.antidote)) {
        throw ArgumentError('SNAKE tile $i must target an ANTIDOTE tile');
      }
      if (tile.type == TileType.mine &&
          tile.mineColor != MineColor.red &&
          (tile.destination == null ||
              tiles[tile.destination!].type != TileType.hospital)) {
        throw ArgumentError('Mine $i must target a HOSPITAL tile');
      }
      if ((tile.type == TileType.fire ||
              tile.type == TileType.trapDoor ||
              tile.type == TileType.lion) &&
          (tile.destination == null ||
              tiles[tile.destination!].type != TileType.hospital)) {
        throw ArgumentError('Tile $i must target a HOSPITAL tile');
      }
    }
  }

  final String id;
  final List<BoardTile> tiles;
  int get lastIndex => tiles.length - 1;

  Map<String, dynamic> toJson() => {
    'id': id,
    'version': 2,
    'title': 'Spiral Survival — Editable Vector Board',
    'startIndex': 0,
    'finishIndex': lastIndex,
    'tiles': tiles.map((tile) => tile.toJson()).toList(),
  };

  factory BoardDefinition.fromJson(Map<String, dynamic> json) {
    if (json['version'] != 2) {
      throw const FormatException('Unsupported board map version');
    }
    final values = json['tiles'] as List<dynamic>;
    final tiles = values
        .map(
          (tile) => BoardTile.fromJson(Map<String, dynamic>.from(tile as Map)),
        )
        .toList(growable: false);
    if ((json['startIndex'] as num).toInt() != 0 ||
        (json['finishIndex'] as num).toInt() != tiles.length - 1) {
      throw const FormatException(
        'START / FINISH indices must match the route',
      );
    }
    return BoardDefinition(tiles, id: json['id'] as String);
  }
}
