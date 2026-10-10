import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:k_youtube/features/auth/application/auth_providers.dart';
import 'package:k_youtube/core/localization/app_localizations.dart';
import 'package:k_youtube/features/business/domain/business_menu.dart';
import 'package:k_youtube/features/business/domain/business_purchase_review.dart';
import 'package:k_youtube/features/business/domain/business_workspace.dart';
import 'package:k_youtube/features/business/presentation/business_pages.dart';
import 'business_flow_test.dart' show MemoryBusiness, pumpBusiness;

Future<void> pumpReview(WidgetTester tester, Widget child) =>
    tester.pumpWidget(ProviderScope(
        overrides: [activeAccountIdProvider.overrideWithValue('staff')],
        child: MaterialApp(
            locale: const Locale('ko'),
            supportedLocales: AppLocalizations.supportedLocales,
            localizationsDelegates: const [
              AppLocalizations.delegate,
              GlobalMaterialLocalizations.delegate,
              GlobalWidgetsLocalizations.delegate,
              GlobalCupertinoLocalizations.delegate
            ],
            home: Scaffold(body: SingleChildScrollView(child: child)))));

void main() {
  testWidgets(
      'shared shopping separates drafts, active work and completed records',
      (tester) async {
    final repo = MemoryBusiness(businessRolePermissions['purchasing']!);
    for (final status in [
      'draft',
      'review',
      'approved',
      'sent',
      'received',
      'cancelled'
    ]) {
      repo.data[status] = BusinessRecord(
          id: status,
          workspace: 'shop',
          kind: 'purchase',
          title: status,
          status: status,
          data: const {});
    }
    await pumpBusiness(tester, repo,
        initial: '/business-workspaces/shop?section=purchasing');
    expect(find.byKey(const ValueKey('business-purchase-status-draft')),
        findsOneWidget);
    expect(find.byKey(const ValueKey('business-purchase-status-sent')),
        findsNothing);
    await tester.tap(find.byKey(const Key('shopping-stage-active')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('business-purchase-status-draft')),
        findsNothing);
    expect(find.byKey(const ValueKey('business-purchase-status-sent')),
        findsOneWidget);
    expect(find.byKey(const Key('business-purchase-start')), findsNothing);
    await tester.tap(find.byKey(const Key('shopping-stage-records')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('business-purchase-status-received')),
        findsOneWidget);
    expect(find.byKey(const ValueKey('business-purchase-status-cancelled')),
        findsOneWidget);
    expect(repo.writes, 0);
    expect(tester.takeException(), isNull);
  });
  test(
      'standard quantities and aliases convert without mixing dimensions or packages',
      () {
    expect(businessConvertQuantity(1.25, 'kg', 'g'), 1250);
    expect(businessConvertQuantity(500, '그램', 'kg'), .5);
    expect(businessConvertQuantity(1.8, 'L', 'mL'), 1800);
    expect(businessConvertQuantity(12, 'ea', '개'), 12);
    expect(businessConvertQuantity(0, 'kg', 'g'), 0);
    for (final pair in [
      ('g', 'ml'),
      ('개', 'g'),
      ('봉', 'g'),
      ('컵', 'ml'),
      ('oz', 'g'),
      ('box', 'pack')
    ]) {
      expect(businessConvertQuantity(1, pair.$1, pair.$2), isNull);
    }
    for (final n in [double.nan, double.infinity, -1.0, 1e10, .0000001]) {
      expect(businessConvertQuantity(n, 'g', 'g'), isNull);
    }
    expect(businessConvertQuantity(1e9, 'kg', 'g'), isNull);
    final line = standardizeBusinessIngredient(const MenuIngredient(
        name: '양파', spec: '껍질 제거', quantity: 1.5, unit: 'kg'))!;
    expect(line.name, '양파');
    expect(line.spec, '껍질 제거');
    expect(line.unit, 'g');
    expect(line.quantity, 1500);
    expect(
        standardizeBusinessIngredient(
                const MenuIngredient(name: '양파', quantity: 2, unit: '망'))!
            .unit,
        '망');
  });

  test(
      'converted pack content rounds up once after stock and incoming deductions',
      () {
    final a =
        MenuPurchaseAdjustment({'key': 'onion', 'required': 2300, 'unit': 'g'})
          ..stock = businessConvertQuantity(.3, 'kg', 'g')
          ..incoming = businessConvertQuantity(.5, 'kg', 'g')
          ..packSize = businessConvertQuantity(1, 'kg', 'g')
          ..packUnit = '봉';
    expect(a.net, 1500);
    expect(a.packs, 2);
    expect(a.overage, 500);
    a.stock = 3000;
    expect(a.net, 0);
    expect(a.packs, 0);
    expect(a.overage, 0);
    a.packSize = .1;
    a.stock = 2299.7;
    a.incoming = 0;
    expect(a.packs, 3);
    expect(a.overage, 0);
  });

  test('request search includes supplier, ingredients and specifications', () {
    const r = BusinessRecord(
        id: 'p',
        workspace: 's',
        kind: 'purchase',
        title: '월요일 구매',
        data: {
          'supplier': '신선 업체',
          'delivery_date': '2026-10-01',
          'lines': [
            {'name': '양파', 'spec': '1kg 망'}
          ],
        });
    expect(businessPurchaseMatches(r, '신선 양파'), true);
    expect(businessPurchaseMatches(r, '1KG'), true);
    expect(businessPurchaseMatches(r, '당근'), false);
    expect(businessPurchaseMatches(r, ''), true);
  });

  testWidgets(
      'quantity field preserves magnitude when changing units and reports base units',
      (tester) async {
    double? value;
    await pumpReview(
        tester,
        SizedBox(
            width: 280,
            child: BusinessQuantityField(
                label: '재고',
                unit: 'g',
                value: null,
                enabled: true,
                onChanged: (v) => value = v)));
    await tester.enterText(find.byType(TextField), '500');
    expect(value, 500);
    await tester.tap(find.byType(DropdownButton<String>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('무게 · kg').last);
    await tester.pumpAndSettle();
    expect(tester.widget<TextField>(find.byType(TextField)).controller!.text,
        '0.5');
    expect(value, 500);
    await tester.enterText(find.byType(TextField), '1.25');
    await tester.pump();
    expect(value, 1250);
    expect(find.text('환산: 1250 g'), findsOneWidget);
    await tester.enterText(find.byType(TextField), '-1');
    expect(value, isNull);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'standardizing ingredients requires review and preserves specifications',
      (tester) async {
    List<MenuIngredient>? updated;
    await pumpReview(
        tester,
        BusinessIngredientEditor(
            enabled: true,
            lines: const [
              MenuIngredient(
                  name: '양파', quantity: 1.5, unit: 'kg', spec: '손질 전'),
              MenuIngredient(
                  name: '양파', quantity: 300, unit: 'g', spec: '손질 후'),
              MenuIngredient(name: '국간장', quantity: 1.8, unit: 'L'),
              MenuIngredient(name: '우유', quantity: 2, unit: '팩'),
            ],
            onChanged: (v) => updated = v));
    await tester.tap(find.byKey(const Key('business-standardize-units')));
    await tester.pumpAndSettle();
    expect(updated, isNull);
    expect(find.textContaining('1500 g'), findsOneWidget);
    expect(find.textContaining('1800 ml'), findsOneWidget);
    await tester.tap(find.widgetWithText(FilledButton, '확인'));
    await tester.pumpAndSettle();
    expect(updated!.length, 4);
    expect(updated![0].quantity, 1500);
    expect(updated![0].spec, '손질 전');
    expect(updated![1].spec, '손질 후');
    expect(updated![2].unit, 'ml');
    expect(updated![3].unit, '팩');
    expect(updated![3].quantity, 2);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'ingredient filters organize without merging or dropping source rows',
      (tester) async {
    final items = [
      {'name': '진간장', 'ready': true},
      {'name': '국간장', 'ready': false},
      {'name': '양파', 'ready': true},
    ];
    await pumpReview(
        tester,
        BusinessIngredientReview<Map<String, Object>>(
            items: items,
            name: (r) => r['name'] as String,
            needsReview: (r) => r['ready'] != true,
            builder: (r) => Text('재료: ${r['name']}')));
    expect(find.text('재료 3개 · 확인 필요 1개'), findsOneWidget);
    await tester.tap(find.text('양념·오일 2'));
    await tester.pumpAndSettle();
    expect(find.text('재료: 진간장'), findsOneWidget);
    expect(find.text('재료: 국간장'), findsOneWidget);
    expect(find.text('재료: 양파'), findsNothing);
    await tester.tap(find.byKey(const Key('business-ingredients-pending')));
    await tester.pumpAndSettle();
    expect(find.text('재료: 진간장'), findsNothing);
    expect(find.text('재료: 국간장'), findsOneWidget);
    expect(items.length, 3);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'business buyer can search ingredient and see the correct next action',
      (tester) async {
    final repo = MemoryBusiness(businessRolePermissions['purchasing']!);
    repo.data['draft'] = const BusinessRecord(
        id: 'draft',
        workspace: 'shop',
        kind: 'purchase',
        title: '오늘 구매',
        data: {
          'supplier': '우리 업체',
          'lines': [
            {'name': '국간장', 'spec': '1L'}
          ],
        });
    repo.data['sent'] = const BusinessRecord(
        id: 'sent',
        workspace: 'shop',
        kind: 'purchase',
        title: '전달한 구매',
        status: 'sent',
        data: {'lines': []});
    await pumpBusiness(tester, repo,
        initial: '/business-workspaces/shop?section=purchasing');
    await tester.enterText(
        find.byKey(const ValueKey('business-search-purchase')), '국간장');
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
        find.byKey(const ValueKey('business-purchase-draft')), 200,
        scrollable: find.byType(Scrollable).first);
    expect(find.text('이어서 작성'), findsOneWidget);
    expect(find.byKey(const ValueKey('business-purchase-sent')), findsNothing);
    expect(repo.writes, 0);
    expect(tester.takeException(), isNull);
  });

  testWidgets('read-only business access has no write entry points',
      (tester) async {
    final repo = MemoryBusiness({'purchasing.read'});
    repo.data['draft'] = const BusinessRecord(
        id: 'draft',
        workspace: 'shop',
        kind: 'purchase',
        title: '참조용',
        data: {});
    await pumpBusiness(tester, repo,
        initial: '/business-workspaces/shop?section=purchasing');
    expect(find.byKey(const Key('business-purchase-start')), findsNothing);
    expect(find.byKey(const Key('business-purchase-manual')), findsNothing);
    expect(find.text('이어서 작성'), findsNothing);
    expect(find.text('요청서 확인'), findsOneWidget);
    expect(repo.writes, 0);
  });
}
