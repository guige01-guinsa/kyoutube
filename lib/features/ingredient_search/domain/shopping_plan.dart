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
  });

  final String rawIngredientText;
  final String normalizedName;
  final ShoppingPlanItemAvailability availability;
  final bool selected;

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

  static ShoppingPlan build({
    required List<String> recipeIngredients,
    required List<String> availableIngredients,
  }) {
    final result = IngredientMatcher.match(
      recipeIngredients: recipeIngredients,
      availableIngredients: availableIngredients,
    );

    return ShoppingPlan(
      items: result.requirements
          .map(
            (requirement) => ShoppingPlanItem(
              rawIngredientText: requirement.rawText,
              normalizedName: requirement.normalizedName,
              availability: requirement.isAvailable
                  ? ShoppingPlanItemAvailability.available
                  : ShoppingPlanItemAvailability.needed,
              // 냉장고에 보유한 재료는 기본 미선택,
              // 부족 재료는 기본 장보기 선택.
              selected: !requirement.isAvailable,
            ),
          )
          .toList(growable: false),
    );
  }
}
