import 'package:intl/intl.dart';
import 'supplier_request.dart';

/// Requested prices only. Unknown prices, shipping and tax are never assumed.
class RequestDocumentAmounts {
  RequestDocumentAmounts(List<SupplierRequestLine> lines)
      : amounts = List.unmodifiable(lines.map(lineAmount));
  final List<double?> amounts;
  int get pricedCount => amounts.whereType<double>().length;
  int get unpricedCount => amounts.length - pricedCount;
  double? get subtotal => pricedCount == 0
      ? null
      : amounts
          .whereType<double>()
          .fold<double>(0, (sum, amount) => sum + amount);

  static double? lineAmount(SupplierRequestLine line) {
    final quantity = line.quantity, price = line.price;
    if (quantity == null ||
        price == null ||
        !quantity.isFinite ||
        !price.isFinite ||
        quantity <= 0 ||
        price < 0) {
      return null;
    }
    final amount = quantity * price;
    return amount.isFinite ? amount : null;
  }
}

String requestMoney(double? value) => value == null || !value.isFinite
    ? '—'
    : NumberFormat('#,##0.##', 'en_US').format(value);
