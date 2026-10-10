import 'package:flutter_test/flutter_test.dart';
import 'package:k_youtube/features/ingredient_search/domain/shopping_plan.dart';

void main() {
  test('reads bibimbap quantities including unicode and mixed fractions', () {
    final plan = ShoppingPlanBuilder.build(recipeIngredients: [
      '밥 120g',
      '달걀 1개',
      '당근 ½ 개 (채 썸)',
      '애호박 ½ 개 (채 썸)',
      '진간장 1/2 작은술',
      '참기름 1 큰술',
      '우유 1½ 컵',
      '설탕 1 1/4 컵',
    ], availableIngredients: []);
    expect(plan.items.map((item) => item.quantity),
        [120, 1, 0.5, 0.5, 0.5, 1, 1.5, 1.25]);
    expect(plan.items.map((item) => item.unit),
        ['g', 'ea', 'ea', 'ea', 'tsp', 'tbsp', 'cup', 'cup']);
    expect(plan.items.every((item) => !item.needsReview), isTrue);
    expect(plan.items[2].rawIngredientText, '당근 ½ 개 (채 썸)');
  });

  test('invalid fractions and missing evidence stay reviewable', () {
    final plan = ShoppingPlanBuilder.build(recipeIngredients: [
      '당근 1/0 개',
      '[확인 필요] 밥 120g',
      '[확인 필요] 달걀',
    ], availableIngredients: []);
    expect(plan.items.first.quantity, isNull);
    expect(plan.items.every((item) => item.needsReview), isTrue);
  });
  test('keeps uncertain recipe measures reviewable while preserving names', () {
    final plan = ShoppingPlanBuilder.build(recipeIngredients: [
      '다진마늘 2 스푼',
      '두부 1모',
      '감자 2~3개',
      '우유 200ml × 2팩',
      '육수 1,000ml',
      '간장 1T',
    ], availableIngredients: []);
    expect(plan.items.map((item) => item.normalizedName),
        ['다진마늘', '두부', '감자', '우유', '육수', '간장']);
    expect(plan.items.take(4).every((item) => item.needsReview), isTrue);
    expect(plan.items[4].quantity, 1000);
    expect(plan.items[4].unit, 'ml');
    expect(plan.items.last.quantity, 1);
    expect(plan.items.last.unit, 'tbsp');
  });
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

  test('combines repeated compatible quantities into one shopping item', () {
    final plan = ShoppingPlanBuilder.build(
      recipeIngredients: <String>['우유 50ml', '우유 250ml'],
      availableIngredients: <String>[],
    );

    expect(plan.items, hasLength(1));
    expect(plan.items.single.normalizedName, '우유');
    expect(plan.items.single.quantity, 300);
    expect(plan.items.single.unit, 'ml');
    expect(plan.items.single.needsReview, isFalse);
  });

  test('keeps incompatible duplicate units as one reviewable item', () {
    final plan = ShoppingPlanBuilder.build(
      recipeIngredients: <String>['간장 2큰술', '간장 1병'],
      availableIngredients: <String>[],
    );

    expect(plan.items, hasLength(1));
    expect(plan.items.single.quantity, isNull);
    expect(plan.items.single.unit, isNull);
    expect(plan.items.single.needsReview, isTrue);
    expect(plan.items.single.selected, isTrue);
  });

  test('keeps unverified ingredients selected for explicit review', () {
    final plan = ShoppingPlanBuilder.build(
      recipeIngredients: <String>['[확인 필요] 우유 250ml'],
      availableIngredients: <String>['우유'],
    );

    expect(plan.items.single.isNeeded, isTrue);
    expect(plan.items.single.selected, isTrue);
    expect(plan.items.single.needsReview, isTrue);
  });
}
