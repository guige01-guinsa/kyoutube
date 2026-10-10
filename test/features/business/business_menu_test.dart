import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:k_youtube/features/business/data/business_menu_repository.dart';
import 'package:k_youtube/features/business/domain/business_menu.dart';
import 'package:k_youtube/features/business/domain/business_workspace.dart';
import 'package:k_youtube/features/business/presentation/business_pages.dart';
import 'package:k_youtube/features/auth/application/auth_providers.dart';
import 'business_flow_test.dart' show MemoryBusiness, pumpBusiness;

class MenuMemory implements BusinessMenuRepository {
  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
  @override
  Future<Map<String, dynamic>> revisions(String workspace) async => {};
  final MemoryBusiness base;
  MenuMemory(this.base);
  final items = <BusinessMenuItem>[
    const BusinessMenuItem(
        id: 'menu',
        revision: 2,
        name: '판매 메뉴',
        category: '식사',
        description: '양파를 사용한 메뉴',
        price: 9000,
        currency: 'KRW',
        recipeId: 'recipe',
        recipeRevision: 1,
        snapshot: {'title': '양파 조리법', 'data': <String, dynamic>{}},
        status: 'on_sale'),
    const BusinessMenuItem(
        id: 'stopped',
        revision: 1,
        name: '중지 메뉴',
        category: '식사',
        description: '',
        price: 1000,
        currency: 'KRW',
        recipeId: 'recipe',
        recipeRevision: 1,
        snapshot: {'title': '조리법', 'data': <String, dynamic>{}},
        status: 'stopped')
  ];
  List<Map<String, dynamic>> events = [];
  int writes = 0;
  String? purpose;
  List<MenuPurchaseSource>? selected;
  List<Map<String, dynamic>>? adjustments;
  Completer<Map<String, dynamic>>? delayedPlan;
  @override
  Future<List<BusinessMenuItem>> menus(String workspace) async => items;
  @override
  Future<List<Map<String, dynamic>>> reviews(
          String workspace, String recipe) async =>
      events;
  @override
  Future<Map<String, dynamic>?> basis(String workspace, String request) async =>
      null;
  @override
  Future<Map<String, dynamic>> review(
      BusinessRecord recipe, int expected, String stage, String note) async {
    writes++;
    final row = {
      'id': 2,
      'recipe_revision': recipe.revision,
      'stage': stage,
      'note': note
    };
    events = [row, ...events];
    return row;
  }

  @override
  Future<Map<String, dynamic>> plan(String workspace, String purpose,
      List<MenuPurchaseSource> sources) async {
    this.purpose = purpose;
    selected = [...sources];
    if (delayedPlan != null) return delayedPlan!.future;
    return {
      'requirements': [
        {
          'key': 'onion',
          'name': '양파',
          'spec': '손질',
          'unit': 'kg',
          'required': 4.5
        }
      ]
    };
  }

  @override
  Future<BusinessRecord> purchase(
      String workspace,
      String request,
      String purpose,
      List<MenuPurchaseSource> sources,
      List<MenuPurchaseAdjustment> adjustments,
      String supplier) async {
    writes++;
    this.adjustments = adjustments.map((a) => a.toJson()).toList();
    final r = BusinessRecord(
        id: request,
        workspace: workspace,
        kind: 'purchase',
        title: '메뉴 구매',
        revision: 1,
        data: {
          'supplier': supplier,
          'buyer': '업소',
          'currency': 'KRW',
          'notes': '',
          'lines': [
            {
              'id': 'line',
              'name': '양파',
              'spec': '2kg',
              'quantity': 2,
              'unit': '봉',
              'price': null
            }
          ]
        });
    base.data[r.id] = r;
    return r;
  }
}

