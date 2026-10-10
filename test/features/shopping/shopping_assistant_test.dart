import 'package:flutter_test/flutter_test.dart';
import 'package:k_youtube/features/kitchen/domain/kitchen_models.dart';
import 'package:k_youtube/features/kitchen/domain/shopping_units.dart';
import 'package:k_youtube/features/chef/domain/chef_recipe.dart';
import 'package:k_youtube/features/shopping/domain/shopping_assistant.dart';
import 'package:k_youtube/features/shopping/domain/shopping_cost_import.dart';

KitchenShoppingItem shoppingItem(String id, double? qty, String? unit,
        {String name = 'Tofu',
        bool review = false,
        KitchenShoppingItemStatus status =
            KitchenShoppingItemStatus.pending}) =>
    KitchenShoppingItem(
        id: id,
        listId: 'list-$id',
        name: name,
        ingredientText: '$name original recipe text',
        status: status,
        reviewStatus: review
            ? KitchenShoppingItemReviewStatus.required
            : KitchenShoppingItemReviewStatus.confirmed,
        needsReview: review,
        isChecked: status == KitchenShoppingItemStatus.purchased,
        revision: 2,
        updatedAt: DateTime(2026, 9, 13),
        quantity: qty,
        unit: unit);

KitchenShoppingList shoppingList(KitchenShoppingItem item) =>
    KitchenShoppingList(
        id: item.listId,
        title: 'Recipe ${item.id}',
        status: 'active',
        items: [item],
        openItemCount: 1);

