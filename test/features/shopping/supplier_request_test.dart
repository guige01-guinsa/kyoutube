import 'dart:io';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:k_youtube/features/shopping/application/supplier_request_pdf.dart';
import 'package:k_youtube/features/shopping/domain/shopping_assistant.dart';
import 'package:k_youtube/features/shopping/domain/supplier_request.dart';
import 'shopping_assistant_test.dart' show shoppingItem, shoppingList;

const sampleSupplier = ShoppingSupplier(
    id: '63000000-0000-4000-8000-000000000001',
    name: '늘푸른 식자재 / Green Pantry',
    contact: '김담당',
    phone: '010-0000-0000',
    products: '채소, 두부');
SupplierRequest sampleRequest(
        {List<SupplierRequestLine>? lines, String status = 'draft'}) =>
    SupplierRequest(
        id: '63000000-0000-4000-8000-000000000011',
        supplier: sampleSupplier,
        buyer: '스카우트 키친',
        phone: '010-0000-0001',
        address: '테스트시 예시로 10, 주방 입고장 (예시 주소)',
        deliveryDate: '2026-09-15',
        deliveryWindow: '오전 9시~11시',
        status: status,
        revision: 1,
        notes: '배송 전 연락 부탁드립니다. 품절 시 대체 상품을 먼저 확인해 주세요.',
        lines: lines ??
            const [
              SupplierRequestLine(
                  id: '63000000-0000-4000-8000-000000000021',
                  name: '두부',
                  quantity: 4,
                  unit: 'pack',
                  spec: '부침용 500g, 냉장',
                  price: 2500,
                  sourceIds: ['a']),
              SupplierRequestLine(
                  id: '63000000-0000-4000-8000-000000000022',
                  name: '양파',
                  quantity: 5,
                  unit: 'kg',
                  spec: '국산, 중간 크기'),
              SupplierRequestLine(
                  id: '63000000-0000-4000-8000-000000000023',
                  name: '대파',
                  quantity: 2,
                  unit: 'kg',
                  spec: '손질 전'),
            ]);
void main() {
  test(
      'request text preserves explicit units, quote and buyer delivery details',
      () {
    final request = sampleRequest();
    final ko = supplierRequestText(request, english: false);
    final en = supplierRequestText(request, english: true);
    expect(ko, contains('4 팩'));
    expect(ko, contains('2500 KRW / 팩'));
    expect(ko, contains('견적 요청'));
    expect(ko, contains(request.reference));
    expect(en, contains('4 pack'));
    expect(en, contains('Quote requested'));
    expect(en, contains('not proof of payment'));
    expect(en, isNot(contains('source_ids')));
    expect(en, isNot(contains('63000000-0000-4000-8000-000000000001')));
  });
  test(
      'repeat uses a new identity and clears old price, schedule and source links',
      () {
    final original = sampleRequest(status: 'received');
    final copy = original.repeat();
    expect(copy.id, isNot(original.id));
    expect(copy.status, 'draft');
    expect(copy.revision, 0);
    expect(copy.deliveryDate, '');
    expect(copy.deliveryWindow, '');
    expect(copy.notes, '');
    expect(copy.lines.first.price, isNull);
    expect(copy.lines.first.sourceIds, isEmpty);
    expect(copy.lines.first.quantity, 4);
    expect(copy.lines.first.spec, original.lines.first.spec);
    expect(copy.address, original.address);
  });
  test('receipt reconnects only original compatible pending items', () {
    final groups = shoppingPurchaseGroups([
      shoppingList(shoppingItem('a', 1, 'kg', name: '두부')),
      shoppingList(shoppingItem('b', 500, 'g', name: '두부')),
    ]);
    const line = SupplierRequestLine(
        id: 'line', name: '두부', quantity: 1, unit: 'kg', sourceIds: ['a']);
    final group = requestReceiptGroup(line, groups)!;
    expect(group.sources.map((s) => s.item.id), ['a']);
    expect(group.unit, 'g');
    expect(group.neededQuantity, 1000);
    expect(requestReceiptGroup(line.copyForRepeat(), groups), isNull);
    expect(requestReceiptGroup(sampleRequest().lines.first, groups), isNull);
  });
  test('date validation rejects normalized impossible days', () {
    expect(validRequestDate('2026-02-30'), isFalse);
    expect(validRequestDate('2028-02-29'), isTrue);
    expect(validRequestDate(''), isTrue);
    expect(validRequestDate('2026-9-3'), isFalse);
  });
  test('snapshot round trip retains manual state and numeric values', () {
    final r = sampleRequest(status: 'accepted');
    final copy = SupplierRequest.fromJson({
      'id': r.id,
      'data': r.data,
      'status': r.status,
      'revision': 3,
      'created_at': '2026-09-13T00:00:00Z'
    });
    expect(copy.data, r.data);
    expect(copy.revision, 3);
    expect(copy.status, 'accepted');
  });
  test('offline Korean and English PDFs support a long multipage order',
      () async {
    final font = ByteData.sublistView(
        await File('assets/fonts/NanumGothic-Regular.ttf').readAsBytes());
    for (final en in [false, true]) {
      final bytes =
          await supplierRequestPdf(sampleRequest(), font, english: en);
      expect(String.fromCharCodes(bytes.take(5)), '%PDF-');
      if (const bool.fromEnvironment('SAVE_REQUEST_PDFS')) {
        await Directory('.artifacts/supplier-requests').create(recursive: true);
        await File(
                '.artifacts/supplier-requests/request-${en ? 'en' : 'ko'}.pdf')
            .writeAsBytes(bytes);
      }
    }
    final long = sampleRequest(
        lines: List.generate(
            100,
            (i) => SupplierRequestLine(
                id: '$i',
                name: '식재료 ${i + 1} / Ingredient ${i + 1}',
                quantity: (i + 1).toDouble(),
                unit: 'kg',
                spec:
                    '냉장 보관, 국산 원산지 확인, 포장 손상 없는 상품 / Refrigerated, check origin and packaging.')));
    final bytes = await supplierRequestPdf(long, font, english: false);
    expect(bytes.length, greaterThan(10000));
    if (const bool.fromEnvironment('SAVE_REQUEST_PDFS')) {
      await File('.artifacts/supplier-requests/request-long.pdf')
          .writeAsBytes(bytes);
    }
  });
}
