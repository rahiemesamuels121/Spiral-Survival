enum WeaponType {
  stabber('Stabber', 5),
  pewPew('Pew pew', 10);

  const WeaponType(this.label, this.range);
  final String label;
  final int range;
}

/// Shop prices are saved with the match, so resumed purchases stay consistent.
class WeaponRules {
  const WeaponRules({this.stabberPrice = 40, this.pewPewPrice = 95});
  final int stabberPrice, pewPewPrice;
  int price(WeaponType type) =>
      type == WeaponType.stabber ? stabberPrice : pewPewPrice;

  Map<String, dynamic> toJson() => {
    'stabberPrice': stabberPrice,
    'pewPewPrice': pewPewPrice,
  };
  factory WeaponRules.fromJson(Map<String, dynamic> json) {
    final stabber = (json['stabberPrice'] as num?)?.toInt() ?? 40;
    final pewPew = (json['pewPewPrice'] as num?)?.toInt() ?? 95;
    if (stabber < 0 || pewPew < 0) {
      throw const FormatException('Weapon prices cannot be negative');
    }
    return WeaponRules(stabberPrice: stabber, pewPewPrice: pewPew);
  }
}
