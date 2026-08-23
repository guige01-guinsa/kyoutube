import 'package:flutter_test/flutter_test.dart';
import 'package:k_youtube/features/ingredient_search/domain/shopping_plan.dart';

void main() {
  test('defaults available ingredients to unselected', () {
    final plan = ShoppingPlanBuilder.build(
      recipeIngredients: <String>[
        '감자 2개',
        '양파 1개',
        '돼지고기 300g',
        '고추장 1큰술',
      ],
      availableIngredients: <String>[
        '감자',
        '양파',
      ],
    );

    expect(plan.availableItems.length, 2);
    expect(plan.neededItems.length, 2);

    expect(
      plan.availableItems.every((item) => item.selected == false),
      isTrue,
    );

    expect(
      plan.neededItems.every((item) => item.selected),
      isTrue,
    );

    expect(plan.selectedCount, 2);
  });

  test('allows user to include an available ingredient', () {
    final plan = ShoppingPlanBuilder.build(
      recipeIngredients: <String>['감자 2개', '양파 1개'],
      availableIngredients: <String>['감자'],
    );

    final updated = plan.toggle('감자');

    expect(updated.selectedCount, 2);
    expect(
      updated.selectedItems.map((item) => item.normalizedName),
      containsAll(<String>['감자', '양파']),
    );
  });

  test('allows user to deselect a needed ingredient', () {
    final plan = ShoppingPlanBuilder.build(
      recipeIngredients: <String>['감자 2개', '양파 1개'],
      availableIngredients: <String>[],
    );

    final updated = plan.toggle('감자');

    expect(updated.selectedCount, 1);
    expect(updated.selectedItems.single.normalizedName, '양파');
  });
}
