import 'dart:convert';
import 'dart:typed_data';
import 'supplier_request.dart';

class RequestLedgerFilter {
  const RequestLedgerFilter(
      {this.from, this.before, this.status = '', this.query = ''});
  final DateTime? from, before;
  final String status, query;
  Map<String, dynamic> params({int offset = 0, int limit = 50}) => {
        'p_from': from?.toUtc().toIso8601String(),
        'p_before': before?.toUtc().toIso8601String(),
        'p_status': status,
        'p_query': query.trim(),
        'p_offset': offset,
        'p_limit': limit,
      };
}

class RequestLedgerRow {
  RequestLedgerRow.fromJson(Map<String, dynamic> j)
      : id = j['id'] as String,
        supplier = j['supplier'] as String,
        buyer = j['buyer'] as String,
        buyerNumber = j['buyer_number'] as String? ?? '',
        supplierNumber = j['supplier_number'] as String? ?? '',
        createdAt = DateTime.parse(j['created_at'] as String).toLocal(),
        deliveryDate = j['delivery_date'] as String,
        status = j['status'] as String,
        currency = j['currency'] as String,
        itemCount = (j['item_count'] as num).toInt(),
        unpricedCount = (j['unpriced_count'] as num).toInt(),
        pricedTotal = j['priced_total'].toString();
  final String id,
      supplier,
      buyer,
      buyerNumber,
      supplierNumber,
      deliveryDate,
      status,
      currency;
  final DateTime createdAt;
  final int itemCount, unpricedCount;
  final String pricedTotal;
  String get reference => 'PO-${id.toUpperCase()}';
  String get amount => ledgerAmount(pricedTotal, currency);
}

class RequestLedgerTotal {
  RequestLedgerTotal.fromJson(Map<String, dynamic> j)
      : currency = j['currency'] as String,
        requestCount = (j['request_count'] as num).toInt(),
        cancelledCount = (j['cancelled_count'] as num).toInt(),
        unpricedCount = (j['unpriced_count'] as num).toInt(),
        pricedTotal = j['priced_total'].toString();
  final String currency;
  final int requestCount, cancelledCount, unpricedCount;
  final String pricedTotal;
  String get amount => ledgerAmount(pricedTotal, currency);
}

// PostgreSQL sends rounded decimal strings so web doubles cannot lose cents.
String ledgerAmount(String value, String currency) {
  if (!RegExp(r'^\d+(\.\d+)?$').hasMatch(value)) {
    throw const FormatException('Invalid ledger amount');
  }
  final parts = value.split('.');
  return currency == 'KRW'
      ? parts.first
      : '${parts.first}.${(parts.length > 1 ? parts[1] : '').padRight(2, '0').substring(0, 2)}';
}

class RequestLedgerPageData {
  RequestLedgerPageData.fromJson(Map<String, dynamic> j)
      : rows = (j['rows'] as List)
            .map((v) => RequestLedgerRow.fromJson(Map<String, dynamic>.from(v)))
            .toList(),
        totals = (j['totals'] as List)
            .map((v) =>
                RequestLedgerTotal.fromJson(Map<String, dynamic>.from(v)))
            .toList(),
        totalCount = (j['total_count'] as num).toInt();
  final List<RequestLedgerRow> rows;
  final List<RequestLedgerTotal> totals;
  final int totalCount;
}

String ledgerDate(DateTime date) =>
    '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';

/// Quote fields AND neutralize spreadsheet formula prefixes (including whitespace).
String ledgerCsvCell(String value) {
  final safe = RegExp(r'^[\s\uFEFF]*[=+@\-]').hasMatch(value) ||
          value.startsWith('\t') ||
          value.startsWith('\r') ||
          value.startsWith('\n')
      ? "'$value"
      : value;
  return '"${safe.replaceAll('"', '""')}"';
}

Uint8List requestLedgerCsv(List<RequestLedgerRow> rows,
    {required bool english}) {
  String t(String ko, String en) => english ? en : ko;
  final records = <List<String>>[
    [
      t('요청번호', 'Reference'),
      t('작성일', 'Created'),
      t('공급업체', 'Supplier'),
      t('요청 업소', 'Buyer'),
      t('업소 사업자번호', 'Buyer registration'),
      t('공급업체 사업자번호', 'Supplier registration'),
      t('희망 납품일', 'Delivery date'),
      t('상태', 'Status'),
      t('통화', 'Currency'),
      t('입력 단가 기준 소계', 'Entered-price subtotal'),
      t('견적 대기 품목수', 'Unpriced items'),
      t('품목수', 'Items')
    ],
    for (final r in rows)
      [
        r.reference,
        ledgerDate(r.createdAt),
        r.supplier,
        r.buyer,
        r.buyerNumber,
        r.supplierNumber,
        r.deliveryDate,
        requestStatus(r.status, english),
        r.currency,
        r.amount,
        '${r.unpricedCount}',
        '${r.itemCount}'
      ],
  ];
  return Uint8List.fromList(utf8.encode(
      '\uFEFF${records.map((row) => row.map(ledgerCsvCell).join(',')).join('\r\n')}\r\n'));
}
