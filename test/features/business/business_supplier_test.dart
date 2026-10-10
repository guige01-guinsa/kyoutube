import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:k_youtube/features/auth/application/auth_providers.dart';
import 'package:k_youtube/features/business/data/business_menu_repository.dart';
import 'package:k_youtube/features/business/data/business_supplier_repository.dart';
import 'package:k_youtube/features/business/domain/business_menu.dart';
import 'package:k_youtube/features/business/domain/business_supplier.dart';
import 'package:k_youtube/features/business/domain/business_workspace.dart';
import 'package:k_youtube/features/business/domain/business_navigation.dart';
import 'package:k_youtube/features/business/presentation/business_pages.dart';
import 'package:k_youtube/features/shopping/data/supplier_request_repository.dart';
import 'package:k_youtube/features/shopping/domain/supplier_request.dart';
import 'business_flow_test.dart' show MemoryBusiness, pumpBusiness;
import 'business_menu_test.dart' show MenuMemory;

const shared = BusinessSupplier(id: 'supplier', revision: 2, data: {
  'name': '공동 농산',
  'contact': '영업팀',
  'phone': '02-000-0000',
  'address': '서울 강남',
  'website': 'https://example.test',
  'active': true,
});
const pack = BusinessSupplierProduct(
    id: 'product',
    supplierId: 'supplier',
    revision: 3,
    data: {
      'name': '국산 양파 2kg',
      'spec': '국내산',
      'content_quantity': 2,
      'content_unit': 'kg',
      'pack_unit': '봉',
      'active': true,
    });

class SupplierMemory implements BusinessSupplierRepository {
  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
  final rows = <BusinessSupplier>[
    shared,
    const BusinessSupplier(id: 'inactive', revision: 1, data: {
      'name': '중지된 업체',
      'active': false,
      'contact': '영업팀',
      'phone': '02-000-0000',
      'address': '서울 강남',
      'website': ''
    })
  ];
  static const sharedData = {
    'name': '공동 농산',
    'contact': '영업팀',
    'phone': '02-000-0000',
    'address': '서울 강남',
    'website': '',
    'active': true
  };
  Map<String, dynamic>? saved;
  int writes = 0;
  List<MenuPurchaseAdjustment>? adjustments;
  Map<String, BusinessSupplierProduct>? selections;
  @override
  Future<List<BusinessSupplier>> suppliers(String workspace) async => rows;
  @override
  Future<List<BusinessSupplierProduct>> products(
          String workspace, String supplier) async =>
      [
        pack,
        const BusinessSupplierProduct(
            id: 'wrong-unit',
            supplierId: 'supplier',
            revision: 1,
            data: {
              'name': '양파 g 규격',
              'spec': '',
              'content_quantity': 2000,
              'content_unit': 'g',
              'pack_unit': '봉',
              'active': true
            })
      ];
  @override
  Future<void> saveSupplier(String workspace, String id, int revision,
      Map<String, dynamic> data) async {
    saved = data;
    writes++;
    rows.removeWhere((s) => s.id == id);
    rows.add(BusinessSupplier(id: id, revision: revision + 1, data: data));
  }

  @override
  Future<void> saveProduct(String workspace, String supplier, String id,
      int revision, Map<String, dynamic> data) async {
    saved = data;
    writes++;
  }

  @override
  Future<Map<String, dynamic>?> snapshot(
          String workspace, String request) async =>
      null;
  @override
  Future<BusinessRecord> purchase(
      String workspace,
      String request,
      String purpose,
      List<MenuPurchaseSource> sources,
      List<MenuPurchaseAdjustment> adjustments,
      BusinessSupplier supplier,
      Map<String, BusinessSupplierProduct> products) async {
    this.adjustments = adjustments;
    selections = Map.of(products);
    writes++;
    // Keep the editor visible so the test can check what was submitted without an unrelated record editor.
    throw StateError('BUSINESS_STALE');
  }
}

Future<void> reveal(WidgetTester tester, Finder finder) async {
  if (finder.evaluate().isEmpty) {
    await tester.scrollUntilVisible(finder, 200,
        scrollable: find.byType(Scrollable).first);
  }
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
}

