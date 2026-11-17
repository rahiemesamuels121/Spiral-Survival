/// Shared supplies at one hospital, replenished by elapsed real time.
class HospitalStock {
  HospitalStock({required this.updatedAt, this.kits = 2}) {
    if (kits < 0) throw const FormatException('Invalid hospital stock.');
  }

  static const refillInterval = Duration(minutes: 5);
  int kits;
  DateTime updatedAt;

  int _refills(DateTime now) => now.isBefore(updatedAt)
      ? 0
      : now.difference(updatedAt).inMilliseconds ~/
            refillInterval.inMilliseconds;

  int available(DateTime now) => kits + _refills(now);

  Duration untilNext(DateTime now) {
    final elapsed = now.difference(updatedAt).inMilliseconds;
    return Duration(
      milliseconds:
          refillInterval.inMilliseconds -
          (elapsed < 0 ? 0 : elapsed % refillInterval.inMilliseconds),
    );
  }

  bool take(DateTime now) {
    final refills = _refills(now);
    kits += refills;
    updatedAt = updatedAt.add(refillInterval * refills);
    if (kits == 0) return false;
    kits--;
    return true;
  }

  Map<String, dynamic> toJson() => {
    'kits': kits,
    'updatedAt': updatedAt.toUtc().toIso8601String(),
  };

  factory HospitalStock.fromJson(Map<String, dynamic> json) => HospitalStock(
    kits: (json['kits'] as num).toInt(),
    updatedAt: DateTime.parse(json['updatedAt'] as String),
  );
}
