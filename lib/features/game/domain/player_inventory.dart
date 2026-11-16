/// Items and spending money carried by one player.
class PlayerInventory {
  PlayerInventory({
    this.boats = 0,
    this.antidotes = 0,
    this.healthPacks = 0,
    this.rawMeat = 0,
    this.cash = 10,
    this.stabbers = 0,
    this.pewPews = 0,
    this.stars = 0,
  }) {
    if (boats < 0 ||
        antidotes < 0 ||
        healthPacks < 0 ||
        rawMeat < 0 ||
        cash < 0 ||
        stabbers < 0 ||
        pewPews < 0 ||
        stars < 0) {
      throw ArgumentError('Inventory amounts cannot be negative');
    }
  }

  int boats;
  int antidotes;
  int healthPacks;
  int rawMeat;
  int cash;
  int stabbers;
  int pewPews;
  int stars;
  bool get hasWeapons => stabbers > 0 || pewPews > 0;
  bool get hasPoliceRisk => hasWeapons || stars > 0;

  Map<String, dynamic> toJson() => {
    'boats': boats,
    'antidotes': antidotes,
    'healthPacks': healthPacks,
    'rawMeat': rawMeat,
    'cash': cash,
    'stabbers': stabbers,
    'pewPews': pewPews,
    'stars': stars,
  };

  factory PlayerInventory.fromJson(Map<String, dynamic> json) =>
      PlayerInventory(
        boats: (json['boats'] as num?)?.toInt() ?? 0,
        antidotes: (json['antidotes'] as num?)?.toInt() ?? 0,
        healthPacks: (json['healthPacks'] as num?)?.toInt() ?? 0,
        rawMeat: (json['rawMeat'] as num?)?.toInt() ?? 0,
        cash: (json['cash'] as num?)?.toInt() ?? 100,
        stabbers: (json['stabbers'] as num?)?.toInt() ?? 0,
        pewPews: (json['pewPews'] as num?)?.toInt() ?? 0,
        stars: (json['stars'] as num?)?.toInt() ?? 0,
      );
}
