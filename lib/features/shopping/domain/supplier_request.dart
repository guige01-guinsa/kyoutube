import '../../kitchen/data/shopping_persistence.dart';
import '../../kitchen/domain/shopping_units.dart';
import 'shopping_assistant.dart';
import 'business_registration.dart';

String newShoppingId() => SecureUuidGenerator().v4();

class ShoppingSupplier {
  const ShoppingSupplier(
      {required this.id,
      required this.name,
      this.contact = '',
      this.phone = '',
      this.products = '',
      this.website = '',
      this.address = '',
      this.memo = '',
      this.catalogSupplierId,
      this.publicListingId,
      this.favorite = false});
  final String id, name, contact, phone, products, website, address, memo;
  final bool favorite;
  final String? catalogSupplierId;
  final String? publicListingId;
  // Directory-only notes and preferences never enter the shared order snapshot.
  Map<String, dynamic> toRequestJson() => {
        'id': id,
        'name': name,
        'contact': contact,
        'phone': phone,
        'products': products
      };
  Map<String, dynamic> toJson() => {
        ...toRequestJson(),
        'website': website,
        'address': address,
        'memo': memo,
        'is_favorite': favorite,
      };
  factory ShoppingSupplier.fromJson(Map<String, dynamic> j) => ShoppingSupplier(
      id: j['id'] as String,
      name: j['name'] as String,
      contact: j['contact'] as String? ?? '',
      phone: j['phone'] as String? ?? '',
      products: j['products'] as String? ?? '',
      website: j['website'] as String? ?? '',
      address: j['address'] as String? ?? '',
      memo: j['memo'] as String? ?? '',
      catalogSupplierId: j['catalog_supplier_id'] as String?,
      publicListingId: j['public_listing_id'] as String?,
      favorite: j['is_favorite'] as bool? ?? false);
}

List<ShoppingSupplier> shoppingSupplierDirectory(
    Iterable<ShoppingSupplier> suppliers,
    {String query = ''}) {
  final key = query.trim().toLowerCase();
  final result = suppliers
      .where((s) =>
          key.isEmpty ||
          [s.name, s.contact, s.phone, s.products, s.website, s.address, s.memo]
              .any((value) => value.toLowerCase().contains(key)))
      .toList();
  result.sort((a, b) {
    if (a.favorite != b.favorite) return a.favorite ? -1 : 1;
    final byName = a.name.toLowerCase().compareTo(b.name.toLowerCase());
    return byName != 0 ? byName : a.id.compareTo(b.id);
  });
  return result;
}

class SupplierRequestLine {
  const SupplierRequestLine(
      {required this.id,
      required this.name,
      required this.quantity,
      required this.unit,
      this.spec = '',
      this.productUrl = '',
      this.price,
      this.sourceIds = const []});
  final String id, name, unit, spec, productUrl;
  String get details => [
        spec,
        if (shoppingProductUri(productUrl) != null) productUrl
      ].where((s) => s.isNotEmpty).join('\n');
  final double? quantity, price;
  final List<String> sourceIds;
  factory SupplierRequestLine.fromGroup(ShoppingPurchaseGroup group) =>
      SupplierRequestLine(
          id: newShoppingId(),
          name: group.name,
          quantity: group.neededQuantity,
          unit: group.unit,
          sourceIds: group.sources.map((s) => s.item.id).toList());
  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'quantity': quantity,
        'unit': unit,
        'spec': spec,
        if (productUrl.isNotEmpty) 'product_url': productUrl,
        'price': price,
        'source_ids': sourceIds
      };
  factory SupplierRequestLine.fromJson(Map<String, dynamic> j) =>
      SupplierRequestLine(
          id: j['id'] as String,
          name: j['name'] as String,
          quantity: (j['quantity'] as num?)?.toDouble(),
          unit: j['unit'] as String,
          spec: j['spec'] as String? ?? '',
          productUrl: j['product_url'] is String &&
                  shoppingProductUri(j['product_url'] as String) != null
              ? j['product_url'] as String
              : '',
          price: (j['price'] as num?)?.toDouble(),
          sourceIds: List<String>.from(j['source_ids'] as List? ?? []));
  SupplierRequestLine copyForRepeat() => SupplierRequestLine(
      id: newShoppingId(),
      name: name,
      quantity: quantity,
      unit: unit,
      spec: spec,
      productUrl: productUrl);
}

