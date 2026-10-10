import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:k_youtube/features/chef/domain/chef_recipe.dart';

const carrots = ChefIngredient(
    id: 'carrots',
    name: 'Carrots',
    quantity: 800,
    unit: ChefUnit.g,
    purchaseQuantity: 1,
    purchaseUnit: ChefUnit.kg,
    purchasePrice: 8000,
    yieldPercent: 80);
const formula = ChefRecipe(
    title: 'Carrots',
    ingredients: [carrots],
    steps: 'Trim and cook.',
    baseServings: 4,
    targetServings: 10,
    extraCost: 1000,
    inputWeight: 1000,
    outputWeight: 750);

void main() {
  test(
      'item costs preserve legacy amounts and snapshots without double counting',
      () {
    final legacy = formula.toJson()..['schema'] = 1;
    legacy.remove('costItems');
    legacy.remove('legacyExtraCost');
    final old = ChefRecipe.fromJson(legacy);
    final changed = ChefRecipe.fromJson({
      ...old.toJson(),
      'costItems': [
        const ChefCostItem(id: 'pack', name: 'Packaging', amount: 200).toJson(),
        const ChefCostItem(id: 'labor', name: 'Labor', amount: 300).toJson(),
      ]
    });
    expect(changed.extraCost, 1000);
    expect(changed.totalExtraCost, 1500);
    expect(changed.batchCost, 23750);
    expect(changed.portionCost, 2375);
    expect(changed.costPer100g, closeTo(1266.6666667, 1e-5));
    final saved = ChefRecipe.fromJson(jsonDecode(jsonEncode(changed.toJson())));
    expect(saved.totalExtraCost, 1500);
    expect(saved.toJson()['extraCost'], 1500,
        reason: 'v55 reads the combined amount');
    final edit = ChefRecipe.fromJson({
      ...saved.toJson(),
      'costItems': [
        const ChefCostItem(id: 'pack', name: 'New packaging', amount: 400)
            .toJson(),
      ]
    });
    expect(edit.totalExtraCost, 1400);
    expect(saved.totalExtraCost, 1500);
    expect(saved.compare(edit).map((d) => d.field),
        containsAll(['costName', 'costAmount', 'costItem']));
  });
  test(
      'money input accepts thousands and unambiguous decimal commas',
      () {
    expect(chefInputNumber('1,200.50'), 1200.5);
    expect(chefInputNumber('1,5'), 1.5);
    expect(chefInputNumber('12,00'), 12);
    expect(chefInputNumber('1,500'), 1500);
  });
  test(
      'scales edible quantity and trimming purchase weight without double counting loss',
      () {
    expect(formula.ratio, 2.5);
    expect(carrots.quantity! * formula.ratio!, 2000);
    expect(carrots.neededPurchase(formula.ratio!), 2500);
    expect(carrots.cost(formula.ratio!), 20000);
    expect(formula.batchCost, 22500);
    expect(formula.portionCost, 2250);
    expect(formula.productionYield, 75);
    expect(formula.costPer100g, 1200);
  });
  test('volume cannot be converted to mass without density', () {
    final item =
        ChefIngredient.fromJson({...carrots.toJson(), 'purchaseUnit': 'ml'});
    final doc = ChefRecipe.fromJson({
      ...formula.toJson(),
      'ingredients': [item.toJson()]
    });
    expect(item.cost(1), isNull);
    expect(doc.incompleteCosts, 1);
    expect(doc.batchCost, isNull);
    expect(doc.portionCost, isNull);
  });
  test(
      'unknown prices remain incomplete while explicit free ingredients cost zero',
      () {
    final unknown =
        ChefIngredient.fromJson({...carrots.toJson(), 'purchasePrice': null});
    final free =
        ChefIngredient.fromJson({...carrots.toJson(), 'purchasePrice': 0});
    expect(unknown.cost(1), isNull);
    expect(free.cost(1), 0);
    expect(
        ChefRecipe.fromJson({...formula.toJson(), 'baseServings': null}).ratio,
        isNull);
  });
  test('invalid trimming yield never produces an estimated cost', () {
    for (final yieldValue in [0, -5, 101]) {
      final item = ChefIngredient.fromJson(
          {...carrots.toJson(), 'yieldPercent': yieldValue});
      expect(item.cost(1), isNull);
    }
  });
  test('cooking yield can exceed 100 percent with absorbed water', () {
    final doc =
        ChefRecipe.fromJson({...formula.toJson(), 'outputWeight': 1500});
    expect(doc.productionYield, 150);
    expect(doc.costPer100g, 600);
  });
  test(
      'imports explicit compatible units and leaves uncertain expressions for review',
      () {
    for (final text in ['Flour 1/2 kg', '0.5 kg Flour']) {
      final item = ChefIngredient.fromText('f', text);
      expect(item.name, 'Flour');
      expect(item.quantity, 0.5);
      expect(item.unit, ChefUnit.kg);
    }
    for (final text in [
      'Flour 1-2 kg',
      'Flour 1 1/2 kg',
      'Flour 1,000 g',
      'Flour 2 x 500 g',
      'Flour 2 × 500 g',
      'Flour 0 g',
      '[Inferred] Flour 2 kg',
      'Salt to taste',
      'Flour 2 cups',
      'Flour 1/0 kg'
    ]) {
      final item = ChefIngredient.fromText('f', text);
      expect(item.quantity, isNull, reason: text);
      expect(item.name, text);
    }
  });
  test(
      'restored snapshots preserve historical prices and compare by ingredient identity',
      () {
    final saved = ChefRecipe.fromJson(jsonDecode(jsonEncode(formula.toJson())));
    final updatedItem =
        ChefIngredient.fromJson({...carrots.toJson(), 'purchasePrice': 10000});
    final current = ChefRecipe.fromJson({
      ...formula.toJson(),
      'ingredients': [updatedItem.toJson()],
      'steps': 'Roast instead.'
    });
    final diff = saved.compare(current);
    expect(saved.ingredients.single.purchasePrice, 8000);
    expect(diff.map((d) => d.field), containsAll(['purchasePrice', 'steps']));
    expect(current.portionCost, 2750);
    expect(saved.compare(ChefRecipe.fromJson(saved.toJson())), isEmpty);
  });
  test(
      'formatting keeps whole quantities intact and fractional scaling is not rounded early',
      () {
    expect(chefFormat(1000), '1000');
    expect(chefFormat(0), '0');
    expect(chefFormat(0.125), '0.125');
    expect(chefFormat(0.000125), '0.000125');
    final item =
        ChefIngredient.fromJson({...carrots.toJson(), 'quantity': 1 / 3});
    expect(item.quantity! * 7 / 3, closeTo(7 / 9, 1e-12));
  });
}
