import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:k_youtube/features/auth/application/auth_providers.dart';
import 'package:k_youtube/features/business/data/business_inventory_repository.dart';
import 'package:k_youtube/features/business/data/business_repository.dart';
import 'package:k_youtube/features/business/domain/business_inventory.dart';
import 'package:k_youtube/features/business/domain/business_navigation.dart';
import 'package:k_youtube/features/business/domain/business_workspace.dart';
import 'package:k_youtube/features/business/presentation/business_pages.dart';
import 'package:k_youtube/features/business/data/business_menu_repository.dart';
import 'business_menu_test.dart' show MenuMemory;
import 'business_flow_test.dart' show MemoryBusiness, pumpBusiness;
import 'business_supplier_test.dart' show click, reveal;

const onionStock = BusinessStockItem(
    id: 'onion',
    name: '양파',
    spec: '손질',
    unit: 'g',
    onHand: 2400,
    reserved: 400,
    available: 2000);

class InventoryMemory implements BusinessInventoryRepository {
  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
  final calls = <({String id, String action, Map<String, dynamic> data})>[];
  Object? failure;
  bool legacy = false, mapped = false, empty = false;
  String status = 'sent';
  @override
  Future<List<BusinessStockItem>> items(String workspace) async =>
      empty ? [] : [onionStock];
  @override
  Future<BusinessReceiving> receiving(String workspace, String request) async =>
      BusinessReceiving(
          request: request,
          title: '양파 구매요청',
          revision: 3,
          status: status,
          legacy: legacy,
          lines: [
            {
              'id': 'line',
              'name': '양파 500g',
              'spec': '손질',
              'unit': '봉',
              'quantity': 6,
              'received': 2,
              'returned': 0,
              'net': 2,
              'outstanding': 4,
              if (mapped) 'mapped_item': onionStock.id,
              if (mapped) 'mapped_factor': 500,
            }
          ]);
  @override
  Future<List<Map<String, dynamic>>> reservations(
          String workspace, String item) async =>
      [
        {
          'id': 'reservation',
          'revision': 2,
          'purpose': '오늘 점심 10인분',
          'quantity': 600,
          'remaining': 400,
          'created_at': '2026-09-21T01:00:00Z'
        }
      ];
  @override
  Future<List<Map<String, dynamic>>> events(StockEventQuery q) async =>
      q.offset > 0
          ? []
          : [
              {
                'id': 'receipt',
                'kind': 'receive',
                'reason': '실제 수량 검수',
                'delta': 1000,
                'reserved_delta': 0,
                'returnable': 2,
                'item_unit': 'g',
                'purchase_quantity': 2,
                'factor': 500,
                'created_at': '2026-09-21T01:00:00Z',
                'snapshot': {
                  'line': {'name': '양파 500g', 'unit': '봉'},
                  'item_unit': 'g'
                },
              }
            ];
  @override
  Future<Map<String, dynamic>> action(String workspace, String id,
      String action, Map<String, dynamic> data) async {
    calls.add((id: id, action: action, data: Map.of(data)));
    if (failure != null) throw failure!;
    return {'id': id, ...data};
  }

  @override
  Future<List<Map<String, dynamic>>> hints(
          String workspace, List<Map<String, dynamic>> requirements) async =>
      [
        {
          'key': requirements.first['key'],
          'item': {
            'id': 'onion',
            'name': '양파',
            'spec': '손질',
            'unit': requirements.first['unit'],
            'on_hand': requirements.first['unit'] == 'kg' ? 2.4 : 2400,
            'reserved': requirements.first['unit'] == 'kg' ? 0.4 : 400,
            'available': requirements.first['unit'] == 'kg' ? 2 : 2000
          },
          'open_requests': [
            {'id': 'request', 'title': '어제 구매요청', 'status': 'approved'}
          ],
        }
      ];
}

Finder field(String label) => find.byWidgetPredicate(
    (w) => w is TextField && (w.decoration?.labelText ?? '').startsWith(label));
