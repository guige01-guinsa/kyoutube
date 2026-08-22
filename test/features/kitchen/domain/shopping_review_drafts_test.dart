import 'package:flutter_test/flutter_test.dart';
import 'package:k_youtube/features/kitchen/domain/shopping_review_drafts.dart';

ShoppingReviewDraftItem _item({
  String id = 'item-1',
  bool selected = true,
}) {
  return ShoppingReviewDraftItem(
    localId: id,
    ingredientText: '감자 2개',
    name: '감자',
    quantityInput: '2',
    quantity: 2,
    unit: 'ea',
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
}