class SupplierRequest {
  const SupplierRequest(
      {required this.id,
      required this.supplier,
      required this.lines,
      this.buyer = '',
      this.buyerBusiness = const BusinessRegistration(),
      this.supplierBusiness = const BusinessRegistration(),
      this.phone = '',
      this.address = '',
      this.deliveryDate = '',
      this.deliveryWindow = '',
      this.notes = '',
      this.currency = 'KRW',
      this.status = 'draft',
      this.revision = 0,
      this.catalogSupplierId,
      this.createdAt});
  final String id,
      buyer,
      phone,
      address,
      deliveryDate,
      deliveryWindow,
      notes,
      currency,
      status;
  final ShoppingSupplier supplier;
  final BusinessRegistration buyerBusiness, supplierBusiness;
  final List<SupplierRequestLine> lines;
  final int revision;
  final String? catalogSupplierId;
  final DateTime? createdAt;
  // Full UUID keeps references unique across devices and repeated orders.
  String get reference => 'PO-${id.toUpperCase()}';
  Map<String, dynamic> get data => {
        'supplier': supplier.toRequestJson(),
        'buyer': buyer,
        if (!buyerBusiness.isEmpty || !supplierBusiness.isEmpty)
          'business_registrations': {
            'buyer': buyerBusiness.toJson(),
            'supplier': supplierBusiness.toJson(),
          },
        'phone': phone,
        'address': address,
        'delivery_date': deliveryDate,
        'delivery_window': deliveryWindow,
        'notes': notes,
        'currency': currency,
        'lines': lines.map((l) => l.toJson()).toList()
      };
  factory SupplierRequest.fromJson(Map<String, dynamic> row) {
    final d = row['data'] as Map<String, dynamic>;
    return SupplierRequest(
        id: row['id'] as String,
        supplier:
            ShoppingSupplier.fromJson(d['supplier'] as Map<String, dynamic>),
        lines: (d['lines'] as List)
            .map((l) => SupplierRequestLine.fromJson(l))
            .toList(),
        buyer: d['buyer'] as String,
        buyerBusiness: BusinessRegistration.fromJson(
            (d['business_registrations'] as Map?)?['buyer']),
        supplierBusiness: BusinessRegistration.fromJson(
            (d['business_registrations'] as Map?)?['supplier']),
        phone: d['phone'] as String,
        address: d['address'] as String,
        deliveryDate: d['delivery_date'] as String,
        deliveryWindow: d['delivery_window'] as String,
        notes: d['notes'] as String,
        currency: d['currency'] as String,
        status: row['status'] as String,
        revision: (row['revision'] as num).toInt(),
        catalogSupplierId: row['catalog_supplier_id'] as String?,
        createdAt: DateTime.tryParse(row['created_at'] as String? ?? ''));
  }
  SupplierRequest repeat() => SupplierRequest(
      id: newShoppingId(),
      supplier: supplier,
      lines: lines.map((l) => l.copyForRepeat()).toList(),
      buyer: buyer,
      buyerBusiness: buyerBusiness,
      supplierBusiness: supplierBusiness,
      phone: phone,
      address: address,
      currency: currency);
}

String requestUnit(String unit, bool english) =>
    english ? unit.replaceAll('_', ' ') : shoppingUnitLabel(unit);
