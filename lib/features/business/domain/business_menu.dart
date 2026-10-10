import 'dart:math' as math;

class MenuIngredient {
  const MenuIngredient(
      {required this.name,
      required this.quantity,
      required this.unit,
      this.spec = ''});
  final String name, unit, spec;
  final double quantity;
  factory MenuIngredient.fromJson(Map<String, dynamic> j) => MenuIngredient(
      name: j['name'] as String,
      quantity: (j['quantity'] as num).toDouble(),
      unit: j['unit'] as String,
      spec: j['spec'] as String? ?? '');
  Map<String, dynamic> toJson() =>
      {'name': name, 'quantity': quantity, 'unit': unit, 'spec': spec};
  String get label =>
      '$name ${menuNumber(quantity)} $unit${spec.isEmpty ? '' : ' ($spec)'}';
}

bool menuQuantityValid(double n) =>
    n.isFinite && n >= 0 && n <= 1e9 && n == double.parse(n.toStringAsFixed(6));

String menuNumber(num n) => n == n.roundToDouble()
    ? n.toInt().toString()
    : n
        .toStringAsFixed(6)
        .replaceFirst(RegExp(r'0+$'), '')
        .replaceFirst(RegExp(r'\.$'), '');

class BusinessMenuItem {
  const BusinessMenuItem(
      {required this.id,
      required this.revision,
      required this.name,
      required this.category,
      required this.description,
      required this.price,
      required this.currency,
      required this.recipeId,
      required this.recipeRevision,
      required this.snapshot,
      required this.status});
  final String id, name, category, description, currency, recipeId, status;
  final int revision, recipeRevision;
  final double? price;
  final Map<String, dynamic> snapshot;
  factory BusinessMenuItem.fromJson(Map<String, dynamic> j) => BusinessMenuItem(
      id: j['id'] as String,
      revision: (j['revision'] as num).toInt(),
      name: j['name'] as String,
      category: j['category'] as String,
      description: j['description'] as String,
      price: j['price_confirmed'] == false
          ? null
          : (j['price'] as num?)?.toDouble(),
      currency: j['currency'] as String,
      recipeId: j['recipe_id'] as String,
      recipeRevision: (j['recipe_revision'] as num).toInt(),
      snapshot: Map<String, dynamic>.from(j['recipe_snapshot'] as Map),
      status: j['is_candidate'] == true ? 'candidate' : j['status'] as String);
  Map<String, dynamic> get editData => {
        'name': name,
        'category': category,
        'description': description,
        'price': price,
        'currency': currency,
        'recipe_id': recipeId,
        'recipe_revision': recipeRevision,
        'status': status
      };
}

class MenuPurchaseSource {
  const MenuPurchaseSource(
      {required this.kind,
      required this.id,
      required this.revision,
      required this.title,
      required this.servings});
  final String kind, id, title;
  final int revision;
  final double servings;
  Map<String, dynamic> toJson() =>
      {'kind': kind, 'id': id, 'revision': revision, 'servings': servings};
}

class MenuPurchaseAdjustment {
  MenuPurchaseAdjustment(this.requirement);
  final Map<String, dynamic> requirement;
  double? stock, incoming, packSize;
  String packUnit = '';
  bool confirmed = false, include = true;
  double get requiredQuantity => (requirement['required'] as num).toDouble();
  bool get valid =>
      [stock, incoming, packSize]
          .every((n) => n != null && menuQuantityValid(n)) &&
      packSize! >= 0.000001 &&
      packUnit.trim().isNotEmpty &&
      packUnit.trim().length <= 30;
  int _micros(double n) => (n * 1000000).round();
  int get _netMicros => math.max(0,
      _micros(requiredQuantity) - _micros(stock ?? 0) - _micros(incoming ?? 0));
  double get net => _netMicros / 1000000;
  int? get packs => valid
      ? (_netMicros + _micros(packSize!) - 1) ~/ _micros(packSize!)
      : null;
  double? get overage => packs == null
      ? null
      : math.max(0, packs! * _micros(packSize!) - _netMicros) / 1000000;
  Map<String, dynamic> toJson() => {
        'key': requirement['key'],
        'stock': stock,
        'incoming': incoming,
        'pack_size': packSize,
        'pack_unit': packUnit.trim(),
        'confirmed': confirmed,
        'include': include
      };
}

/// Human-readable comparison of selected snapshots. New saves create a new revision.
List<String> changedRecipeFields(
        Map<String, dynamic> before, Map<String, dynamic> after) =>
    [
      for (final key in ['title', 'servings', 'ingredients', 'steps', 'notes'])
        if (before[key] != after[key]) key,
    ];
