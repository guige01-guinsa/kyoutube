import '../../../core/format/user_number.dart';
import '../../kitchen/domain/shopping_units.dart';
import '../../recipes/domain/recipe.dart';

class ChefUnit {
  const ChefUnit._(
      this.name, this.label, this.dimension, this.factor, this.category);
  final String name, label, dimension, category;
  final double factor;
  static const g = ChefUnit._('g', 'g', 'mass', 1, '무게');
  static const kg = ChefUnit._('kg', 'kg', 'mass', 1000, '무게');
  static const ml = ChefUnit._('ml', 'mL', 'volume', 1, '부피');
  static const l = ChefUnit._('l', 'L', 'volume', 1000, '부피');
  static const each = ChefUnit._('each', '개', 'count', 1, '개수');
  static final List<ChefUnit> values = [
    g,
    kg,
    ml,
    l,
    each,
    for (final unit in shoppingUnits)
      if (!const {'g', 'kg', 'ml', 'l', 'ea'}.contains(unit.code))
        ChefUnit._(
            unit.code, unit.label, 'unit:${unit.code}', 1, unit.category),
  ];
  bool get isCustom => name.startsWith('custom:');
  factory ChefUnit.custom(String label) {
    final value = label.trim();
    return ChefUnit._('custom:$value', value, 'custom:$value', 1, '직접 입력');
  }
  static ChefUnit parse(String? value) {
    if (value == null) return g;
    if (value == 'ea' || value == '개') return each;
    for (final unit in values) {
      if (unit.name == value) return unit;
    }
    return ChefUnit.custom(
        value.startsWith('custom:') ? value.substring(7) : value);
  }

  String displayLabel(bool english) => !english || isCustom
      ? label
      : name == 'each'
          ? 'ea'
          : name == 'l'
              ? 'L'
              : name == 'ml'
                  ? 'mL'
                  : name.replaceAll('_', ' ');
  double? convert(double value, ChefUnit to) =>
      dimension == to.dimension ? value * factor / to.factor : null;
  @override
  bool operator ==(Object other) => other is ChefUnit && name == other.name;
  @override
  int get hashCode => name.hashCode;
}

double? chefNumber(Object? value) =>
    value is num && value.isFinite ? value.toDouble() : null;
double? chefInputNumber(String value) => parseUserNumber(value);

String chefFormat(double? value) {
  if (value == null || !value.isFinite) return '—';
  return value.toStringAsFixed(6).replaceFirst(RegExp(r'\.?0+$'), '');
}

class ChefIngredient {
  const ChefIngredient(
      {required this.id,
      required this.name,
      this.quantity,
      this.unit = ChefUnit.g,
      this.purchaseQuantity,
      this.purchaseUnit = ChefUnit.g,
      this.purchasePrice,
      this.purchaseUnitInUsageUnits,
      this.yieldPercent = 100});
  final String id, name;

  /// Edible quantity for the base recipe, after trimming.
  final double? quantity, purchaseQuantity, purchasePrice;
  final ChefUnit unit, purchaseUnit;

  /// Usage units per one purchase unit, e.g. 400 g per pack.
  final double? purchaseUnitInUsageUnits;
  final double yieldPercent;

  factory ChefIngredient.fromText(String id, String text) {
    final trailing =
        RegExp(r'^(.+?)\s+(\d+(?:\.\d+)?|\d+/\d+)\s*(kg|g|ml|l|L|ea|개)\s*$');
    final leading =
        RegExp(r'^(\d+(?:\.\d+)?|\d+/\d+)\s*(kg|g|ml|l|L|ea|개)\s+(.+)$');
    final tail = trailing.firstMatch(text.trim());
    final head = leading.firstMatch(text.trim());
    final match = tail ?? head;
    if (match == null ||
        RegExp(r'[\[\]~–]|\d\s*-\s*\d|\d\s+\d+/|\d,\d|\d\s*[x×]\s*\d')
            .hasMatch(text)) {
      return ChefIngredient(id: id, name: text);
    }
    final name = match.group(tail != null ? 1 : 3)!;
    final raw = match.group(tail != null ? 2 : 1)!;
    final pieces = raw.split('/').map(double.parse).toList();
    final amount =
        pieces.length == 2 ? pieces.first / pieces.last : pieces.first;
    if (!amount.isFinite || amount <= 0) {
      return ChefIngredient(id: id, name: text);
    }
    final rawUnit = match.group(tail != null ? 3 : 2)!.toLowerCase();
    final unit = switch (rawUnit) {
      'kg' => ChefUnit.kg,
      'ml' => ChefUnit.ml,
      'l' => ChefUnit.l,
      'ea' || '개' => ChefUnit.each,
      _ => ChefUnit.g,
    };
    return ChefIngredient(
        id: id, name: name, quantity: amount, unit: unit, purchaseUnit: unit);
  }