String requestStatus(String status, bool english) =>
    (english
        ? const {
            'draft': 'Draft',
            'sent': 'Delivery confirmed by you',
            'accepted': 'Supplier acceptance confirmed by you',
            'received': 'Receipt confirmed by you',
            'cancelled': 'Cancelled',
          }
        : const {
            'draft': '작성 중',
            'sent': '전달 확인',
            'accepted': '업체 수락 확인',
            'received': '입고 확인',
            'cancelled': '취소'
          })[status] ??
    status;

String supplierRequestText(SupplierRequest r, {required bool english}) {
  String t(String ko, String en) => english ? en : ko;
  final out = <String>[
    t('[레시피 스카우트 구매 요청서]', '[Recipe Scout purchase request]'),
    r.reference,
    '${t('협력업체', 'Supplier')}: ${r.supplier.name}',
    if (r.supplier.contact.isNotEmpty)
      '${t('담당자', 'Contact')}: ${r.supplier.contact}',
    '${t('요청자', 'Buyer')}: ${r.buyer}',
    if (r.buyerBusiness.number.isNotEmpty)
      '${t('요청 업소 사업자등록번호', 'Buyer business registration number')}: ${r.buyerBusiness.formattedNumber}',
    if (r.supplierBusiness.number.isNotEmpty)
      '${t('공급업체 사업자등록번호', 'Supplier business registration number')}: ${r.supplierBusiness.formattedNumber}',
    if (r.phone.isNotEmpty) '${t('회신 연락처', 'Reply to')}: ${r.phone}',
    if (r.deliveryDate.isNotEmpty || r.deliveryWindow.isNotEmpty)
      '${t('희망 납품', 'Requested delivery')}: ${r.deliveryDate} ${r.deliveryWindow}',
    if (r.address.isNotEmpty) '${t('납품 장소', 'Delivery address')}: ${r.address}',
    '',
    for (var i = 0; i < r.lines.length; i++) ...[
      '${i + 1}. ${r.lines[i].name} | ${shoppingNumber(r.lines[i].quantity)} ${requestUnit(r.lines[i].unit, english)}',
      if (r.lines[i].details.isNotEmpty) '   ${r.lines[i].details}',
      '   ${r.lines[i].price == null ? t('견적 요청', 'Quote requested') : '${t('단가', 'Unit price')}: ${shoppingNumber(r.lines[i].price)} ${r.currency} / ${requestUnit(r.lines[i].unit, english)}'}',
    ],
    '',
    if (r.notes.isNotEmpty) '${t('요청사항', 'Notes')}: ${r.notes}',
    t('납품 가능 여부와 배송비·세금을 포함한 총금액을 회신해 주세요.',
        'Please confirm availability and the total including delivery and taxes.'),
    t('대체 상품은 먼저 확인 부탁드립니다. 이 문서는 구매 요청이며 결제 확인서가 아닙니다.',
        'Please confirm substitutions first. This is a purchase request, not proof of payment.'),
  ];
  return out.join('\n');
}

bool validRequestDate(String value) {
  if (value.isEmpty) return true;
  if (!RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(value)) return false;
  final d = DateTime.tryParse(value);
  return d != null && d.toIso8601String().substring(0, 10) == value;
}

/// Reconnect only original, still-pending items with compatible units.
/// A repeated request deliberately has no links to a previous shopping list.
ShoppingPurchaseGroup? requestReceiptGroup(
    SupplierRequestLine line, List<ShoppingPurchaseGroup> groups) {
  final sources = groups
      .where((g) =>
          shoppingNameKey(g.name) == shoppingNameKey(line.name) &&
          shoppingConvert(1, line.unit, g.unit) != null)
      .expand((g) => g.sources)
      .where((s) => line.sourceIds.contains(s.item.id))
      .toList();
  if (sources.isEmpty) return null;
  return ShoppingPurchaseGroup(
      key: line.id,
      name: line.name,
      unit: shoppingBaseUnit(line.unit),
      sources: sources);
}
