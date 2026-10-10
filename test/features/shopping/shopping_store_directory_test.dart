import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:k_youtube/features/shopping/data/purchase_cleanup_repository.dart';
import 'package:k_youtube/features/shopping/domain/purchase_cleanup.dart';
import 'purchase_cleanup_test.dart' show CleanupMemory;
import 'package:k_youtube/features/shopping/domain/supplier_request.dart';
import 'package:k_youtube/features/shopping/presentation/supplier_request_editor.dart';
import 'package:k_youtube/features/shopping/presentation/supplier_requests_page.dart';
import 'supplier_request_widget_test.dart' show RequestRepo, pumpRequest, show;

class StoreCleanup extends CleanupMemory {
  StoreCleanup(this.stores);
  final RequestRepo stores;
  @override
  Future<PurchaseCleanupIndex> index(String? workspace) async =>
      PurchaseCleanupIndex(hidden.map((id) => 'supplier:$id').toSet());
  @override
  Future<List<PurchaseCleanupEntry>> list(
          {String? workspace,
          required String kind,
          required bool archived,
          DateTime? before,
          String query = '',
          int offset = 0}) async =>
      stores.directory
          .where((s) =>
              hidden.contains(s.id) == archived &&
              (query.isEmpty || s.id == query))
          .map((s) => PurchaseCleanupEntry(
              id: s.id,
              title: s.name,
              detail: '',
              status: 'saved',
              token: 'token',
              eligible: true,
              archived: archived))
          .toList();
}

const store = ShoppingSupplier(
    id: 'store-b',
    name: '바른 식자재',
    contact: '담당자',
    phone: '010-0000-0000',
    website: 'https://example.com/groceries',
    address: '테스트 매장 주소',
    products: '두부, 버섯',
    memo: '금요일 오전 방문',
    favorite: true);

Finder field(String label) => find.byWidgetPredicate(
    (w) => w is TextField && w.decoration?.labelText == label);

Future<void> fill(WidgetTester tester, String label, String value) async {
  final target = field(label);
  await show(tester, target);
  await tester.enterText(target, value);
  tester.testTextInput.hide();
  await tester.pumpAndSettle();
}

void main() {
  test('directory fields round trip but never enter the request snapshot', () {
    final restored = ShoppingSupplier.fromJson(store.toJson());
    expect(restored.toJson(), store.toJson());
    final request =
        SupplierRequest(id: 'request', supplier: restored, lines: const []);
    expect(request.data['supplier'], store.toRequestJson());
    for (final privateValue in [store.memo, store.address, store.website]) {
      expect(request.data.toString(), isNot(contains(privateValue)));
      expect(supplierRequestText(request, english: false),
          isNot(contains(privateValue)));
      expect(supplierRequestText(request, english: true),
          isNot(contains(privateValue)));
    }
    final old = ShoppingSupplier.fromJson(store.toRequestJson());
    expect(old.website, isEmpty);
    expect(old.memo, isEmpty);
    expect(old.favorite, isFalse);
  });
  test('directory search includes notes and products, with favorites first',
      () {
    const other =
        ShoppingSupplier(id: 'store-a', name: 'AAA Market', products: 'Rice');
    final source = [other, store];
    expect(shoppingSupplierDirectory(source), [store, other]);
    expect(source, [other, store]);
    expect(shoppingSupplierDirectory(source, query: ' RICE '), [other]);
    expect(shoppingSupplierDirectory(source, query: '금요일'), [store]);
    expect(shoppingSupplierDirectory(source, query: '없는 업체'), isEmpty);
  });

  for (final language in ['ko', 'en']) {
    testWidgets(
        '$language directory opens only the selected store and preselects requests',
        (tester) async {
      final repo = RequestRepo()..directory.add(store);
      final opened = <Uri>[];
      await pumpRequest(tester, repo, [],
          language: language,
          opened: opened,
          home: const SupplierRequestsPage(showStores: true));
      final search = find.byType(TextField).first;
      await tester.enterText(search, '금요일');
      await tester.pumpAndSettle();
      expect(find.text(store.name), findsOneWidget);
      expect(opened, isEmpty);
      final openLabel = language == 'ko' ? '구매 사이트 열기' : 'Open store website';
      await show(tester, find.text(openLabel));
      await tester.tap(find.text(openLabel));
      await tester.pumpAndSettle();
      expect(opened, [Uri.parse(store.website)]);
      expect(repo.saves, isEmpty);
      final requestLabel =
          language == 'ko' ? '이 구매처에 요청' : 'Request from this store';
      await tester.tap(find.text(requestLabel));
      await tester.pumpAndSettle();
      expect(find.byType(SupplierRequestEditor), findsOneWidget);
      final dropdown = tester.widget<DropdownButton<String>>(
          find.byType(DropdownButton<String>).first);
      expect(dropdown.value, store.id);
      expect(repo.saves, isEmpty);
      expect(tester.takeException(), isNull);
    });
  }
  testWidgets(
      'store creation validates links, saves edits and archives without deleting identity',
      (tester) async {
    final repo = RequestRepo()..directory.clear();
    final cleanup = StoreCleanup(repo);
    await pumpRequest(tester, repo, [],
        overrides: [
          purchaseCleanupRepositoryProvider.overrideWithValue(cleanup)
        ],
        home: const SupplierRequestsPage(showStores: true));
    await tester.tap(find.text('구매처 추가'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('저장'));
    await tester.pumpAndSettle();
    expect(find.text('구매처 이름을 입력해 주세요.'), findsOneWidget);
    await fill(tester, '구매처 이름', store.name);
    await show(tester, find.byType(CheckboxListTile));
    await tester.tap(find.byType(CheckboxListTile));
    await fill(tester, '구매 사이트 링크 (선택)', 'javascript:alert(1)');
    await tester.tap(find.text('저장'));
    await tester.pumpAndSettle();
    expect(repo.directory, isEmpty);
    await fill(tester, '구매 사이트 링크 (선택)', store.website);
    await fill(tester, '담당자 (선택)', store.contact);
    await fill(tester, '연락처 (선택)', store.phone);
    await fill(tester, '주로 구매하는 재료', store.products);
    await fill(tester, '구매처 주소 (선택)', store.address);
    await fill(tester, '나만의 구매처 메모', store.memo);
    await tester.tap(find.text('저장'));
    await tester.pumpAndSettle();
    final saved = repo.directory.single;
    expect(saved.website, store.website);
    expect(saved.address, store.address);
    expect(saved.memo, store.memo);
    expect(saved.favorite, isTrue);
    await show(tester, find.text('수정'));
    await tester.tap(find.text('수정'));
    await tester.pumpAndSettle();
    await fill(tester, '나만의 구매처 메모', '수요일 배송');
    await tester.tap(find.text('저장'));
    await tester.pumpAndSettle();
    expect(repo.directory.single.id, saved.id);
    expect(repo.directory.single.memo, '수요일 배송');
    await show(tester, find.byTooltip('관리'));
    await tester.tap(find.byTooltip('관리'));
    await tester.pumpAndSettle();
    expect(find.text('삭제'), findsNothing);
    await tester.tap(find.text('보관·복원'));
    await tester.pumpAndSettle();
    expect(repo.directory.length, 1);
    await tester.tap(find.widgetWithText(FilledButton, '확인'));
    await tester.pumpAndSettle();
    expect(cleanup.hidden, contains(saved.id));
    expect(repo.directory.single.id, saved.id);
    expect(find.text(store.name), findsNothing);
    expect(repo.rows, isNotEmpty);
    expect(tester.takeException(), isNull);
  });
}
