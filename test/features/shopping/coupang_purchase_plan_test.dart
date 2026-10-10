import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:k_youtube/features/auth/application/auth_providers.dart';
import 'package:k_youtube/features/shopping/data/shopping_affiliate_repository.dart';
import 'package:k_youtube/features/shopping/data/shopping_assistant_repository.dart';
import 'package:k_youtube/features/shopping/domain/shopping_affiliate.dart';
import 'package:k_youtube/features/shopping/domain/coupang_purchase_plan.dart';
import 'package:k_youtube/features/shopping/domain/shopping_preparation.dart';
import 'package:k_youtube/features/shopping/presentation/coupang_purchase_planner.dart';
import 'package:k_youtube/features/shopping/presentation/shopping_assistant_dialogs.dart';
import 'shopping_preparation_widget_test.dart'
    show pump, tapText, MemoryPreparationStore;

ShoppingAffiliate offer(
        {double amount = 900,
        String unit = 'g',
        int inner = 1,
        bool legacy = false,
        int revision = 1,
        String id = '11111111-1111-4111-8111-111111111111',
        String title = '소면 상품'}) =>
    ShoppingAffiliate({
      'id': id,
      'program': 'coupang',
      'title': title,
      'specification': '판매 옵션 확인',
      'link': 'https://link.coupang.com/a/RealIssuedLink',
      'revision': revision,
      if (!legacy)
        'purchase_pack': {
          'amount': amount,
          'unit': unit,
          'units_per_order': inner,
          'label': '묶음',
          'option': '선택 옵션'
        },
    });

