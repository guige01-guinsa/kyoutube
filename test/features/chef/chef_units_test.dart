import 'package:flutter_test/flutter_test.dart';
import 'package:k_youtube/features/chef/domain/chef_recipe.dart';

void main() {
  test('custom and categorized units survive documents and versions', () {
    for (final unit in [...ChefUnit.values, ChefUnit.custom('국자')]) {
      final item = ChefIngredient(
          id: 'i',
          name: 'Sauce',
          unit: unit,
          purchaseUnit: unit,
          quantity: 2,
          purchaseQuantity: 4,
          purchasePrice: 1000);
      final restored = ChefIngredient.fromJson(item.toJson());
      expect(restored.unit, unit);
      expect(restored.purchaseUnit, unit);
      expect(restored.cost(1), 500);
    }
    expect(ChefUnit.parse('unfamiliar').label, 'unfamiliar');
    expect(ChefUnit.parse('unfamiliar'), isNot(ChefUnit.g));
  });
  test('manual pack conversion includes yield and serving scale', () {
    final item = ChefIngredient(
        id: 'i',
        name: 'Tofu',
        quantity: 300,
        unit: ChefUnit.g,
        purchaseUnit: ChefUnit.parse('pack'),
        purchaseQuantity: 2,
        purchasePrice: 6000,
        yieldPercent: 75,
        purchaseUnitInUsageUnits: 400);
    expect(item.cost(1), 3000);
    expect(item.cost(2), 6000);
    expect(ChefIngredient.fromJson(item.toJson()).cost(2), 6000);
    final without = ChefIngredient.fromJson(
        {...item.toJson(), 'purchaseUnitInUsageUnits': null});
    expect(without.cost(1), isNull);
    for (final invalid in [0, -1]) {
      expect(
          ChefIngredient.fromJson(
              {...item.toJson(), 'purchaseUnitInUsageUnits': invalid}).cost(1),
          isNull);
    }
  });
  test(
      'known metric conversion takes priority and manual basis appears in comparison',
      () {
    const item = ChefIngredient(
        id: 'i',
        name: 'Flour',
        quantity: 500,
        unit: ChefUnit.g,
        purchaseUnit: ChefUnit.kg,
        purchaseQuantity: 1,
        purchasePrice: 1000,
        purchaseUnitInUsageUnits: 2);
    expect(item.cost(1), 500);
    const before = ChefRecipe(title: 'Test', ingredients: [item], steps: 'Mix');
    final after = ChefRecipe(
        title: 'Test',
        ingredients: [
          ChefIngredient.fromJson(
              {...item.toJson(), 'purchaseUnitInUsageUnits': 3})
        ],
        steps: 'Mix');
    expect(before.compare(after).single.field, 'purchaseUnitInUsageUnits');
  });
}
