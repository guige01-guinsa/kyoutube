import 'ingredient_matcher.dart';

enum ShoppingPlanItemAvailability {
  available,
  needed,
}

class ShoppingPlanItem {
  const ShoppingPlanItem({
    required this.rawIngredientText,
    required this.normalizedName,
    required this.availability,
    required this.selected,
    this.quantity,
    this.unit,
    this.needsReview = false,
  });

  final String rawIngredientText;
  final String normalizedName;
  final ShoppingPlanItemAvailability availability;
  final bool selected;
  final double? quantity;
  final String? unit;
  final bool needsReview;

  bool get isAvailable =>
      availability == ShoppingPlanItemAvailability.available;

  bool get isNeeded => availability == ShoppingPlanItemAvailability.needed;

  ShoppingPlanItem copyWith({
    bool? selected,
  }) {
    return ShoppingPlanItem(
      rawIngredientText: rawIngredientText,
      normalizedName: normalizedName,
      availability: availability,
      selected: selected ?? this.selected,
      quantity: quantity,
      unit: unit,
      needsReview: needsReview,
    );
  }
}

class ShoppingPlan {
  const ShoppingPlan({
    required this.items,
  });

  final List<ShoppingPlanItem> items;

  List<ShoppingPlanItem> get availableItems =>
      items.where((item) => item.isAvailable).toList(growable: false);

  List<ShoppingPlanItem> get neededItems =>
      items.where((item) => item.isNeeded).toList(growable: false);

  List<ShoppingPlanItem> get selectedItems =>
      items.where((item) => item.selected).toList(growable: false);

  int get selectedCount => selectedItems.length;

  bool get hasSelectedItems => selectedItems.isNotEmpty;

  ShoppingPlan toggle(String normalizedName) {
    return ShoppingPlan(
      items: items
          .map(
            (item) => item.normalizedName == normalizedName
                ? item.copyWith(selected: !item.selected)
                : item,
          )
          .toList(growable: false),
    );
  }
}

class ShoppingPlanBuilder {
  const ShoppingPlanBuilder._();

  static final RegExp _amountPattern = RegExp(
    r'(\d{1,3}(?:,\d{3})+|\d+\s+\d+/\d+|\d+/\d+|\d+(?:\.\d+)?)\s*'
    r'(킬로그램|키로그램|밀리리터|리터|그램|'
    r'큰술|큰스푼|밥숟가락|작은술|작은스푼|티스푼|컵|종이컵|'
    r'개|알|대|쪽|장|봉지|봉|팩|포|병|캔|'
    r'tbsp|tsp|tablespoons?|teaspoons?|cups?|oz|lb|lbs|'
    r'cucharadas?|cucharaditas?|tazas?|gramos?|mililitros?|litros?|'
    r'kg|ml|cc|g|l|T|t)',
    caseSensitive: false,
  );

  static final RegExp _rangeWithUnit = RegExp(
    r'(?:\d+(?:\.\d+)?|[½⅓⅔¼¾⅛⅜⅝⅞])\s*(?:~|-|–|—)\s*'
    r'(?:\d+(?:\.\d+)?|[½⅓⅔¼¾⅛⅜⅝⅞])\s*[^\s]*',
  );

