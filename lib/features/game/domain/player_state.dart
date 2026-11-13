import 'player_inventory.dart';

class PlayerState {
  PlayerState({
    required this.id,
    required this.name,
    required this.colorValue,
    this.position = 0,
    int cash = 10,
    PlayerInventory? inventory,
    this.debt = 0,
    this.skipTurns = 0,
    this.reverseNextMove = false,
  }) : inventory = inventory ?? PlayerInventory(cash: cash);

  final String id;
  final String name;
  final int colorValue;
  int position;
  final PlayerInventory inventory;
  int get cash => inventory.cash;
  set cash(int value) => inventory.cash = value;
  int debt;
  int skipTurns;
  bool reverseNextMove;

  /// Fines cannot create negative cash; unpaid amounts become debt.
  void pay(int amount) {
    if (amount <= 0) return;
    if (cash >= amount) {
      cash -= amount;
    } else {
      debt += amount - cash;
      cash = 0;
    }
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'colorValue': colorValue,
    'position': position,
    'cash': cash,
    'inventory': inventory.toJson(),
    'debt': debt,
    'skipTurns': skipTurns,
    'reverseNextMove': reverseNextMove,
  };

  factory PlayerState.fromJson(Map<String, dynamic> json) => PlayerState(
    id: json['id'] as String,
    name: json['name'] as String,
    colorValue: json['colorValue'] as int,
    position: json['position'] as int? ?? 0,
    cash: json['cash'] as int? ?? 100,
    inventory: json['inventory'] == null
        ? null
        : PlayerInventory.fromJson(
            Map<String, dynamic>.from(json['inventory'] as Map),
          ),
    debt: json['debt'] as int? ?? 0,
    skipTurns: json['skipTurns'] as int? ?? 0,
    reverseNextMove: json['reverseNextMove'] as bool? ?? false,
  );
}
