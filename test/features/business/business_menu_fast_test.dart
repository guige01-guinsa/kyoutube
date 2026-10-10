import 'package:k_youtube/features/business/domain/business_menu.dart';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:k_youtube/features/business/data/business_menu_fast_repository.dart';
import 'package:k_youtube/features/business/data/business_menu_repository.dart';
import 'package:k_youtube/features/business/domain/business_workspace.dart';
import 'package:k_youtube/features/business/presentation/business_pages.dart';
import 'business_flow_test.dart' show MemoryBusiness, pumpBusiness;
import 'business_menu_test.dart' show MenuMemory;
import '../workspace/workspace_reorganization_test.dart' show capturePreview;

class FastMemory implements BusinessMenuFastRepository {
  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
  bool ready = true, uncertain = false;
  int calls = 0;
  final payloads = <Map<String, dynamic>>[];
  @override
  Future<Map<String, dynamic>> preview(String workspace,
          List<Map<String, dynamic>> sources, bool stock) async =>
      {
        'fingerprint': 'snapshot',
        'sources': sources,
        'rows': [
          {
            'key': 'onion',
            'name': '양파',
            'spec': '',
            'unit': 'g',
            'required': 1000,
            'ready': ready,
            'stock': 200,
            'pack_size': 1000,
            'packs': 1,
            'open_requests': 1,
            'supplier': {
              'data': {'name': '채소 업체'}
            },
            'product': {
              'data': {'name': '양파 1kg', 'pack_unit': '봉'}
            }
          }
        ]
      };
  @override
  Future<Map<String, dynamic>> create(Map<String, dynamic> payload) async {
    calls++;
    payloads.add(Map.of(payload));
    if (uncertain && calls == 1) throw const SocketException('response lost');
    return {
      'id': 'batch',
      'requests': [
        {'id': 'created', 'supplier': '채소 업체'}
      ],
      'reservations': [
        {'id': 'reserved'}
      ]
    };
  }
}

