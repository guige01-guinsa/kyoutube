import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:k_youtube/core/theme/app_theme.dart';
import 'package:k_youtube/features/auth/application/auth_providers.dart';
import 'package:k_youtube/features/kitchen/application/kitchen_providers.dart';
import 'package:k_youtube/features/kitchen/data/kitchen_api.dart';
import 'package:k_youtube/features/kitchen/domain/kitchen_models.dart';
import 'package:k_youtube/features/kitchen/presentation/kitchen_page.dart';
import 'package:k_youtube/features/recipes/application/recipe_providers.dart';

class _ShoppingApi extends KitchenApi {
  _ShoppingApi({this.needsReview = false});
  final bool needsReview;
  final requests = <KitchenShoppingItemStatus>[];
  KitchenShoppingItemStatus status = KitchenShoppingItemStatus.pending;
  int revision = 1;

  KitchenShoppingItem get item => KitchenShoppingItem(
        id: 'tomato',
        listId: 'shopping',
        name: '토마토',
        ingredientText: '토마토 2개',
        status: status,
        reviewStatus: needsReview
            ? KitchenShoppingItemReviewStatus.required
            : KitchenShoppingItemReviewStatus.confirmed,
        needsReview: needsReview,
        isChecked: status == KitchenShoppingItemStatus.purchased,
        revision: revision,
        updatedAt: DateTime(2026, 9, 9),
        quantity: 2,
        unit: 'ea',
      );

  @override
  Future<List<KitchenShoppingList>> listShoppingLists(
          {String status = 'active'}) async =>
      [
        KitchenShoppingList(
            id: 'shopping',
            status: 'active',
            title: '오늘의 장보기',
            items: [item],
            openItemCount:
                this.status == KitchenShoppingItemStatus.pending ? 1 : 0)
      ];

  @override
  Future<KitchenShoppingItem> setShoppingItemStatus(
      {required String itemId,
      required KitchenShoppingItemStatus status,
      required int expectedRevision}) async {
    expect(itemId, 'tomato');
    expect(expectedRevision, revision);
    requests.add(status);
    this.status = status;
    revision++;
    return item;
  }
}

Future<void> _pumpKitchen(WidgetTester tester, _ShoppingApi api) async {
  const user = User(
      id: 'test-user',
      appMetadata: {},
      userMetadata: {},
      aud: 'authenticated',
      createdAt: '2026-09-09');
  final router = GoRouter(
      routes: [GoRoute(path: '/', builder: (_, __) => const KitchenPage())]);
  addTearDown(router.dispose);
  await tester.pumpWidget(ProviderScope(overrides: <Override>[
    authUserProvider.overrideWith((_) => Stream.value(user)),
    kitchenApiProvider.overrideWithValue(api),
    kitchenSummaryProvider.overrideWith((_) async => {}),
    kitchenIngredientsProvider.overrideWith((_) async => []),
    kitchenCompletedShoppingListsProvider.overrideWith((_) async => []),
    kitchenCookSessionsProvider.overrideWith((_) async => []),
  ], child: MaterialApp.router(theme: AppTheme.light, routerConfig: router)));
  await tester.pumpAndSettle();
  await tester.scrollUntilVisible(find.byType(Checkbox), 240,
      scrollable: find.byType(Scrollable).first);
  await tester.pumpAndSettle();
}

void main() {
  testWidgets(
      'purchase checkbox and status menu use the existing revision-aware mutations',
      (tester) async {
    final api = _ShoppingApi();
    await _pumpKitchen(tester, api);
    await tester.tap(find.byType(Checkbox));
    await tester.pumpAndSettle();
    expect(api.requests, [KitchenShoppingItemStatus.purchased]);
    expect(tester.widget<Checkbox>(find.byType(Checkbox)).value, isTrue);
    await tester.ensureVisible(find.byTooltip('토마토 구매 상태 변경'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('토마토 구매 상태 변경'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('이번에는 건너뜀'));
    await tester.pumpAndSettle();
    expect(api.requests, [
      KitchenShoppingItemStatus.purchased,
      KitchenShoppingItemStatus.skipped
    ]);
    expect(tester.takeException(), isNull);
  });

  testWidgets('unchecked evidence opens review before marking purchased',
      (tester) async {
    final api = _ShoppingApi(needsReview: true);
    await _pumpKitchen(tester, api);
    await tester.tap(find.byType(Checkbox));
    await tester.pumpAndSettle();
    expect(find.text('재료 검토 후 구매함'), findsOneWidget);
    expect(api.requests, isEmpty);
    await tester.tap(find.text('취소'));
    await tester.pumpAndSettle();
    expect(api.requests, isEmpty);
  });
}