void main() {
  test(
      'purchase conversion uses standards or explicit package factors, never cooking units',
      () {
    expect(convertPurchaseQuantity(1.2, 'kg', 'g'), 1200);
    expect(convertPurchaseQuantity(1200, 'g', 'kg'), 1.2);
    expect(convertPurchaseQuantity(125, 'g', 'kg'), 0.125);
    expect(convertPurchaseQuantity(1.5, 'l', 'ml'), 1500);
    expect(convertPurchaseQuantity(1500, 'ml', 'l'), 1.5);
    expect(convertPurchaseQuantity(2, 'dozen', 'ea'), 24);
    expect(convertPurchaseQuantity(2, 'pack', 'g'), isNull);
    expect(convertPurchaseQuantity(2, 'pack', 'g', unitsPerOne: 300), 600);
    expect(convertPurchaseQuantity(600, 'g', 'pack', unitsPerOne: 1 / 300), 2);
    expect(convertPurchaseQuantity(1, 'tbsp', 'ml', unitsPerOne: 15), isNull);
    expect(convertPurchaseQuantity(1, 'g', 'ml'), isNull);
    expect(convertPurchaseQuantity(2, 'pack', 'g', unitsPerOne: double.nan),
        isNull);
  });
  test(
      'purchase units exclude cooking measures but legacy records remain readable',
      () {
    expect(purchaseUnits.where((u) => ['tsp', 'tbsp', 'cup'].contains(u.code)),
        isEmpty);
    expect(shoppingUnits.where((u) => ['tsp', 'tbsp', 'cup'].contains(u.code)),
        hasLength(3));
    final oldCookingItem = shoppingItem('old', 1, 'tbsp');
    expect(oldCookingItem.needsIngredientInfo, isTrue);
    expect(
        shoppingPurchaseGroups([shoppingList(oldCookingItem)])
            .single
            .neededQuantity,
        isNull);
    expect(shoppingItem('purchase', 1, 'bottle').needsIngredientInfo, isFalse);
  });
  test(
      'combines metric quantities across selected lists, excludes bought items',
      () {
    final lists = [
      shoppingList(shoppingItem('a', 1, 'kg')),
      shoppingList(shoppingItem('b', 500, 'g', name: ' tofu ')),
      shoppingList(shoppingItem('c', 300, 'g',
          status: KitchenShoppingItemStatus.purchased))
    ];
    final group = shoppingPurchaseGroups(lists).single;
    expect(group.neededQuantity, 1500);
    expect(group.unit, 'g');
    expect(group.toBuy(300), 1200);
    expect(group.packs(300, 500), 3);
    expect(group.toBuy(2000), 0);
    expect(
        shoppingPurchaseGroups(lists, listId: 'list-b').single.neededQuantity,
        500);
    final split = group.allocations(1500, 300);
    expect(split.map((i) => i['quantity']), [875, 625]);
    expect(split.map((i) => i['revision']), [2, 2]);
    expect(group.allocations(0, 1500).every((i) => i['quantity'] == 0), isTrue);
  });
  test(
      'no guessed density, package size, cooking measure or unreviewed quantity',
      () {
    final groups = shoppingPurchaseGroups([
      for (final pair in ['g', 'ml', 'cup', 'pack', 'pack'].indexed)
        shoppingList(shoppingItem('${pair.$1}', 1, pair.$2)),
      shoppingList(shoppingItem('unknown', null, null)),
      shoppingList(shoppingItem('review', 100, 'g', review: true)),
    ]);
    expect(groups, hasLength(7));
    expect(groups.where((g) => g.neededQuantity == null), hasLength(3));
    expect(shoppingConvert(1, 'kg', 'g'), 1000);
    expect(shoppingConvert(1, 'l', 'ml'), 1000);
    expect(shoppingConvert(1, 'cup', 'ml'), isNull);
    expect(shoppingConvert(1, 'pack', 'g'), isNull);
    expect(shoppingConvert(1, 'g', 'ml'), isNull);
  });
  test('inventory is a reference only, ambiguous lots require manual review',
      () {
    final group =
        shoppingPurchaseGroups([shoppingList(shoppingItem('a', 500, 'g'))])
            .single;
    const stock =
        KitchenIngredient(id: 'stock', name: 'TOFU', quantity: 0.2, unit: 'kg');
    expect(group.knownStock([stock]), 200);
    expect(group.toBuy(0), 500);
    expect(group.knownStock([stock, stock]), isNull);
    expect(
        group.knownStock([
          const KitchenIngredient(
              id: 's', name: 'Tofu', quantity: 1, unit: 'pack')
        ]),
        isNull);
  });
  test(
      'allocation preserves exact rounded purchase quantity and handles zero weights',
      () {
    final group = shoppingPurchaseGroups([
      for (var i = 0; i < 3; i++) shoppingList(shoppingItem('$i', 1, 'ea'))
    ]).single;
    for (final amount in [0.0, 1.0, 3.5, 0.01, 0.125, 0.000125]) {
      final split = group.allocations(amount, 0);
      expect(split.fold<double>(0, (s, i) => s + (i['quantity'] as double)),
          closeTo(amount, 0.0000001));
    }
    expect(group.allocations(1, 3).map((i) => i['quantity']), [1, 0, 0]);
    expect(() => group.allocations(double.nan, 0), throwsFormatException);
    expect(group.packs(0, 0), isNull);
  });
  test(
      'external links reject credentials, private hosts, schemes and command URLs',
      () {
    for (final bad in [
      'javascript:alert(1)',
      'intent://pay',
      'http://shop.example.com',
      'https://user:password@shop.example.com/item',
      'https://localhost/a',
      'https://127.0.0.1/a',
      'https://[::1]/',
      'https://store.internal/a',
      'https://shop.example.com:8443/a',
      'https://shop.example.com/\nitem'
    ]) {
      expect(shoppingProductUri(bad), isNull, reason: bad);
    }
    expect(
        shoppingProductUri('https://shop.example.com/item?q=tofu'), isNotNull);
    final uri = shoppingSearchUri(ShoppingSearchStore.naver, '두부 & 우유');
    expect(uri.queryParameters['query'], '두부 & 우유');
    expect(uri.host, 'search.shopping.naver.com');
  });
  test('shopping links preserve language and shopper-selected pack terms', () {
    final coupang = shoppingSearchUri(ShoppingSearchStore.coupang, ' 김치 & 소면 ',
        specification: ' 500g  2개 ', mobile: true);
    expect(coupang.host, 'www.coupang.com');
    expect(coupang.path, '/np/search');
    expect(coupang.queryParameters, {'q': '김치 & 소면 500g 2개'});
    final naver = shoppingSearchUri(ShoppingSearchStore.naver, ' 춘장 & 소스 ',
        specification: ' 500g  업소용 ', mobile: true);
    expect(naver.host, 'msearch.shopping.naver.com');
    expect(naver.queryParameters, {'query': '춘장 & 소스 500g 업소용'});
    final google =
        shoppingSearchUri(ShoppingSearchStore.web, '두부', languageCode: 'ko');
    expect(google.queryParameters, {'q': '두부', 'tbm': 'shop', 'hl': 'ko'});
    final en = shoppingSearchUri(ShoppingSearchStore.web, 'tofu',
        specification: 'organic 500g', languageCode: 'en');
    expect(en.queryParameters['q'], 'tofu organic 500g');
    expect(en.queryParameters['hl'], 'en');
    expect(shoppingProductUri(en.toString()), isNotNull);
    expect(() => shoppingSearchUri(ShoppingSearchStore.naver, '  '),
        throwsFormatException);
    expect(() => shoppingSearchQuery('a' * 251), throwsFormatException);
    expect(() => shoppingSearchQuery('tofu', specification: 'a' * 121),
        throwsFormatException);
  });
  test(
      'cost import preserves recipe usage/yield and requires same name and currency',
      () {
    const ingredient = ChefIngredient(
        id: 'tofu',
        name: 'Tofu',
        quantity: 150,
        unit: ChefUnit.g,
        yieldPercent: 80,
        purchaseUnit: ChefUnit.each,
        purchaseUnitInUsageUnits: 300);
    final record = ShoppingPurchaseRecord(
        id: 'r',
        name: 'Tofu',
        quantity: 600,
        unit: 'g',
        currency: 'KRW',
        amount: 4500,
        createdAt: DateTime(2026));
    final changed = chefIngredientWithPurchase(ingredient, record, 'KRW');
    expect(changed.quantity, 150);
    expect(changed.yieldPercent, 80);
    expect(changed.purchaseQuantity, 600);
    expect(changed.purchasePrice, 4500);
    expect(changed.purchaseUnitInUsageUnits, isNull);
    expect(changed.cost(1), 1406.25);
    expect(() => chefIngredientWithPurchase(ingredient, record, 'USD'),
        throwsFormatException);
  });
}