void main() {
  setUpAll(() async {
    await (FontLoader('BusinessPreview')
          ..addFont(rootBundle.load('assets/fonts/NanumGothic-Regular.ttf')))
        .load();
    await (FontLoader('MaterialIcons')
          ..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf')))
        .load();
  });
  test(
      'candidate flags preserve legacy numeric price and distinguish pending from zero',
      () {
    final row = <String, dynamic>{
      'id': 'm',
      'revision': 1,
      'name': 'Candidate',
      'category': '',
      'description': '',
      'price': 0,
      'currency': 'KRW',
      'recipe_id': 'r',
      'recipe_revision': 1,
      'recipe_snapshot': <String, dynamic>{},
      'status': 'preparing',
      'is_candidate': true,
      'price_confirmed': false
    };
    final pending = BusinessMenuItem.fromJson(row);
    expect(pending.status, 'candidate');
    expect(pending.price, isNull);
    final free = BusinessMenuItem.fromJson({
      ...row,
      'is_candidate': false,
      'price_confirmed': true,
      'status': 'on_sale'
    });
    expect(free.price, 0);
    expect(free.status, 'on_sale');
  });
  test('menu approval is separate from finance and expires with plan', () {
    const b = BusinessContext(
        id: 'shop',
        name: '업소',
        owner: false,
        paid: true,
        approval: true,
        permissions: {'recipes.read', 'menus.approve'});
    expect(b.can('menus.approve'), true);
    expect(b.can('finance.read'), false);
    expect(b.can('finance.write'), false);
    const expired = BusinessContext(
        id: 'shop',
        name: '업소',
        owner: false,
        paid: false,
        approval: true,
        permissions: {'recipes.read', 'menus.approve'});
    expect(expired.can('menus.approve'), false);
  });
  for (final locale in ['ko', 'en']) {
    testWidgets('menu selection, explicit review and supplier drafts $locale',
        (tester) async {
      final base = MemoryBusiness(
          {'recipes.read', 'purchasing.read', 'purchasing.write'});
      final menus = MenuMemory(base), fast = FastMemory();
      final preview = GlobalKey();
      await tester.binding.setSurfaceSize(const Size(390, 844));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await pumpBusiness(tester, base,
          capture: preview,
          initial: '/business-workspaces/shop/menu-fast',
          locale: locale,
          overrides: [
            businessMenuRepositoryProvider.overrideWithValue(menus),
            businessMenuFastRepositoryProvider.overrideWithValue(fast)
          ]);
      await tester.pumpAndSettle();
      expect(find.text('중지 메뉴'), findsNothing);
      await tester.tap(find.byType(CheckboxListTile).first);
      await tester.pumpAndSettle();
      await tester.enterText(
          find.byKey(const ValueKey('fast-servings-menu')), '30');
      final calculate = find.text(
          locale == 'ko' ? '재료·구매량 계산' : 'Calculate ingredients and purchases');
      await tester.scrollUntilVisible(calculate, 250,
          scrollable: find.byType(Scrollable).first);
      await tester.tap(calculate);
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
          find.byKey(const Key('business-ingredient-summary')), 250,
          scrollable: find.byType(Scrollable).first);
      await Scrollable.ensureVisible(
          tester.element(find.byKey(const Key('business-ingredient-summary'))),
          alignment: 0);
      await tester.pumpAndSettle();
      await capturePreview(tester, preview, 'business-ingredients-$locale');
      final create = find.text(locale == 'ko'
          ? '업체별 초안 생성·재고 예약'
          : 'Create supplier drafts and reserve stock');
      await tester.scrollUntilVisible(create, 250,
          scrollable: find.byType(Scrollable).first);
      expect(
          tester
              .widget<FilledButton>(find.ancestor(
                  of: create, matching: find.byType(FilledButton)))
              .onPressed,
          isNull);
      final review = find.text(locale == 'ko'
          ? '구매처·규격·환산·중복 요청·재고 예약을 확인했습니다.'
          : 'I checked suppliers, packs, conversions, open requests and stock reservations.');
      await tester.ensureVisible(review);
      await tester.tap(review);
      await tester.pumpAndSettle();
      await tester.ensureVisible(create);
      await tester.tap(create);
      await tester.pumpAndSettle();
      expect(fast.calls, 1);
      expect(fast.payloads.single['p_confirmed'], true);
      expect(
          (fast.payloads.single['p_sources'] as List).single['servings'], 30);
      expect(find.text('채소 업체'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }
  testWidgets(
      'filtering hides no validation requirements and cannot bypass missing defaults',
      (tester) async {
    final base =
        MemoryBusiness({'recipes.read', 'purchasing.read', 'purchasing.write'});
    final fast = FastMemory()..ready = false;
    await pumpBusiness(tester, base,
        initial: '/business-workspaces/shop/menu-fast',
        overrides: [
          businessMenuRepositoryProvider.overrideWithValue(MenuMemory(base)),
          businessMenuFastRepositoryProvider.overrideWithValue(fast),
        ]);
    await tester.tap(find.byType(CheckboxListTile).first);
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(find.text('재료·구매량 계산'), 250,
        scrollable: find.byType(Scrollable).first);
    await tester.tap(find.text('재료·구매량 계산'));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
        find.byKey(const Key('business-ingredient-search')), 250,
        scrollable: find.byType(Scrollable).first);
    await tester.enterText(
        find.byKey(const Key('business-ingredient-search')), '없는 재료');
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
        find.text('구매처·규격·환산·중복 요청·재고 예약을 확인했습니다.'), 250,
        scrollable: find.byType(Scrollable).first);
    await tester.tap(find.text('구매처·규격·환산·중복 요청·재고 예약을 확인했습니다.'));
    await tester.pumpAndSettle();
    expect(
        tester
            .widget<FilledButton>(
                find.widgetWithText(FilledButton, '업체별 초안 생성·재고 예약'))
            .onPressed,
        isNull);
    expect(fast.calls, 0);
    expect(tester.takeException(), isNull);
  });
  testWidgets('transport uncertainty retries frozen id and input',
      (tester) async {
    final base = MemoryBusiness(
            {'recipes.read', 'purchasing.read', 'purchasing.write'}),
        fast = FastMemory()..uncertain = true;
    await tester.binding.setSurfaceSize(const Size(1000, 1600));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await pumpBusiness(tester, base,
        initial: '/business-workspaces/shop/menu-fast',
        overrides: [
          businessMenuRepositoryProvider.overrideWithValue(MenuMemory(base)),
          businessMenuFastRepositoryProvider.overrideWithValue(fast)
        ]);
    await tester.pumpAndSettle();
    await tester.tap(find.byType(CheckboxListTile).first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('재료·구매량 계산'));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
        find.text('구매처·규격·환산·중복 요청·재고 예약을 확인했습니다.'), 300,
        scrollable: find.byType(Scrollable).first);
    await tester.tap(find.text('구매처·규격·환산·중복 요청·재고 예약을 확인했습니다.'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('업체별 초안 생성·재고 예약'));
    await tester.tap(find.text('업체별 초안 생성·재고 예약'));
    await tester.pumpAndSettle();
    expect(
        tester
            .widget<TextField>(find.byKey(const ValueKey('fast-servings-menu')))
            .enabled,
        false);
    await tester.tap(find.text('같은 요청 재확인'));
    await tester.pumpAndSettle();
    expect(fast.calls, 2);
    expect(fast.payloads.first, fast.payloads.last);
  });
  testWidgets('researcher sees candidate registration, not purchasing action',
      (tester) async {
    final base = MemoryBusiness({'recipes.read', 'recipes.write'});
    await pumpBusiness(tester, base,
        initial: '/business-workspaces/shop/menus',
        overrides: [
          businessMenuRepositoryProvider.overrideWithValue(MenuMemory(base))
        ]);
    await tester.pumpAndSettle();
    expect(find.text('메뉴 등록'), findsOneWidget);
    expect(find.text('판매 메뉴로 빠른 구매'), findsNothing);
    await tester.tap(find.text('메뉴 등록'));
    await tester.pumpAndSettle();
    expect(find.byType(BusinessMenuEditor), findsOneWidget);
    expect(find.text('메뉴 후보'), findsWidgets);
  });
}