  factory ChefIngredient.fromJson(Map<String, dynamic> json) => ChefIngredient(
      id: json['id'] as String,
      name: json['name'] as String,
      quantity: chefNumber(json['quantity']),
      unit: ChefUnit.parse(json['unit']),
      purchaseQuantity: chefNumber(json['purchaseQuantity']),
      purchaseUnit: ChefUnit.parse(json['purchaseUnit']),
      purchasePrice: chefNumber(json['purchasePrice']),
      purchaseUnitInUsageUnits: chefNumber(json['purchaseUnitInUsageUnits']),
      yieldPercent: chefNumber(json['yieldPercent']) ?? 100);
  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'quantity': quantity,
        'unit': unit.name,
        'purchaseQuantity': purchaseQuantity,
        'purchaseUnit': purchaseUnit.name,
        'purchasePrice': purchasePrice,
        'purchaseUnitInUsageUnits': purchaseUnitInUsageUnits,
        'yieldPercent': yieldPercent
      };

  double? neededPurchase(double ratio) {
    if (quantity == null ||
        quantity! <= 0 ||
        yieldPercent <= 0 ||
        yieldPercent > 100) {
      return null;
    }
    return quantity! * ratio / (yieldPercent / 100);
  }

  double? neededPurchaseUnits(double ratio) {
    final amount = neededPurchase(ratio);
    if (amount == null) return null;
    final manual = purchaseUnitInUsageUnits;
    return unit.convert(amount, purchaseUnit) ??
        (manual != null && manual.isFinite && manual > 0
            ? amount / manual
            : null);
  }

  double? cost(double ratio) {
    final converted = neededPurchaseUnits(ratio);
    if (converted == null ||
        purchaseQuantity == null ||
        purchaseQuantity! <= 0 ||
        purchasePrice == null ||
        purchasePrice! < 0) {
      return null;
    }
    return converted / purchaseQuantity! * purchasePrice!;
  }
}

class ChefCostItem {
  const ChefCostItem(
      {required this.id, required this.name, required this.amount});
  final String id, name;
  final double amount;
  factory ChefCostItem.fromJson(Map<String, dynamic> json) => ChefCostItem(
      id: json['id'] as String,
      name: json['name'] as String,
      amount: chefNumber(json['amount'])!);
  Map<String, dynamic> toJson() => {'id': id, 'name': name, 'amount': amount};
}

class ChefRecipe {
  const ChefRecipe(
      {required this.title,
      required this.ingredients,
      required this.steps,
      this.notes = '',
      this.baseServings,
      this.targetServings,
      this.currency = 'KRW',
      this.extraCost = 0,
      this.costItems = const [],
      this.markupPercent = 0,
      this.inputWeight,
      this.outputWeight});
  final String title, steps, notes, currency;
  final List<ChefIngredient> ingredients;
  final double? baseServings, targetServings, inputWeight, outputWeight;
  final double extraCost;
  final List<ChefCostItem> costItems;
  final double markupPercent;
  double? get sellingPrice {
    final cost = portionCost;
    if (cost == null) return null;
    final factor = currency == 'KRW' ? 1 : 100;
    return (cost * (1 + markupPercent / 100) * factor).round() / factor;
  }

