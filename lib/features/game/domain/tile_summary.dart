/// Saved explanation of the last special tile, shown until acknowledged.
class TileSummary {
  const TileSummary({
    required this.title,
    required this.message,
    required this.landedIndex,
    required this.finalPosition,
    required this.changes,
  });

  final String title;
  final String message;
  final int landedIndex;
  final int finalPosition;
  final List<String> changes;

  Map<String, dynamic> toJson() => {
    'title': title,
    'message': message,
    'landedIndex': landedIndex,
    'finalPosition': finalPosition,
    'changes': changes,
  };

  factory TileSummary.fromJson(Map<String, dynamic> json) => TileSummary(
    title: json['title'] as String,
    message: json['message'] as String,
    landedIndex: (json['landedIndex'] as num).toInt(),
    finalPosition: (json['finalPosition'] as num).toInt(),
    changes: (json['changes'] as List).cast<String>(),
  );
}
