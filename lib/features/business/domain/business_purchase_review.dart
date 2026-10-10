import 'business_workspace.dart';
import 'business_menu.dart';

/// Search only the records already loaded for the current business/page.
bool businessPurchaseMatches(BusinessRecord record, String query) {
  final words = query.trim().toLowerCase().split(RegExp(r'\s+'));
  final lines = (record.data['lines'] as List? ?? const []).whereType<Map>();
  final text = [
    record.title,
    record.data['supplier'],
    record.data['delivery_date'],
    for (final line in lines) ...[line['name'], line['spec']],
  ].join(' ').toLowerCase();
  return words.every(text.contains);
}

/// Exact physical conversions only. Packages, cooking measures and densities
/// require a separately confirmed product-specific basis.
class BusinessUnit {
  const BusinessUnit(this.code, this.ko, this.en, this.dimension, this.factor);
  final String code, ko, en, dimension;
  final double factor;
}

const businessStandardUnits = [
  BusinessUnit('g', '무게 · g', 'Weight · g', 'mass', 1),
  BusinessUnit('kg', '무게 · kg', 'Weight · kg', 'mass', 1000),
  BusinessUnit('ml', '부피 · mL', 'Volume · mL', 'volume', 1),
  BusinessUnit('l', '부피 · L', 'Volume · L', 'volume', 1000),
  BusinessUnit('개', '개수 · 개', 'Count · each', 'count', 1),
];

BusinessUnit? businessStandardUnit(String value) {
  final code = switch (value.trim().toLowerCase()) {
    '그램' => 'g',
    '킬로그램' => 'kg',
    '밀리리터' => 'ml',
    '리터' => 'l',
    'ea' || 'each' || 'pcs' => '개',
    final v => v,
  };
  return businessStandardUnits.where((u) => u.code == code).firstOrNull;
}

double? businessUnitFactor(String from, String to) {
  if (from.trim().isEmpty || to.trim().isEmpty) return null;
  if (from.trim().toLowerCase() == to.trim().toLowerCase()) return 1;
  final left = businessStandardUnit(from), right = businessStandardUnit(to);
  return left != null && right != null && left.dimension == right.dimension
      ? left.factor / right.factor
      : null;
}

double? businessConvertQuantity(double quantity, String from, String to) {
  final factor = businessUnitFactor(from, to);
  if (!quantity.isFinite || quantity < 0 || factor == null) return null;
  final result = quantity * factor;
  if (!result.isFinite || result > 1e9) return null;
  // Server accepts at most six decimal places. Never silently round quantities.
  final rounded = double.parse(result.toStringAsFixed(6));
  if ((rounded - result).abs() > 1e-9 || (quantity > 0 && rounded == 0)) {
    return null;
  }
  return rounded;
}

String businessBaseUnit(String unit) =>
    switch (businessStandardUnit(unit)?.dimension) {
      'mass' => 'g',
      'volume' => 'ml',
      'count' => '개',
      _ => unit.trim(),
    };

MenuIngredient? standardizeBusinessIngredient(MenuIngredient line) {
  final unit = businessBaseUnit(line.unit);
  final quantity = businessConvertQuantity(line.quantity, line.unit, unit);
  if (quantity == null || quantity <= 0) return null;
  return MenuIngredient(
      name: line.name, spec: line.spec, quantity: quantity, unit: unit);
}
