import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:k_youtube/features/shopping/domain/shopping_assistant.dart';
import 'package:k_youtube/features/shopping/domain/shopping_preparation.dart';
import 'package:k_youtube/features/shopping/data/shopping_preparation_store.dart';
import 'package:k_youtube/features/shopping/data/shopping_classification_repository.dart';
import 'shopping_assistant_test.dart' show shoppingItem, shoppingList;

void main() {
  test('Spanish ingredient categories keep explicit names and unit dimensions',
      () {
    expect(shoppingCategory('salsa de soya'), ShoppingCategory.seasoning);
    expect(shoppingCategory('진간장'), ShoppingCategory.seasoning);
    expect(shoppingCategory('tomate'), ShoppingCategory.produce);
    expect(shoppingCategory('unknown custom product'), ShoppingCategory.other);
  });
  test('expanded food categories cover marketplace grocery families', () {
    expect(shoppingCategory('두부'), ShoppingCategory.beansTofuNuts);
    expect(shoppingCategory('소면'), ShoppingCategory.noodlesFlour);
    expect(shoppingCategory('김치'), ShoppingCategory.kimchiBanchan);
    expect(shoppingCategory('미원'), ShoppingCategory.spices);
    expect(shoppingCategory('참치캔'), ShoppingCategory.processedFrozen);
    expect(shoppingCategory('커피'), ShoppingCategory.beverages);
  });
  test(
      'approved same ingredient converts metrics but never category or package guesses',
      () {
    final groups = shoppingPurchaseGroups([
      shoppingList(shoppingItem('a', 1, 'kg', name: '대파')),
      shoppingList(shoppingItem('b', 500, 'g', name: '손질 대파')),
      shoppingList(shoppingItem('c', 1, 'pack', name: '손질 대파')),
      shoppingList(shoppingItem('d', 100, 'ml', name: '대파')),
      shoppingList(shoppingItem('e', null, null, name: '손질 대파', review: true)),
    ]);
    expect(mergePreparedGroups(groups, {}), hasLength(5));
    final aliases = {
      for (final g in groups)
        preparationIdentity(g): preparationIdentity(groups.first)
    };
    final merged = mergePreparedGroups(groups, aliases);
    expect(merged, hasLength(4));
    expect(merged.first.neededQuantity, 1500);
    expect(merged.first.unit, 'g');
    expect(merged.first.sources.map((s) => s.item.name), ['대파', '손질 대파']);
    expect(merged[1].unit, 'pack');
    expect(merged[2].unit, 'ml');
    expect(merged.last.neededQuantity, isNull);
  });
  test('AI result must cover requested items without extra fields or IDs', () {
    expect(
        ShoppingClassificationRepository.parseCategories({
          'categories': [
            {'id': '1', 'category': 'protein'},
            {'id': '0', 'category': 'produce'}
          ]
        }, 2),
        [ShoppingCategory.produce, ShoppingCategory.protein]);
    for (final rows in [
      [
        {'id': '2', 'category': 'produce'}
      ],
      [
        {'id': '0', 'category': 'made_up'}
      ],
      [
        {'id': '0', 'category': 'produce', 'quantity': 2}
      ],
      <Map<String, String>>[],
    ]) {
      expect(
          () => ShoppingClassificationRepository.parseCategories(
              {'categories': rows}, 1),
          throwsFormatException);
    }
  });
  test('counting units merge, ambiguous measures and different units do not',
      () {
    final groups = shoppingPurchaseGroups([
      shoppingList(shoppingItem('a', .5, 'stalk', name: '대파')),
      shoppingList(shoppingItem('b', 1, 'stalk', name: '대파')),
      shoppingList(shoppingItem('c', 100, 'g', name: '대파')),
      shoppingList(shoppingItem('d', null, null, name: '대파', review: true)),
      shoppingList(shoppingItem('e', 1, 'pack', name: '대파')),
      shoppingList(shoppingItem('f', 1, 'pack', name: '대파')),
    ]);
    expect(groups, hasLength(5));
    expect(groups.first.neededQuantity, 1.5);
    expect(groups[1].neededQuantity, 100);
    expect(groups[2].neededQuantity, isNull);
  });
  test('exact categories and source fingerprint prevent unsafe reuse', () {
    expect(shoppingCategory('대파'), ShoppingCategory.produce);
    expect(shoppingCategory('진간장'), ShoppingCategory.seasoning);
    expect(shoppingCategory('chicken stock'), ShoppingCategory.other);
    final a =
        shoppingPurchaseGroups([shoppingList(shoppingItem('a', 100, 'g'))])
            .single;
    final b =
        shoppingPurchaseGroups([shoppingList(shoppingItem('a', 200, 'g'))])
            .single;
    expect(preparationIdentity(a), isNot(preparationIdentity(b)));
    expect(a.toBuy(40), 60);
    expect(a.toBuy(150), 0);
  });
  test('unknown amounts need correction or explicit exclusion', () {
    expect(
        const PreparedPurchase(
                category: ShoppingCategory.other, stock: 0, quantity: null)
            .ready,
        isFalse);
    expect(
        const PreparedPurchase(
                category: ShoppingCategory.other,
                stock: 0,
                quantity: null,
                included: false)
            .ready,
        isTrue);
    expect(
        () => PreparedPurchase.fromJson({
              'stock': -1,
              'quantity': 1,
              'included': true,
              'category': 'other'
            }),
        throwsFormatException);
  });
  test('local purchase drafts survive reload and are separated by account',
      () async {
    SharedPreferences.setMockInitialValues({});
    final store = ShoppingPreparationStore();
    await store.write('a', {'confirmed': true, 'edits': {}});
    expect(await ShoppingPreparationStore().read('a'),
        {'confirmed': true, 'edits': {}});
    expect(await store.read('b'), isNull);
  });
}
