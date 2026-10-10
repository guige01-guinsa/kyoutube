import 'package:flutter_test/flutter_test.dart';
import 'package:k_youtube/features/shopping/domain/request_document_amounts.dart';
import 'package:k_youtube/features/shopping/domain/supplier_request.dart';

void main() {
  test('document amounts keep unknown prices separate from the priced subtotal',
      () {
    final result = RequestDocumentAmounts(const [
      SupplierRequestLine(
          id: 'a', name: 'Noodles', quantity: 2, unit: 'box', price: 50000),
      SupplierRequestLine(id: 'b', name: 'Onion', quantity: 5, unit: 'kg'),
      SupplierRequestLine(
          id: 'c', name: 'Bonus', quantity: 1, unit: 'pack', price: 0),
    ]);
    expect(result.amounts, [100000, null, 0]);
    expect(result.subtotal, 100000);
    expect(result.pricedCount, 2);
    expect(result.unpricedCount, 1);
    expect(requestMoney(result.subtotal), '100,000');
  });
  test('unquoted and invalid quantities never appear as a zero total', () {
    for (final quantity in [null, 0.0, -1.0, double.nan, double.infinity]) {
      final result = RequestDocumentAmounts([
        SupplierRequestLine(
            id: 'a', name: 'Item', quantity: quantity, unit: 'kg', price: 50),
      ]);
      expect(result.subtotal, isNull);
      expect(result.unpricedCount, 1);
    }
    expect(RequestDocumentAmounts([]).subtotal, isNull);
    expect(requestMoney(null), '—');
    expect(requestMoney(1234.56), '1,234.56');
  });
}