Future<void> fill(WidgetTester tester, String label, String value) async {
  final f = field(label);
  await tester.ensureVisible(f);
  await tester.enterText(f, value);
  await tester.pump();
}

Future<void> pumpInventory(WidgetTester tester, InventoryMemory stock,
    {Set<String>? permissions,
    String path = '/business-workspaces/shop/inventory/onion',
    String locale = 'ko',
    double scale = 1}) async {
  await pumpBusiness(tester,
      MemoryBusiness(permissions ?? businessRolePermissions['purchasing']!),
      initial: path,
      locale: locale,
      width: 390,
      textScale: scale,
      overrides: [
        businessInventoryRepositoryProvider.overrideWithValue(stock)
      ]);
}

void main() {
  test(
      'inventory quantity validation preserves decimal and signed adjustment constraints',
      () {
    expect(stockQuantityValid(0), false);
    expect(stockQuantityValid(double.nan), false);
    expect(stockQuantityValid(double.infinity), false);
    expect(stockQuantityValid(-2), false);
    expect(stockQuantityValid(-2, signed: true), true);
    expect(stockQuantityValid(0.000001), true);
    expect(stockQuantityValid(0.0000001), false);
    expect(stockQuantityValid(1e-14), false);
    expect(stockQuantityValid(1e9 + 1), false);
    expect(findStockItems([onionStock], '손질 양파').single.id, 'onion');
    expect(findStockItems([onionStock], 'kg'), isEmpty);
    for (final path in ['inventory/onion', 'receiving/request']) {
      expect(
          businessLocationSection(Uri.parse('/business-workspaces/shop/$path')),
          BusinessSection.purchasing);
    }
  });
  testWidgets(
      'empty inventory can register a seeded item and resume the receipt',
      (tester) async {
    final stock = InventoryMemory()..empty = true;
    await pumpInventory(tester, stock,
        path: '/business-workspaces/shop/receiving/request');
    await click(tester, '재고 등록·입고');
    await click(tester, '재고 품목 등록 후 계속');
    expect(find.text('양파 500g'), findsWidgets);
    await fill(tester, '재고 단위', 'g');
    await tester.ensureVisible(find.text('기록 저장').last);
    await tester.tap(find.text('기록 저장').last);
    await tester.pumpAndSettle();
    expect(stock.calls.single.action, 'item');
    expect(stock.calls.single.data['name'], '양파 500g');
    expect(find.text('품목 입고 기록'), findsOneWidget);
    expect(find.text('단위 환산: 1 봉 = ? g'), findsOneWidget);
  });
  testWidgets(
      'culinary staff can reserve and consume but cannot adjust or return',
      (tester) async {
    final stock = InventoryMemory();
    await pumpInventory(tester, stock,
        permissions: businessRolePermissions['culinary']!);
    expect(find.text('실사·재고 조정'), findsNothing);
    expect(find.text('조리용 예약'), findsOneWidget);
    await click(tester, '실제 사용 기록');
    await fill(tester, '이번 수량', '200');
    await fill(tester, '용도·사유', '점심 조리 완료');
    await click(tester, '기록 저장');
    expect(stock.calls.single.action, 'consume');
    expect(stock.calls.single.data, {
      'reservation': 'reservation',
      'revision': 2,
      'quantity': 200.0,
      'reason': '점심 조리 완료'
    });
    await reveal(tester, find.text('재고 수불 이력'));
    expect(find.text('반품 기록'), findsNothing);
  });
  testWidgets(
      'receipt requires explicit conversion and freezes the submitted request revision',
      (tester) async {
    final stock = InventoryMemory()..mapped = true;
    await pumpInventory(tester, stock,
        path: '/business-workspaces/shop/receiving/request');
    await click(tester, '품목 입고 기록');
    expect(tester.widget<TextField>(field('구매 1단위당 재고량')).readOnly, true);
    await fill(tester, '이번 수량', '2');
    await fill(tester, '용도·사유', '검수 완료');
    await click(tester, '기록 저장');
    expect(stock.calls, isEmpty);
    expect(find.text('확인 항목을 체크해 주세요.'), findsOneWidget);
    await click(tester, '실제 품목·수량·단위 환산을 확인했습니다.');
    await click(tester, '기록 저장');
    expect(stock.calls.single.action, 'receive');
    expect(stock.calls.single.data, {
      'request': 'request',
      'revision': 3,
      'line': 'line',
      'item': 'onion',
      'quantity': 2.0,
      'factor': 500.0,
      'confirmed': true,
      'reason': '검수 완료'
    });
  });
  testWidgets('shortage closure must be explicitly accepted and have a reason',
      (tester) async {
    final stock = InventoryMemory();
    await pumpInventory(tester, stock,
        path: '/business-workspaces/shop/receiving/request');
    await click(tester, '입고 마감');
    await fill(tester, '용도·사유', '잔량 납품 취소 합의');
    await click(tester, '기록 저장');
    expect(stock.calls, isEmpty);
    await click(tester, '미입고 잔량을 확인하고 마감합니다.');
    await click(tester, '기록 저장');
    expect(stock.calls.single.action, 'close');
    expect(stock.calls.single.data['shortage_accepted'], true);
  });
  testWidgets('uncertain saves freeze fields and retry the same action token',
      (tester) async {
    final stock = InventoryMemory()..failure = TimeoutException('network');
    await pumpInventory(tester, stock);
    await click(tester, '조리용 예약');
    await fill(tester, '이번 수량', '100');
    await fill(tester, '용도·사유', '저녁');
    await click(tester, '기록 저장');
    expect(stock.calls.length, 1);
    expect(tester.widget<TextField>(field('이번 수량')).enabled, false);
    stock.failure = null;
    await click(tester, '기록 저장');
    expect(stock.calls.length, 2);
    expect(stock.calls[1].id, stock.calls[0].id);
    expect(stock.calls[1].data, stock.calls[0].data);
  });
  testWidgets(
      'rolled back stock errors preserve editable inputs for correction',
      (tester) async {
    final stock = InventoryMemory()
      ..failure =
          const PostgrestException(message: 'INVENTORY_STOCK', code: 'P0001');
    await pumpInventory(tester, stock);
    await click(tester, '조리용 예약');
    await fill(tester, '이번 수량', '3000');
    await fill(tester, '용도·사유', '저녁');
    await click(tester, '기록 저장');
    expect(find.text('사용 가능 재고가 부족합니다. 최신 입고·예약량을 확인하세요.'), findsOneWidget);
    expect(tester.widget<TextField>(field('이번 수량')).controller!.text, '3000');
    expect(tester.widget<TextField>(field('이번 수량')).enabled, true);
    stock.failure = null;
    await fill(tester, '이번 수량', '100');
    await click(tester, '기록 저장');
    expect(stock.calls.last.data['quantity'], 100);
    expect(stock.calls.last.id, isNot(stock.calls.first.id));
  });
  testWidgets(
      'legacy receiving is explained without allowing synthetic historical receipts',
      (tester) async {
    final stock = InventoryMemory()
      ..legacy = true
      ..status = 'received';
    await pumpInventory(tester, stock,
        path: '/business-workspaces/shop/receiving/request');
    expect(find.textContaining('이전 방식으로 입고 완료'), findsOneWidget);
    expect(find.text('품목 입고 기록'), findsNothing);
    expect(find.text('입고 마감'), findsNothing);
  });
  testWidgets('account change closes stock form before any mutation',
      (tester) async {
    final account = StateProvider<String?>((ref) => 'staff');
    final stock = InventoryMemory();
    await pumpBusiness(
        tester, MemoryBusiness(businessRolePermissions['purchasing']!),
        initial: '/business-workspaces/shop/inventory/onion',
        overrides: [
          activeAccountIdProvider.overrideWith((ref) => ref.watch(account)),
          businessInventoryRepositoryProvider.overrideWithValue(stock)
        ]);
    await click(tester, '조리용 예약');
    final container = ProviderScope.containerOf(
        tester.element(find.byType(BusinessInventoryPage)));
    container.read(account.notifier).state = null;
    await tester.pumpAndSettle();
    expect(stock.calls, isEmpty);
    expect(find.byType(AlertDialog), findsNothing);
  });
  testWidgets('revoked purchasing permission hides stock mutation controls',
      (tester) async {
    final stock = InventoryMemory(),
        repo = MemoryBusiness(businessRolePermissions['purchasing']!);
    await pumpBusiness(tester, repo,
        initial: '/business-workspaces/shop/inventory/onion',
        overrides: [
          businessInventoryRepositoryProvider.overrideWithValue(stock)
        ]);
    final container = ProviderScope.containerOf(
        tester.element(find.byType(BusinessInventoryPage)));
    repo.business = const BusinessContext(
        id: 'shop',
        name: 'shop',
        owner: false,
        paid: true,
        approval: true,
        permissions: {'purchasing.read'});
    container.invalidate(businessContextProvider('shop'));
    await tester.pumpAndSettle();
    expect(find.text('실사·재고 조정'), findsNothing);
    expect(find.text('조리용 예약'), findsNothing);
  });
  testWidgets('return uses the original receipt and purchase quantity',
      (tester) async {
    final stock = InventoryMemory();
    await pumpInventory(tester, stock);
    await click(tester, '반품 기록');
    expect(find.textContaining('이 입고에서 반품 가능한 잔량: 2 봉'), findsOneWidget);
    await fill(tester, '이번 수량', '1');
    await fill(tester, '용도·사유', '품질 반품');
    await click(tester, '기록 저장');
    expect(stock.calls.single.action, 'return');
    expect(stock.calls.single.data,
        {'receipt': 'receipt', 'quantity': 1.0, 'reason': '품질 반품'});
  });
  testWidgets(
      'stock and duplicate request hints do not overwrite manual purchase inputs',
      (tester) async {
    final stock = InventoryMemory(),
        base = MemoryBusiness(
            {'recipes.read', 'purchasing.read', 'purchasing.write'});
    await pumpBusiness(tester, base,
        initial: '/business-workspaces/shop/menu-purchase',
        overrides: [
          businessMenuRepositoryProvider.overrideWithValue(MenuMemory(base)),
          businessInventoryRepositoryProvider.overrideWithValue(stock)
        ]);
    await click(tester, '메뉴·레시피와 인분 추가');
    await click(tester, '판매 메뉴');
    await tester.enterText(find.byType(TextField).last, '30');
    await tester.tap(find.widgetWithText(FilledButton, '추가'));
    await tester.pumpAndSettle();
    await tester.pump(const Duration(seconds: 1));
    await click(tester, '재료 필요량 계산');
    await click(tester, '양파');
    expect(find.text('어제 구매요청'), findsOneWidget);
    expect(find.textContaining('입고 예정량은 자동 차감하지 않습니다.'), findsOneWidget);
    final input = field('사용 가능 재고');
    await reveal(tester, input);
    expect(tester.widget<TextField>(input).controller!.text, isEmpty);
    expect(stock.calls, isEmpty);
  });
  for (final locale in ['ko', 'en']) {
    testWidgets(
        '$locale receiving form and inventory fit narrow screens with large text',
        (tester) async {
      final stock = InventoryMemory()..mapped = true;
      await pumpInventory(tester, stock,
          path: '/business-workspaces/shop/receiving/request',
          locale: locale,
          scale: 1.4);
      await click(tester, locale == 'ko' ? '품목 입고 기록' : 'Record item receipt');
      expect(tester.takeException(), isNull);
      await fill(tester, locale == 'ko' ? '이번 수량' : 'Quantity this time', '1');
      await click(tester, locale == 'ko' ? '닫기' : 'Close');
      expect(tester.takeException(), isNull);
    });
  }
}
