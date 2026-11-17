/// Stable names are stored in saves. Legacy cosmetic values remain readable;
/// new matches offer only the three character classes below.
enum PlayerIcon {
  number,
  star,
  rocket,
  shield,
  paw,
  bolt,
  diamond,
  flag,
  secretAgent,
  swimmer;

  static const selectable = [paw, secretAgent, swimmer];
  bool get isSelectable => selectable.contains(this);
  bool get ignoresLions => this == paw;
  bool get canSwim => this == swimmer;
  int get weaponRangeBonus => this == secretAgent ? 3 : 0;
  int secretSocietyPrice(int price) =>
      this == secretAgent ? (price - 50).clamp(0, price) : price;
}