  double get totalExtraCost =>
      costItems.fold(extraCost, (sum, item) => sum + item.amount);
  factory ChefRecipe.seed(Recipe recipe, {String currency = 'KRW'}) =>
      ChefRecipe(
          title: recipe.title,
          ingredients: [
            for (var i = 0; i < recipe.ingredients.length; i++)
              ChefIngredient.fromText('import-$i', recipe.ingredients[i])
          ],
          steps: recipe.steps.join('\n'),
          notes: recipe.tips ?? '',
          currency: currency);
  factory ChefRecipe.fromJson(Map<String, dynamic> json) => ChefRecipe(
      title: json['title'] as String,
      steps: json['steps'] as String,
      notes: json['notes'] as String? ?? '',
      currency: json['currency'] as String? ?? 'KRW',
      markupPercent: chefNumber(json['markupPercent']) ?? 0,
      baseServings: chefNumber(json['baseServings']),
      targetServings: chefNumber(json['targetServings']),
      extraCost: chefNumber(
              json[json['schema'] == 2 ? 'legacyExtraCost' : 'extraCost']) ??
          0,
      costItems: (json['costItems'] as List? ?? const [])
          .map((item) =>
              ChefCostItem.fromJson(Map<String, dynamic>.from(item as Map)))
          .toList(growable: false),
      inputWeight: chefNumber(json['inputWeight']),
      outputWeight: chefNumber(json['outputWeight']),
      ingredients: (json['ingredients'] as List)
          .map((item) =>
              ChefIngredient.fromJson(Map<String, dynamic>.from(item as Map)))
          .toList(growable: false));
  Map<String, dynamic> toJson() => {
        'schema': 2,
        'unitFormat': 1,
        'title': title,
        'steps': steps,
        'notes': notes,
        'currency': currency,
        'markupPercent': markupPercent,
        'baseServings': baseServings,
        'targetServings': targetServings,
        'extraCost': totalExtraCost,
        'legacyExtraCost': extraCost,
        'costItems': costItems.map((item) => item.toJson()).toList(),
        'inputWeight': inputWeight,
        'outputWeight': outputWeight,
        'ingredients': ingredients.map((item) => item.toJson()).toList()
      };
  double? get ratio => baseServings != null &&
          baseServings! > 0 &&
          targetServings != null &&
          targetServings! > 0
      ? targetServings! / baseServings!
      : null;
  int get incompleteCosts =>
      ingredients.where((item) => item.cost(1) == null).length;
  double get knownBaseCost =>
      ingredients.fold(0.0, (sum, item) => sum + (item.cost(1) ?? 0));
  double? get batchCost =>
      ratio == null || incompleteCosts > 0 || ingredients.isEmpty
          ? null
          : (knownBaseCost + totalExtraCost) * ratio!;
  double? get portionCost =>
      batchCost == null ? null : batchCost! / targetServings!;
  double? get productionYield =>
      inputWeight == null || inputWeight! <= 0 || outputWeight == null
          ? null
          : outputWeight! / inputWeight! * 100;
  double? get costPer100g => incompleteCosts > 0 ||
          ingredients.isEmpty ||
          outputWeight == null ||
          outputWeight! <= 0
      ? null
      : (knownBaseCost + totalExtraCost) / outputWeight! * 100;
  List<ChefDifference> compare(ChefRecipe other) {
    final before = toJson(), after = other.toJson();
    final result = <ChefDifference>[];
    for (final key in [
      'title',
      'baseServings',
      'targetServings',
      'currency',
      'markupPercent',
      'extraCost',
      'inputWeight',
      'outputWeight',
      'steps',
      'notes'
    ]) {
      if (before[key] != after[key]) {
        result.add(ChefDifference(key, before[key], after[key]));
      }
    }
    final oldItems = {for (final item in ingredients) item.id: item};
    final newItems = {for (final item in other.ingredients) item.id: item};
    for (final id in {...oldItems.keys, ...newItems.keys}) {
      final old = oldItems[id], next = newItems[id];
      if (old == null || next == null) {
        result.add(ChefDifference('ingredient', old?.name, next?.name));
        continue;
      }
      final a = old.toJson(), b = next.toJson();
      for (final key in a.keys.where((key) => key != 'id')) {
        if (a[key] != b[key]) {
          result
              .add(ChefDifference(key, a[key], b[key], ingredient: next.name));
        }
      }
    }
    final oldCosts = {for (final item in costItems) item.id: item};
    final newCosts = {for (final item in other.costItems) item.id: item};
    for (final id in {...oldCosts.keys, ...newCosts.keys}) {
      final old = oldCosts[id], next = newCosts[id];
      if (old == null || next == null) {
        result.add(ChefDifference('costItem', old?.amount, next?.amount,
            ingredient: (next ?? old)!.name));
      } else {
        if (old.name != next.name) {
          result.add(ChefDifference('costName', old.name, next.name));
        }
        if (old.amount != next.amount) {
          result.add(ChefDifference('costAmount', old.amount, next.amount,
              ingredient: next.name));
        }
      }
    }
    return result;
  }
}

class ChefDifference {
  const ChefDifference(this.field, this.before, this.after, {this.ingredient});
  final String field;
  final Object? before, after;
  final String? ingredient;
}

class ChefVersion {
  const ChefVersion(
      {required this.number,
      required this.label,
      required this.note,
      required this.createdAt,
      required this.document});
  final int number;
  final String label, note;
  final DateTime createdAt;
  final ChefRecipe document;
  factory ChefVersion.fromJson(Map<String, dynamic> json) => ChefVersion(
      number: json['version_number'] as int,
      label: json['label'] as String,
      note: json['note'] as String? ?? '',
      createdAt: DateTime.parse(json['created_at'] as String),
      document: ChefRecipe.fromJson(
          Map<String, dynamic>.from(json['document'] as Map)));
}
