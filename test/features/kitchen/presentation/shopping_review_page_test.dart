import 'package:k_youtube/features/guide/presentation/guide_help_button.dart';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:k_youtube/features/kitchen/application/kitchen_providers.dart';
import 'package:k_youtube/features/kitchen/application/shopping_persistence_controllers.dart';
import 'package:k_youtube/features/kitchen/data/kitchen_api.dart';
import 'package:k_youtube/features/kitchen/data/shopping_persistence.dart';
import 'package:k_youtube/features/kitchen/domain/shopping_review_drafts.dart';
import 'package:k_youtube/features/kitchen/presentation/shopping_review_page.dart';
import 'package:k_youtube/features/kitchen/presentation/shopping_purchase_quantity_dialog.dart';
import 'package:k_youtube/features/recipes/application/recipe_providers.dart';
import 'package:k_youtube/features/recipes/domain/recipe.dart';

class _MemoryStore implements KitchenKeyValueStore {
  final values = <String, String>{};
  @override
  Future<String?> read(String key) async => values[key];
  @override
  Future<void> write(String key, String value) async {
    values[key] = value;
  }

  @override
  Future<void> remove(String key) async {
    values.remove(key);
  }
}

void main() {
  testWidgets('purchase package conversion leaves cooking source untouched',
      (tester) async {
    tester.view.physicalSize = const Size(430, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    ShoppingReviewDraftItem? saved;
    const source = ShoppingReviewDraftItem(
        localId: 'tofu',
        ingredientText: '두부 100g',
        name: '두부',
        quantityInput: '2',
        quantity: 2,
        unit: 'pack',
        purchaseConfirmed: true);
    await tester.pumpWidget(MaterialApp(
        home: Builder(
            builder: (context) => Scaffold(
                body: TextButton(
                    onPressed: () async {
                      saved = await showShoppingPurchaseQuantityDialog(
                          context, source);
                    },
                    child: const Text('Open purchase editor'))))));
    await tester.tap(find.text('Open purchase editor'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(ChoiceChip, '무게'));
    await tester.pumpAndSettle();
    final quantity = find.byKey(const ValueKey('purchase-quantity'));
    expect(tester.widget<TextField>(quantity).controller!.text, isEmpty);
    await tester.enterText(
        find.byKey(const ValueKey('purchase-conversion-factor')), '300');
    await tester.pump();
    expect(
        double.parse(tester.widget<TextField>(quantity).controller!.text), 600);
    await tester.tap(find.byType(DropdownButtonFormField<String>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('kg').last);
    await tester.pumpAndSettle();
    expect(
        double.parse(tester.widget<TextField>(quantity).controller!.text), 0.6);
    await tester.tap(find.widgetWithText(FilledButton, '저장'));
    await tester.pumpAndSettle();
    expect(saved!.ingredientText, '두부 100g');
    expect(saved!.quantity, 0.6);
    expect(saved!.unit, 'kg');
    expect(saved!.purchaseConfirmed, isTrue);
  });
  for (final excludeRiceAndEgg in [false, true]) {
    testWidgets(
        'edited recipe to shopping, excluded=$excludeRiceAndEgg, retry keeps request key',
        (tester) async {
      tester.view.physicalSize = const Size(430, 1400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final memory = _MemoryStore();
      final store = ShoppingReviewDraftStore(storage: memory);
      await store.getOrCreateDraft(
          userId: 'chef',
          sourceRecipeId: 'creator:bibimbap',
          initialItems: [
            for (final entry in ['[확인 필요] 밥', '[확인 필요] 달걀 (기호에 따라 올림)'].indexed)
              ShoppingReviewDraftItem(
                  localId: '${entry.$1}',
                  ingredientText: entry.$2,
                  name: entry.$2,
                  quantityInput: '',
                  quantity: null,
                  unit: null,
                  needsReview: true),
          ]);
      final requests = <http.Request>[];
      final api = KitchenApi(
          accessTokenProvider: () async => 'test-token',
          httpClient: MockClient((request) async {
            if (request.method == 'GET') {
              return http.Response(
                  jsonEncode({
                    'status': 'ok',
                    'data': [
                      {
                        'id': 'past-stock',
                        'name': '밥',
                        'quantity': 999,
                        'unit': 'g'
                      },
                    ]
                  }),
                  200);
            }
            requests.add(request);
            if (requests.length == 1) {
              return http.Response(
                  jsonEncode({
                    'status': 'error',
                    'message': 'Shopping request was rejected',
                    'details': {'code': 'shopping_request_rejected'},
                  }),
                  422);
            }
            return http.Response(
                jsonEncode({
                  'status': 'ok',
                  'data': {
                    'list_id': 'shopping-list',
                    'status': 'active',
                    'created': true,
                    'replayed': false,
                    'idempotency_key': request.headers['Idempotency-Key'],
                  }
                }),
                201);
          }));
      final router = GoRouter(routes: [
        GoRoute(
            path: '/',
            builder: (_, __) => const ShoppingReviewPage(
                sourceRecipeReference: 'creator:bibimbap')),
        GoRoute(
            path: '/shopping',
            builder: (_, state) => Scaffold(
                body: Text(
                    'Created shopping list ${state.uri.queryParameters['list']}'))),
      ]);
      addTearDown(router.dispose);
      await tester.pumpWidget(ProviderScope(overrides: [
        creatorRecipeByIdProvider.overrideWith((_, __) async => Recipe(
                id: 'bibimbap',
                title: '간단한 비빔밥',
                ingredients: [
                  '밥 120g',
                  '달걀 1개',
                  '당근 ½ 개 (채 썸)',
                  '진간장 1/2 작은술',
                  '참기름 1 큰술'
                ],
                steps: [])),
        kitchenApiProvider.overrideWithValue(api),
        shoppingReviewDraftControllerProvider.overrideWith((_) async =>
            ShoppingReviewDraftController(
                store: store, currentUserId: () async => 'chef')),
      ], child: MaterialApp.router(routerConfig: router)));
      await tester.pumpAndSettle();
      expect(find.text('[확인 필요] 밥'), findsNothing);
      expect(find.text('밥 120g'), findsOneWidget);
      expect(find.byType(GuideHelpButton), findsOneWidget);
      expect(find.text('당근 ½ 개 (채 썸)'), findsOneWidget);
      expect(find.text('구매 수량·단위 미입력 · 나중에 입력 가능'), findsNWidgets(5));
      // Buying ten eggs must not rewrite the recipe's one-egg cooking amount.
      await tester.tap(find.byTooltip('구매 수량·단위').at(1));
      await tester.pumpAndSettle();
      await tester.enterText(
          find.byKey(const ValueKey('purchase-quantity')), '10');
      await tester.tap(find.widgetWithText(ChoiceChip, '개수'));
      await tester.pumpAndSettle();
      await tester.tap(find.byType(DropdownButtonFormField<String>));
      await tester.pumpAndSettle();
      await tester.tap(find.text('개').last);
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, '저장'));
      await tester.pumpAndSettle();
      expect(find.text('달걀 1개'), findsOneWidget);
      expect(find.text('구매 10 개'), findsOneWidget);
      if (excludeRiceAndEgg) {
        await tester.tap(find.text('밥 120g'));
        await tester.pump();
        await tester.tap(find.text('달걀 1개'));
        await tester.pump();
      }
      await tester.tap(find.byType(FilledButton));
      await tester.pumpAndSettle();
      expect(requests, hasLength(1));
      expect(find.textContaining('서버가 장보기 요청을 처리하지 못했습니다.'), findsOneWidget);
      expect(memory.values, isNotEmpty);
      await tester.tap(find.byType(FilledButton));
      await tester.pumpAndSettle();
      expect(find.text('Created shopping list shopping-list'), findsOneWidget);
      expect(memory.values, isEmpty);
      expect(requests[1].headers['Idempotency-Key'],
          requests[0].headers['Idempotency-Key']);
      expect(requests[1].body, requests[0].body);
      final items = jsonDecode(requests[1].body)['items'] as List<dynamic>;
      expect(
          items.map((dynamic item) => item['name']),
          excludeRiceAndEgg
              ? ['당근', '진간장', '참기름']
              : ['밥', '달걀', '당근', '진간장', '참기름']);
      expect(
          items.map((dynamic item) => item['unit']),
          excludeRiceAndEgg
              ? [null, null, null]
              : [null, 'ea', null, null, null]);
      expect(
          items.map((dynamic item) => item['quantity']),
          excludeRiceAndEgg
              ? [null, null, null]
              : [null, 10, null, null, null]);
      expect(tester.takeException(), isNull);
    });
  }
}