  static _IngredientAmount? _parseAmount(String text) {
    const fractions = <String, String>{
      '½': '1/2',
      '⅓': '1/3',
      '⅔': '2/3',
      '¼': '1/4',
      '¾': '3/4',
      '⅛': '1/8',
      '⅜': '3/8',
      '⅝': '5/8',
      '⅞': '7/8',
    };
    final normalized = text.replaceAllMapped(
      RegExp('[½⅓⅔¼¾⅛⅜⅝⅞]'),
      (match) => ' ${fractions[match[0]]}',
    );
    // A range or a multiplied package needs a human choice. Do not silently
    // use the last number as the shopping amount.
    if (_rangeWithUnit.hasMatch(normalized) || normalized.contains('×')) {
      return null;
    }
    final match = _amountPattern.firstMatch(normalized);
    if (match == null) return null;

    final rawQuantity = match.group(1)!;
    final mixedParts = rawQuantity.trim().split(RegExp(r'\s+'));
    final whole = mixedParts.length == 2 ? double.parse(mixedParts.first) : 0;
    final parts = mixedParts.last.split('/');
    final double? quantity;
    if (parts.length == 2) {
      final numerator = double.tryParse(parts[0]);
      final denominator = double.tryParse(parts[1]);
      quantity = numerator == null || denominator == null || denominator == 0
          ? null
          : whole + numerator / denominator;
    } else {
      quantity = double.tryParse(rawQuantity.replaceAll(',', ''));
    }
    if (quantity == null || quantity <= 0 || !quantity.isFinite) return null;

    final rawUnit = match.group(2)!;
    final unit = rawUnit == 'T'
        ? 'tbsp'
        : rawUnit == 't'
            ? 'tsp'
            : switch (rawUnit.toLowerCase()) {
                '개' || '알' => 'ea',
                '큰술' ||
                '큰스푼' ||
                '밥숟가락' ||
                'tbsp' ||
                'tablespoon' ||
                'tablespoons' ||
                'cucharada' ||
                'cucharadas' =>
                  'tbsp',
                '작은술' ||
                '작은스푼' ||
                '티스푼' ||
                'tsp' ||
                'teaspoon' ||
                'teaspoons' ||
                'cucharadita' ||
                'cucharaditas' =>
                  'tsp',
                '컵' || '종이컵' || 'cup' || 'cups' || 'taza' || 'tazas' => 'cup',
                '대' => 'stalk',
                '쪽' => 'clove',
                '장' => 'slice',
                '봉' || '봉지' || '팩' || '포' => 'pack',
                '병' => 'bottle',
                '캔' => 'can',
                '킬로그램' || '키로그램' => 'kg',
                '그램' || 'gramo' || 'gramos' => 'g',
                '밀리리터' || 'mililitro' || 'mililitros' => 'ml',
                '리터' || 'litro' || 'litros' => 'l',
                _ => rawUnit.toLowerCase(),
              };

    return _IngredientAmount(quantity, unit);
  }

  static _IngredientAmount? _mergeAmounts(
    List<_IngredientAmount?> values,
  ) {
    if (values.isEmpty || values.any((value) => value == null)) return null;
    final amounts = values.cast<_IngredientAmount>();
    final units = amounts.map((value) => value.unit).toSet();

    if (units.length == 1) {
      return _IngredientAmount(
        amounts.fold(0, (sum, value) => sum + value.quantity),
        amounts.first.unit,
      );
    }
    if (units.every(<String>{'g', 'kg'}.contains)) {
      return _IngredientAmount(
        amounts.fold(
          0,
          (sum, value) =>
              sum +
              (value.unit == 'kg' ? value.quantity * 1000 : value.quantity),
        ),
        'g',
      );
    }
    if (units.every(<String>{'ml', 'l'}.contains)) {
      return _IngredientAmount(
        amounts.fold(
          0,
          (sum, value) =>
              sum +
              (value.unit == 'l' ? value.quantity * 1000 : value.quantity),
        ),
        'ml',
      );
    }
    return null;
  }

  static ShoppingPlan build({
    required List<String> recipeIngredients,
    required List<String> availableIngredients,
  }) {
    final result = IngredientMatcher.match(
      recipeIngredients: recipeIngredients,
      availableIngredients: availableIngredients,
    );

    final groups = <String, List<IngredientRequirement>>{};
    for (final requirement in result.requirements) {
      groups
          .putIfAbsent(
            requirement.normalizedName,
            () => <IngredientRequirement>[],
          )
          .add(requirement);
    }

    final items = groups.entries.map((entry) {
      final requirements = entry.value;
      final rawTexts =
          requirements.map((item) => item.rawText).toSet().toList();
      final amounts = requirements
          .map((requirement) => _parseAmount(requirement.rawText))
          .toList(growable: false);
      final mergedAmount = _mergeAmounts(amounts);
      final requiresEvidenceReview =
          requirements.any((requirement) => requirement.requiresReview);
      final allAvailable =
          requirements.every((requirement) => requirement.isAvailable);
      final needsReview = requiresEvidenceReview || mergedAmount == null;

      return ShoppingPlanItem(
        rawIngredientText: rawTexts.join(' / '),
        normalizedName: entry.key,
        availability: allAvailable && !requiresEvidenceReview
            ? ShoppingPlanItemAvailability.available
            : ShoppingPlanItemAvailability.needed,
        selected: !allAvailable || requiresEvidenceReview,
        quantity: mergedAmount?.quantity,
        unit: mergedAmount?.unit,
        needsReview: needsReview,
      );
    }).toList(growable: false);

    return ShoppingPlan(items: items);
  }
}

class _IngredientAmount {
  const _IngredientAmount(this.quantity, this.unit);

  final double quantity;
  final String unit;
}