class PlannerOffers implements ShoppingAffiliateRepository {
  List<ShoppingAffiliate> rows = [offer()];
  @override
  Future<List<ShoppingAffiliate>> find(String ingredient) async => rows;
  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

void main() {
  testWidgets(
      'personal list plans before confirmation and records computed amount',
      (tester) async {
    final store = MemoryPreparationStore(), catalog = PlannerOffers();
    await pump(tester, store, name: '소면', catalog: catalog, width: 500);
    expect(find.text('구매처 찾기'), findsNothing);
    await tapText(tester, '이 상품으로 구매량 적용');
    final saved = (store.data!['edits'] as Map).values.single as Map;
    expect(saved['quantity'], 1500);
    expect(saved['coupang']['count'], 2);
    expect(store.data!['confirmed'], false);
    await tapText(tester, '구매 리스트 확정');
    expect(store.data!['confirmed'], true);
    await tapText(tester, '수량 확인 · 구매 기록');
    final dialog = tester
        .widget<ShoppingPurchaseDialog>(find.byType(ShoppingPurchaseDialog));
    expect(dialog.suggestedQuantity, 1800);
    expect(dialog.group.neededQuantity, 1500);
    expect(dialog.purchaseLabel, '소면 상품');
  });
  test('900g packs cover 1.2kg with two packs, original need unchanged', () {
    final p = CoupangPack.parse(offer().data['purchase_pack'])!;
    expect(p.suggest(1.2, 'kg'), 2);
    final plan =
        CoupangPurchasePlan(offer: offer(), count: 2, needed: 1.2, unit: 'kg');
    expect(plan.total, 1.8);
    expect(plan.difference, .6);
    expect(plan.needed, 1.2);
  });
  test('multipack is multiplied exactly once and counts convert explicitly',
      () {
    final p = CoupangPack.parse(
        offer(amount: .5, unit: 'kg', inner: 2).data['purchase_pack'])!;
    expect(p.quantityIn('g'), 1000);
    expect(p.suggest(1200, 'g'), 2);
    final eggs = CoupangPack.parse(
        offer(amount: 10, unit: 'ea', inner: 3).data['purchase_pack'])!;
    expect(eggs.suggest(31, '개'), 2);
    expect(eggs.quantityIn('g'), isNull);
    expect(p.quantityIn('ml'), isNull);
    expect(p.quantityIn('봉'), isNull);
  });
  test('exact decimal boundary does not add a pack and invalid inputs fail',
      () {
    const p = CoupangPack(.1, 'kg', 3, '묶음', '300g');
    expect(p.suggest(600, 'g'), 2);
    expect(p.suggest(double.nan, 'g'), isNull);
    expect(p.suggest(0, 'g'), isNull);
    for (final amount in [0, -1, 0.0000001, double.infinity]) {
      expect(
          CoupangPack.parse(
              offer(amount: amount.toDouble()).data['purchase_pack']),
          isNull);
    }
    expect(
        CoupangPack.parse({
          'amount': 1,
          'unit': 'g',
          'units_per_order': 1.5,
          'label': '묶음',
          'option': '옵션'
        }),
        isNull);
  });
  test('saved preparation retains both demand and sale count; old data loads',
      () {
    final plan =
        CoupangPurchasePlan(offer: offer(), count: 2, needed: 1200, unit: 'g');
    final value = PreparedPurchase(
        category: ShoppingCategory.staple,
        stock: 100,
        quantity: 1200,
        coupang: plan);
    final restored = PreparedPurchase.fromJson(value.toJson());
    expect(restored.quantity, 1200);
    expect(restored.purchaseQuantity, 1800);
    expect(restored.stock, 100);
    expect(
        PreparedPurchase.fromJson({...value.toJson()}..remove('coupang'))
            .purchaseQuantity,
        1200);
    expect(CoupangPurchasePlan.parse({...plan.toJson(), 'count': double.nan}),
        isNull);
    expect(plan.matches(offer(revision: 2)), false);
  });
  for (final config in [(390.0, 1.3, 'ko'), (1280.0, 2.0, 'en')]) {
    testWidgets('inline planning selection/counts/clear fit ${config.$1}',
        (tester) async {
      final repo = PlannerOffers();
      CoupangPurchasePlan? value;
      final opened = <Uri>[];
      tester.view.physicalSize = Size(config.$1, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(ProviderScope(
          overrides: [
            activeAccountIdProvider.overrideWithValue('user'),
            shoppingAffiliateRepositoryProvider.overrideWithValue(repo),
            shoppingLinkLauncherProvider.overrideWithValue((u) async {
              opened.add(u);
              return true;
            }),
          ],
          child: MaterialApp(
              locale: Locale(config.$3),
              supportedLocales: const [Locale('ko'), Locale('en')],
              localizationsDelegates: const [
                GlobalMaterialLocalizations.delegate,
                GlobalWidgetsLocalizations.delegate,
                GlobalCupertinoLocalizations.delegate
              ],
              builder: (_, child) => MediaQuery(
                  data:
                      MediaQueryData(textScaler: TextScaler.linear(config.$2)),
                  child: child!),
              home: Scaffold(
                  body: SingleChildScrollView(
                      child: StatefulBuilder(
                          builder: (context, set) => CoupangPurchasePlanner(
                              ingredient: '소면',
                              unit: 'g',
                              needed: 1200,
                              value: value,
                              onChanged: (p) => set(() => value = p))))))));
      await tester.pumpAndSettle();
      Future<void> tap(String ko, String en) async {
        final f = find.text(config.$3 == 'ko' ? ko : en);
        await tester.ensureVisible(f);
        await tester.tap(f);
        await tester.pumpAndSettle();
      }

      await tap('이 상품으로 구매량 적용', 'Use this product quantity');
      expect(value!.count, 2);
      expect(value!.total, 1800);
      final plus =
          find.byTooltip(config.$3 == 'ko' ? '구매 수량 늘리기' : 'Increase quantity');
      await tester.ensureVisible(plus);
      await tester.tap(plus);
      await tester.pumpAndSettle();
      expect(value!.count, 3);
      expect(value!.needed, 1200);
      await tap('구매', 'Buy');
      expect(opened.single.toString(), offer().uri.toString());
      await tap('기존 구매량으로 돌아가기', 'Use the original quantity');
      expect(value, isNull);
      expect(tester.takeException(), isNull);
    });
  }
  testWidgets(
      'business planning never exposes purchase action; unknown packs cannot apply',
      (tester) async {
    final repo = PlannerOffers()..rows = [offer(legacy: true)];
    await tester.pumpWidget(ProviderScope(
        overrides: [
          activeAccountIdProvider.overrideWithValue('user'),
          shoppingAffiliateRepositoryProvider.overrideWithValue(repo)
        ],
        child: MaterialApp(
            home: Scaffold(
                body: CoupangPurchasePlanner(
                    ingredient: '소면',
                    unit: 'g',
                    needed: 1200,
                    value: null,
                    allowOpen: false,
                    onChanged: (_) => fail('Legacy pack applied'))))));
    await tester.pumpAndSettle();
    expect(find.text('Buy'), findsNothing);
    expect(
        tester
            .widget<OutlinedButton>(find.widgetWithText(
                OutlinedButton, 'Use this product quantity'))
            .onPressed,
        isNull);
  });
  testWidgets(
      'requires an explicit selection when several affiliate products match',
      (tester) async {
    final repo = PlannerOffers()
      ..rows = [
        offer(title: '소면 900g'),
        offer(
            id: '22222222-2222-4222-8222-222222222222',
            amount: 500,
            title: '소면 500g'),
      ];
    CoupangPurchasePlan? value;
    await tester.pumpWidget(ProviderScope(
        overrides: [
          activeAccountIdProvider.overrideWithValue('user'),
          shoppingAffiliateRepositoryProvider.overrideWithValue(repo),
        ],
        child: MaterialApp(
            home: Scaffold(
                body: CoupangPurchasePlanner(
                    ingredient: '소면',
                    unit: 'g',
                    needed: 1200,
                    value: value,
                    onChanged: (plan) => value = plan)))));
    await tester.pumpAndSettle();
    expect(find.text('Choose from 2 products'), findsOneWidget);
    expect(find.text('Use this product quantity'), findsNothing);
    await tester.tap(find.text('Choose from 2 products'));
    await tester.pumpAndSettle();
    await tester.tap(find.textContaining('소면 500g'));
    await tester.pumpAndSettle();
    expect(find.text('Use this product quantity'), findsOneWidget);
  });
  testWidgets(
      'changed product disables purchase and count changes until selection renewed',
      (tester) async {
    final repo = PlannerOffers()..rows = [offer(revision: 2)];
    final value =
        CoupangPurchasePlan(offer: offer(), count: 2, needed: 1200, unit: 'g');
    await tester.pumpWidget(ProviderScope(
        overrides: [
          activeAccountIdProvider.overrideWithValue('user'),
          shoppingAffiliateRepositoryProvider.overrideWithValue(repo)
        ],
        child: MaterialApp(
            home: Scaffold(
                body: SingleChildScrollView(
                    child: CoupangPurchasePlanner(
                        ingredient: '소면',
                        unit: 'g',
                        needed: 1200,
                        value: value,
                        onChanged: (_) => fail('Changed count')))))));
    await tester.pumpAndSettle();
    expect(
        tester
            .widget<OutlinedButton>(find.widgetWithText(OutlinedButton, 'Buy'))
            .onPressed,
        isNull);
    expect(
        tester
            .widget<IconButton>(find.byWidgetPredicate(
                (w) => w is IconButton && w.tooltip == 'Increase quantity'))
            .onPressed,
        isNull);
  });
}
