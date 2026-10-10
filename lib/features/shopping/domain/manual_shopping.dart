import '../../kitchen/domain/shopping_units.dart';

class ManualShoppingItem {
  const ManualShoppingItem(
      {required this.name,
      required this.quantity,
      required this.unit,
      this.specification = ''});
  final String name, unit, specification;
  final double quantity;
  bool get valid =>
      name.trim().isNotEmpty &&
      name.trim().length <= 200 &&
      specification.length <= 120 &&
      isPurchaseUnit(unit) &&
      quantity.isFinite &&
      quantity > 0 &&
      quantity <= 1e9 &&
      quantity == double.parse(quantity.toStringAsFixed(6));
  Map<String, dynamic> toJson() => {
        'name': name.trim(),
        'quantity': quantity,
        'unit': unit,
        'specification': specification.trim()
      };
  factory ManualShoppingItem.fromJson(Map<String, dynamic> json) =>
      ManualShoppingItem(
          name: json['name'] as String,
          quantity: (json['quantity'] as num).toDouble(),
          unit: json['unit'] as String,
          specification: json['specification'] as String? ?? '');
}