Future<void> click(WidgetTester tester, String text) async {
  final f = find.text(text);
  await reveal(tester, f);
  await tester.tap(f);
  await tester.pumpAndSettle();
}

void main() {
  test(
      'selective personal import never shares notes, preferences or private IDs',
      () {
    const personal = ShoppingSupplier(
        id: 'private-id',
        name: '개인 거래처',
        phone: '010-0000-0000',
        contact: '사적 담당자',
        address: '부산',
        website: 'https://example.test',
        memo: '비공개 메모',
        products: '개인 제품 메모',
        favorite: true,
        catalogSupplierId: 'external');
    final nameOnly = sharedSupplierCopy(personal, {});
    expect(nameOnly, {
      'name': '개인 거래처',
      'phone': '',
      'contact': '',
      'address': '',
      'website': '',
      'active': true
    });
    final selected =
        sharedSupplierCopy(personal, {'phone', 'memo', 'id', 'products'});
    expect(selected['phone'], personal.phone);
    expect(selected.containsKey('memo'), false);
    expect(selected.containsKey('id'), false);
    expect(selected.containsKey('products'), false);
    expect(selected['contact'], '');
  });
  test(
      'shared supplier search includes location but hides inactive unless requested',
      () {
    final repo = SupplierMemory();
    expect(findBusinessSuppliers(repo.rows, '강남').single.id, shared.id);
    expect(findBusinessSuppliers(repo.rows, '중지'), isEmpty);
    expect(
        findBusinessSuppliers(repo.rows, '중지', includeInactive: true).single.id,
        'inactive');
    expect(
        businessLocationSection(
            Uri.parse('/business-workspaces/shop/suppliers/supplier')),
        BusinessSection.purchasing);
  });
  test('product unit compatibility does not infer conversion', () {
    expect(pack.matchesUnit(' KG '), true);
    expect(pack.matchesUnit('g'), false);
    expect(pack.selection('ingredient'),
        {'key': 'ingredient', 'id': 'product', 'revision': 3});
  });
  for (final locale in ['ko', 'en']) {
    testWidgets(
        'read-only shared supplier list and details fit small large-text screen $locale',
        (tester) async {
      final repo = SupplierMemory();
      await pumpBusiness(tester, MemoryBusiness({'purchasing.read'}),
          initial: '/business-workspaces/shop/suppliers',
          locale: locale,
          width: 390,
          textScale: 2,
          overrides: [
            businessSupplierRepositoryProvider.overrideWithValue(repo)
          ]);
      expect(
          find.text(locale == 'ko' ? '거래처 등록' : 'Add supplier'), findsNothing);
      expect(find.text('중지된 업체'), findsNothing);
      await click(tester, '공동 농산');
      expect(find.text(locale == 'ko' ? '상품 규격 등록' : 'Add pack specification'),
          findsNothing);
      await reveal(tester, find.text('국산 양파 2kg'));
      expect(find.text('국산 양파 2kg'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }
  testWidgets(
      'personal import requires selected fields and explicit shared save',
      (tester) async {
    final repo = SupplierMemory();
    await pumpBusiness(
        tester, MemoryBusiness({'purchasing.read', 'purchasing.write'}),
        initial: '/business-workspaces/shop/suppliers',
        overrides: [
          businessSupplierRepositoryProvider.overrideWithValue(repo),
          shoppingSuppliersProvider.overrideWith((ref) async => [
                const ShoppingSupplier(
                    id: 'p',
                    name: '개인 업체',
                    contact: '개인 담당자',
                    phone: '010-1234-5678',
                    memo: '숨겨야 할 메모',
                    address: '비공개 주소')
              ])
        ]);
    await click(tester, '개인 거래처에서 가져오기');
    await click(tester, '개인 업체');
    expect(repo.writes, 0);
    expect(find.text('숨겨야 할 메모'), findsNothing);
    await click(tester, '연락처');
    await click(tester, '공유할 사본 확인');
    expect(find.widgetWithText(TextFormField, '010-1234-5678'), findsOneWidget);
    expect(find.widgetWithText(TextFormField, '개인 담당자'), findsNothing);
    expect(repo.writes, 0);
    await click(tester, '공동 자료로 저장');
    expect(repo.writes, 1);
    expect(repo.saved!['phone'], '010-1234-5678');
    expect(repo.saved!['contact'], '');
    expect(repo.saved!['address'], '');
    expect(repo.saved!.containsKey('memo'), false);
    expect(tester.takeException(), isNull);
  });
  testWidgets('account switch closes private supplier import without saving',
      (tester) async {
    final account = StateProvider<String?>((ref) => 'staff');
    final repo = SupplierMemory();
    await pumpBusiness(
        tester, MemoryBusiness({'purchasing.read', 'purchasing.write'}),
        initial: '/business-workspaces/shop/suppliers',
        overrides: [
          activeAccountIdProvider.overrideWith((ref) => ref.watch(account)),
          businessSupplierRepositoryProvider.overrideWithValue(repo)
        ]);
    await click(tester, '거래처 등록');
    expect(find.text('공동 자료로 저장'), findsOneWidget);
    final container = ProviderScope.containerOf(
        tester.element(find.byType(BusinessSuppliersPage)));
    container.read(account.notifier).state = null;
    await tester.pumpAndSettle();
    expect(find.text('공동 자료로 저장'), findsNothing);
    expect(find.text('공동 농산'), findsNothing);
    expect(repo.writes, 0);
  });
  testWidgets(
      'supplier product controls pack quantity and must be reviewed before purchase',
      (tester) async {
    final base = MemoryBusiness(
            {'recipes.read', 'purchasing.read', 'purchasing.write'}),
        repo = SupplierMemory();
    await pumpBusiness(tester, base,
        initial: '/business-workspaces/shop/menu-purchase',
        overrides: [
          businessMenuRepositoryProvider.overrideWithValue(MenuMemory(base)),
          businessSupplierRepositoryProvider.overrideWithValue(repo)
        ]);
    await click(tester, '메뉴·레시피와 인분 추가');
    await click(tester, '판매 메뉴');
    await tester.enterText(find.byType(TextField).last, '30');
    await tester.tap(find.widgetWithText(FilledButton, '추가'));
    await tester.pumpAndSettle();
    await tester.pump(const Duration(seconds: 1));
    await click(tester, '재료 필요량 계산');
    await click(tester, '업소 공동 거래처 선택');
    expect(find.text('중지된 업체'), findsNothing);
    await click(tester, '공동 농산');
    await click(tester, '공급업체 상품 연결');
    expect(find.text('양파 g 규격'), findsNothing);
    await click(tester, '국산 양파 2kg');
    final quantity = find.widgetWithText(TextField, '포장 1개당 양 (kg)');
    expect(tester.widget<TextField>(quantity).enabled, false);
    for (final pair in [('사용 가능 재고 (kg)', '1'), ('입고 예정 (kg)', '0')]) {
      final f = find.widgetWithText(TextField, pair.$1);
      await reveal(tester, f);
      await tester.enterText(f, pair.$2);
      await tester.pump();
    }
    expect(find.textContaining('→ 2 봉'), findsOneWidget);
    await click(tester, '재고·입고 예정·포장 규격을 확인했습니다.');
    await click(tester, '확인한 수량으로 구매 초안 만들기');
    await tester.tap(find.widgetWithText(FilledButton, '확인'));
    await tester.pumpAndSettle();
    expect(repo.writes, 1);
    expect(repo.selections!.values.single.id, pack.id);
    expect(repo.adjustments!.single.packSize, 2);
    await click(tester, '연결 해제');
    expect(tester.widget<TextField>(quantity).enabled, true);
    final confirmed = tester.widget<CheckboxListTile>(
        find.widgetWithText(CheckboxListTile, '재고·입고 예정·포장 규격을 확인했습니다.'));
    expect(confirmed.value, false);
    expect(tester.takeException(), isNull);
  });
}
