import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:k_youtube/features/auth/application/auth_providers.dart';
import 'package:k_youtube/features/kitchen/application/kitchen_providers.dart';
import 'package:k_youtube/features/recipes/application/recipe_providers.dart';
import 'package:k_youtube/features/shopping/data/purchase_cleanup_repository.dart';
import 'package:k_youtube/features/shopping/data/shopping_assistant_repository.dart';
import 'package:k_youtube/features/shopping/domain/purchase_cleanup.dart';
import 'package:k_youtube/features/shopping/domain/shopping_assistant.dart';
import 'package:k_youtube/features/shopping/presentation/shopping_assistant_page.dart';
import 'shopping_assistant_test.dart' show shoppingItem, shoppingList;

final archivedKeys =
    StateProvider<Set<String>>((_) => {'favorite:old', 'record:receipt'});
const savedProduct = ShoppingFavorite(
    id: 'old',
    ingredientName: '당근',
    unit: 'g',
    productName: '보관한 당근 상품',
    url: 'https://example.test/carrot');
final receipt = ShoppingPurchaseRecord(
    id: 'receipt',
    name: '당근 구매 기록',
    quantity: 750,
    unit: 'g',
    currency: 'KRW',
    amount: 3000,
    createdAt: DateTime(2026, 9, 28));

Future<ProviderContainer> showShopping(WidgetTester tester, int tab) async {
  await tester.pumpWidget(ProviderScope(
      overrides: [
        activeAccountIdProvider.overrideWith((_) => 'owner'),
        purchaseCleanupIndexProvider(null).overrideWith(
            (ref) async => PurchaseCleanupIndex(ref.watch(archivedKeys))),
        shoppingFavoritesProvider.overrideWith((_) async => [savedProduct]),
        shoppingRecordsProvider(null).overrideWith((_) async => [receipt]),
        kitchenShoppingListsProvider.overrideWith((_) async =>
            [shoppingList(shoppingItem('carrot', 200, 'g', name: '당근'))]),
        kitchenIngredientsProvider.overrideWith((_) async => []),
        kitchenSummaryProvider.overrideWith((_) async => {}),
      ],
      child: MaterialApp(
        locale: const Locale('ko'),
        supportedLocales: const [Locale('ko')],
        localizationsDelegates: const [
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate
        ],
        home: ShoppingAssistantPage(initialTab: tab),
      )));
  await tester.pumpAndSettle();
  return ProviderScope.containerOf(
      tester.element(find.byType(ShoppingAssistantPage)));
}

void main() {
  test('a stale archive index never hides an active request', () {
    const index = PurchaseCleanupIndex({'request:r', 'business_purchase:b'});
    for (final status in ['review', 'approved', 'sent', 'accepted']) {
      expect(index.hidesRequest('request', 'r', status), isFalse);
      expect(index.hidesRequest('business_purchase', 'b', status), isFalse);
    }
    expect(index.hidesRequest('request', 'r', 'draft'), isTrue);
    expect(index.hidesRequest('business_purchase', 'b', 'received'), isTrue);
  });
  testWidgets(
      'archived products disappear from saved items and return after restore',
      (tester) async {
    final container = await showShopping(tester, 2);
    expect(find.text('보관한 당근 상품'), findsNothing);
    expect(find.textContaining('표시할 저장 상품이 없습니다.'), findsOneWidget);
    expect(
        await container.read(shoppingFavoritesProvider.future), [savedProduct]);
    container.read(archivedKeys.notifier).state = {};
    await tester.pumpAndSettle();
    expect(find.text('보관한 당근 상품'), findsOneWidget);
  });
  testWidgets('hiding a purchase leaves its quantity and paid amount intact',
      (tester) async {
    final container = await showShopping(tester, 1);
    expect(find.text('당근 구매 기록'), findsNothing);
    final records = await container.read(shoppingRecordsProvider(null).future);
    expect(records.single.quantity, 750);
    expect(records.single.amount, 3000);
    container.read(archivedKeys.notifier).state = {};
    await tester.pumpAndSettle();
    expect(find.text('당근 구매 기록'), findsOneWidget);
    expect(find.textContaining('KRW 3000'), findsOneWidget);
  });
  testWidgets(
      'archived matching products are not recommended for a new purchase',
      (tester) async {
    final container = await showShopping(tester, 0);
    expect(find.textContaining('보관한 당근 상품'), findsNothing);
    container.read(archivedKeys.notifier).state = {};
    await tester.pumpAndSettle();
    expect(find.textContaining('보관한 당근 상품'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
