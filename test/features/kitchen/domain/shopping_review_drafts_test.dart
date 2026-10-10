import 'package:flutter_test/flutter_test.dart';
import 'package:k_youtube/features/kitchen/domain/shopping_review_drafts.dart';

ShoppingReviewDraftItem _item({
  String id = 'item-1',
  bool selected = true,
  String unit = 'ea',
  String name = '감자',
  String ingredientText = '감자 2개',
  double quantity = 2,
}) {
  return ShoppingReviewDraftItem(
    localId: id,
    ingredientText: ingredientText,
    name: name,
    quantityInput: quantity.toString(),
    quantity: quantity,
    unit: unit,
    selected: selected,
  );
}

ShoppingReviewDraft _draft(List<ShoppingReviewDraftItem> items) {
  return ShoppingReviewDraft(
    schemaVersion: shoppingReviewDraftSchemaVersion,
    draftId: 'draft-1',
    sourceRecipeId: 'public:recipe-1',
    createIdempotencyKey: 'key-1',
    createdAt: DateTime.utc(2026, 1, 1),
    updatedAt: DateTime.utc(2026, 1, 1),
    items: items,
  );
}

void main() {
  test('selected defaults to true for legacy JSON drafts', () {
    final item = ShoppingReviewDraftItem.fromJson(<String, dynamic>{
      'local_id': 'item-1',
      'ingredient_text': '감자 2개',
      'name': '감자',
      'quantity_input': '2',
      'quantity': 2,
      'unit': 'ea',
    });

    expect(item.selected, isTrue);
  });

  test('selected is persisted in JSON', () {
    final item = _item(selected: false);

    expect(item.toJson()['selected'], isFalse);
  });

  test('accepts a packaging purchase unit without conversion', () {
    final draft = _draft(<ShoppingReviewDraftItem>[
      _item(unit: 'bottle'),
    ]);

    expect(() => draft.validate(forSubmission: true), returnsNormally);
  });

  test('accepts expanded purchase packaging units without conversion', () {
    for (final unit in <String>['carton', 'case', 'net', 'pouch']) {
      final draft = _draft(<ShoppingReviewDraftItem>[_item(unit: unit)]);

      expect(() => draft.validate(forSubmission: true), returnsNormally);
    }
  });

  test('submission ignores deselected items but requires one selected item',
      () {
    final draft = _draft(<ShoppingReviewDraftItem>[
      _item(id: 'item-1', selected: true),
      _item(id: 'item-2', selected: false),
    ]);

    expect(() => draft.validate(forSubmission: true), returnsNormally);

    final noneSelected = _draft(<ShoppingReviewDraftItem>[
      _item(id: 'item-1', selected: false),
    ]);

    expect(
      () => noneSelected.validate(forSubmission: true),
      throwsFormatException,
    );
  });

  test('legacy duplicate names no longer block submission validation', () {
    final draft = _draft(<ShoppingReviewDraftItem>[
      _item(
          id: 'milk-1',
          name: '우유',
          ingredientText: '우유 50ml',
          quantity: 50,
          unit: 'ml'),
      _item(
          id: 'milk-2',
          name: '우유',
          ingredientText: '우유 250ml',
          quantity: 250,
          unit: 'ml'),
    ]);

    expect(() => draft.validate(forSubmission: true), returnsNormally);
  });

  test('merges compatible duplicate review items before submission', () {
    final items = mergeShoppingReviewItems(<ShoppingReviewDraftItem>[
      _item(
          id: 'milk-1',
          name: '우유',
          ingredientText: '우유 50ml',
          quantity: 50,
          unit: 'ml'),
      _item(
          id: 'milk-2',
          name: '우유',
          ingredientText: '우유 250ml',
          quantity: 250,
          unit: 'ml'),
    ]);

    expect(items, hasLength(1));
    expect(items.single.quantity, 300);
    expect(items.single.unit, 'ml');
    expect(items.single.ingredientText, contains('우유 50ml'));
    expect(items.single.ingredientText, contains('우유 250ml'));
  });

  test('serving changes rescale recipe amounts but keep chosen packages', () {
    final draft = _draft(<ShoppingReviewDraftItem>[
      _item(id: 'rice', quantity: 120, unit: 'g'),
      const ShoppingReviewDraftItem(
          localId: 'eggs',
          ingredientText: '달걀 1개',
          name: '달걀',
          quantityInput: '10',
          quantity: 10,
          unit: 'ea',
          purchaseConfirmed: true),
    ]);

    final scaled = rescaleShoppingReviewDraftServings(draft,
        recipeServings: 2, targetServings: 5);

    expect(scaled.recipeServings, 2);
    expect(scaled.targetServings, 5);
    expect(scaled.items.first.quantity, 300);
    expect(scaled.items.last.quantity, 10);
    expect(scaled.items.last.quantityInput, '10');
  });

  test(
      'legacy drafts default servings to one and invalid servings are rejected',
      () {
    final encoded = _draft(<ShoppingReviewDraftItem>[_item()]).toJson()
      ..remove('recipe_servings')
      ..remove('target_servings');
    final restored = ShoppingReviewDraft.fromJson(encoded);
    expect(restored.recipeServings, 1);
    expect(restored.targetServings, 1);
    expect(
        () => rescaleShoppingReviewDraftServings(restored,
            recipeServings: 0, targetServings: 2),
        throwsFormatException);
  });
}