void main() {
  test(
      'pack calculation avoids binary floating over-purchase and keeps unknown stock unknown',
      () {
    final a = MenuPurchaseAdjustment({'key': 'x', 'required': 0.07});
    expect(a.valid, false);
    expect(a.packs, null);
    expect(a.confirmed, false);
    a
      ..stock = 0
      ..incoming = 0
      ..packSize = 0.01
      ..packUnit = 'pack';
    expect(a.packs, 7);
    expect(a.overage, 0);
    a.requirement['required'] = 4.5;
    a
      ..stock = 1
      ..packSize = 2;
    expect(a.net, 3.5);
    expect(a.packs, 2);
    expect(a.overage, 0.5);
    a.stock = 6;
    expect(a.packs, 0);
    a.stock = double.nan;
    expect(a.valid, false);
    expect(menuQuantityValid(0.0000001), false);
    expect(menuNumber(0.000001), '0.000001');
  });
  test(
      'source serialization carries exact source version and no mutable display title',
      () {
    const source = MenuPurchaseSource(
        kind: 'menu', id: 'm', revision: 4, title: 'Display', servings: 30);
    expect(source.toJson(),
        {'kind': 'menu', 'id': 'm', 'revision': 4, 'servings': 30.0});
    expect(
        changedRecipeFields(
            {'title': 'A', 'servings': 1}, {'title': 'A', 'servings': 2}),
        ['servings']);
  });
  for (final locale in ['ko', 'en']) {
    testWidgets('menu permission, preview and small screen $locale',
        (tester) async {
      final base = MemoryBusiness(
              {'recipes.read', 'purchasing.read', 'purchasing.write'}),
          menu = MenuMemory(MemoryBusiness({}));
      await pumpBusiness(tester, base,
          locale: locale,
          initial: '/business-workspaces/shop/menus',
          width: 390,
          textScale: 2,
          overrides: [businessMenuRepositoryProvider.overrideWithValue(menu)]);
      await tester.pumpAndSettle();
      expect(
          find.text(locale == 'ko' ? '메뉴 등록' : 'Add menu item'), findsNothing);
      await tester.scrollUntilVisible(find.text('판매 메뉴'), 200,
          scrollable: find.byType(Scrollable).first);
      expect(find.text('판매 메뉴'), findsOneWidget);
      expect(find.text('중지 메뉴'), findsOneWidget);
      final preview =
          find.text(locale == 'ko' ? '판매 메뉴판 미리보기' : 'Preview selling menu');
      await tester.scrollUntilVisible(preview.hitTestable(), -200,
          scrollable: find.byType(Scrollable).first);
      await tester.tap(preview);
      await tester.pumpAndSettle();
      expect(find.text('중지 메뉴'), findsNothing);
      expect(find.text('판매 메뉴'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }
  testWidgets(
      'purchase requires source, quantities, stock confirmation and supplier before draft creation',
      (tester) async {
    final base =
        MemoryBusiness({'recipes.read', 'purchasing.read', 'purchasing.write'});
    final menu = MenuMemory(base);
    await pumpBusiness(tester, base,
        initial: '/business-workspaces/shop/menu-purchase',
        overrides: [businessMenuRepositoryProvider.overrideWithValue(menu)]);
    await tester.pumpAndSettle();
    await tester.tap(find.text('메뉴·레시피와 인분 추가'));
    await tester.pumpAndSettle();
    expect(find.text('중지 메뉴'), findsNothing);
    await tester.tap(find.text('판매 메뉴'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).last, '30');
    await tester.tap(find.widgetWithText(FilledButton, '추가'));
    await tester.pumpAndSettle();
    await tester.pump(const Duration(seconds: 1));
    await tester.tap(find.text('재료 필요량 계산'));
    await tester.pumpAndSettle();
    expect(menu.purpose, 'operations');
    expect(menu.selected!.single.revision, 2);
    expect(menu.selected!.single.servings, 30);
    expect(menu.writes, 0);
    Future<void> fill(String label, String value) async {
      final f = find.widgetWithText(TextField, label);
      if (f.evaluate().isEmpty) {
        await tester.scrollUntilVisible(f, 200,
            scrollable: find.byType(Scrollable).first);
      }
      await tester.ensureVisible(f);
      await tester.enterText(f, value);
      await tester.pump();
    }

    await fill('사용 가능 재고 (kg)', '1');
    // Enter stock in grams while preserving the server's kilogram basis.
    final stockUnit = find.descendant(
        of: find.byKey(const ValueKey('stock--')),
        matching: find.byType(DropdownButton<String>));
    await tester.ensureVisible(stockUnit);
    await tester.tap(stockUnit);
    await tester.pumpAndSettle();
    await tester.tap(find.text('무게 · g').last);
    await tester.pumpAndSettle();
    await fill('사용 가능 재고 (g)', '1000');
    expect(find.text('환산: 1 kg'), findsOneWidget);
    await fill('입고 예정 (kg)', '0');
    await fill('포장 1개당 양 (kg)', '2');
    await fill('구매 단위 (봉·박스 등)', '봉');
    expect(find.textContaining('→ 2 봉'), findsOneWidget);
    final confirm = find.text('재고·입고 예정·포장 규격을 확인했습니다.');
    await tester.ensureVisible(confirm);
    await tester.tap(confirm);
    await tester.pump();
    final supplier = find.widgetWithText(TextField, '공급업체');
    if (supplier.evaluate().isEmpty) {
      await tester.scrollUntilVisible(supplier, -200,
          scrollable: find.byType(Scrollable).first);
    }
    await tester.ensureVisible(supplier);
    await tester.enterText(supplier, '한결 식자재');
    await tester.pump();
    final create = find.text('확인한 수량으로 구매 초안 만들기');
    if (create.evaluate().isEmpty) {
      await tester.scrollUntilVisible(create, 200,
          scrollable: find.byType(Scrollable).first);
    }
    await tester.ensureVisible(create);
    await tester.tap(create);
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, '확인'));
    await tester.pumpAndSettle();
    expect(menu.writes, 1);
    expect(menu.adjustments!.single['stock'], 1);
    expect(menu.adjustments!.single['confirmed'], true);
    expect(menu.adjustments!.single['include'], true);
    expect(base.data.values.single.status, 'draft');
    expect(find.text('저장하지 않고 나갈까요?'), findsNothing);
    expect(tester.takeException(), isNull);
  });
  testWidgets(
      'recipe approval action visible to management and hidden from purchaser',
      (tester) async {
    final base = MemoryBusiness({'recipes.read', 'menus.approve'});
    final menu = MenuMemory(base)
      ..events = [
        {'id': 1, 'recipe_revision': 1, 'stage': 'testing', 'note': '간 확인'}
      ];
    base.data['r'] = const BusinessRecord(
        id: 'r',
        workspace: 'shop',
        kind: 'recipe',
        title: '개발 레시피',
        revision: 1,
        data: {
          'servings': 4,
          'ingredients': '양파 600g',
          'ingredient_lines': [
            {'name': '양파', 'spec': '', 'quantity': 600, 'unit': 'g'}
          ],
          'steps': '조리',
          'notes': ''
        });
    await pumpBusiness(tester, base,
        initial: '/business-workspaces/shop/records/r',
        overrides: [businessMenuRepositoryProvider.overrideWithValue(menu)]);
    await tester.pumpAndSettle();
    expect(find.text('이 버전 출시 승인'), findsOneWidget);
    await tester.tap(find.text('이 버전 출시 승인'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).last, '맛·배합 검토 완료');
    await tester.tap(find.widgetWithText(FilledButton, '기록'));
    await tester.pumpAndSettle();
    await tester.pump(const Duration(seconds: 1));
    expect(menu.writes, 1);
    expect(menu.events.first['stage'], 'approved');
  });
  testWidgets('signed-out account cannot see or continue purchase editor',
      (tester) async {
    final account = StateProvider<String?>((ref) => 'staff');
    final base =
        MemoryBusiness({'recipes.read', 'purchasing.read', 'purchasing.write'});
    final menu = MenuMemory(base);
    await pumpBusiness(tester, base,
        initial: '/business-workspaces/shop/menu-purchase',
        overrides: [
          activeAccountIdProvider.overrideWith((ref) => ref.watch(account)),
          businessMenuRepositoryProvider.overrideWithValue(menu)
        ]);
    await tester.pumpAndSettle();
    final container = ProviderScope.containerOf(
        tester.element(find.byType(BusinessMenuPurchaseEditor)));
    container.read(account.notifier).state = null;
    await tester.pumpAndSettle();
    expect(find.text('메뉴·레시피와 인분 추가'), findsNothing);
    expect(menu.writes, 0);
  });
}
