/// Supplies available during a hospital visit.
enum MedicalItem {
  healthPack('Health pack', 10),
  antidote('Antidote', 5);

  const MedicalItem(this.label, this.price);
  final String label;
  final int price;
}
