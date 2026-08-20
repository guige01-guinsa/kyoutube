import 'package:flutter_test/flutter_test.dart';

import 'package:k_youtube/features/kitchen/domain/kitchen_models.dart';

Map<String, dynamic> itemJson({
  String status = 'pending',
  String reviewStatus = 'confirmed',
  bool? needsReview,
  bool? isChecked,
}) =>
    <String, dynamic>{
      'id': 'item-1',
      'list_id': 'list-1',
      'name': 'Potato',
      'ingredient_text': '2 kg potato',
      'quantity': 2,
      'unit': 'kg',
      'status': status,
      'review_status': reviewStatus,
      'needs_review': needsReview ?? reviewStatus == 'required',
      'is_checked': isChecked ?? status == 'purchased',
      'revision': 3,
      'updated_at': '2026-01-01T00:00:00Z',
    };

void main() {
  test('parses the canonical reviewed item contract', () {
    final item = KitchenShoppingItem.fromJson(itemJson());
    expect(item.status, KitchenShoppingItemStatus.pending);
    expect(item.reviewStatus, KitchenShoppingItemReviewStatus.confirmed);
    expect(item.needsReview, isFalse);
    expect(item.isChecked, isFalse);
    expect(item.ingredientText, '2 kg potato');
    expect(item.revision, 3);
    expect(item.updatedAt, DateTime.parse('2026-01-01T00:00:00Z'));
  });

  test('parses a canonical shopping list with reviewed items', () {
    final list = KitchenShoppingList.fromJson(<String, dynamic>{
      'id': 'list-1',
      'status': 'active',
      'title': 'Shopping',
      'open_item_count': 1,
      'items': <Map<String, dynamic>>[itemJson()],
    });
    expect(list.id, 'list-1');
    expect(list.items, hasLength(1));
    expect(list.items.single.ingredientText, '2 kg potato');
    expect(list.openItemCount, 1);
  });

  test('supports every canonical status and review status', () {
    for (final status in <String>['pending', 'skipped', 'unavailable']) {
      expect(KitchenShoppingItem.fromJson(itemJson(status: status)).status.name,
          status);
    }
    expect(
      KitchenShoppingItem.fromJson(itemJson(status: 'purchased')).status,
      KitchenShoppingItemStatus.purchased,
    );
    expect(
      KitchenShoppingItem.fromJson(itemJson(reviewStatus: 'required'))
          .reviewStatus,
      KitchenShoppingItemReviewStatus.required,
    );
  });

  test('rejects unknown or inconsistent canonical fields', () {
    expect(() => KitchenShoppingItem.fromJson(itemJson(status: 'unknown')),
        throwsFormatException);
    expect(
        () => KitchenShoppingItem.fromJson(itemJson(reviewStatus: 'unknown')),
        throwsFormatException);
    expect(() => KitchenShoppingItem.fromJson(itemJson(needsReview: true)),
        throwsFormatException);
    expect(() => KitchenShoppingItem.fromJson(itemJson(isChecked: true)),
        throwsFormatException);
    expect(() => KitchenShoppingItem.fromJson({...itemJson(), 'revision': -1}),
        throwsFormatException);
    expect(
        () => KitchenShoppingItem.fromJson(
            {...itemJson(), 'updated_at': 'invalid'}),
        throwsFormatException);
    expect(
        () => KitchenShoppingItem.fromJson(
            {...itemJson()..remove('ingredient_text')}),
        throwsFormatException);
  });
}
