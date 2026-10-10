import 'dart:convert';
import '../../shopping/domain/shopping_affiliate.dart';
import '../../shopping/domain/coupang_purchase_plan.dart';
import 'business_workspace.dart';

enum BusinessCoupangBlock { access, practice, approval, closed, invalid }

BusinessCoupangBlock? businessCoupangBlock(
    BusinessContext business, BusinessRecord record) {
  if (business.id != record.workspace ||
      !business.can('purchasing.read') ||
      !business.can('purchasing.write')) {
    return BusinessCoupangBlock.access;
  }
  if (business.isTest || record.isTest) return BusinessCoupangBlock.practice;
  if (record.kind != 'purchase') return BusinessCoupangBlock.invalid;
  if (['draft', 'review'].contains(record.status)) {
    return BusinessCoupangBlock.approval;
  }
  if (record.status != 'approved') return BusinessCoupangBlock.closed;
  return null;
}

/// Preserve request units and line identity. Product packaging is never inferred.
class BusinessCoupangLine {
  const BusinessCoupangLine(
      {required this.index,
      required this.name,
      required this.quantity,
      required this.unit,
      required this.spec,
      this.price});
  final int index;
  final String name, unit, spec;
  final double quantity;
  final double? price;
}

List<BusinessCoupangLine> businessCoupangLines(BusinessRecord record) {
  final rows = record.data['lines'];
  if (rows is! List) return [];
  return [
    for (var i = 0; i < rows.length; i++)
      if (rows[i] case final Map row)
        if (row['name'] is String &&
            (row['name'] as String).trim().isNotEmpty &&
            row['unit'] is String &&
            (row['unit'] as String).trim().isNotEmpty &&
            row['quantity'] is num &&
            (row['quantity'] as num).isFinite &&
            (row['quantity'] as num) > 0 &&
            (row['quantity'] as num) <= 1e9)
          BusinessCoupangLine(
              index: i,
              name: row['name'] as String,
              quantity: (row['quantity'] as num).toDouble(),
              unit: row['unit'] as String,
              spec: row['spec'] is String ? row['spec'] as String : '',
              price: row['price'] is num
                  ? (row['price'] as num).toDouble()
                  : null),
  ];
}

List<ShoppingAffiliate> businessCoupangOffers(
        Iterable<ShoppingAffiliate> offers) =>
    offers.where((o) => o.program == 'coupang' && o.uri != null).toList();

Object? _canonical(Object? value) => switch (value) {
      Map map => {
          for (final key in map.keys.cast<String>().toList()..sort())
            key: _canonical(map[key])
        },
      List list => list.map(_canonical).toList(),
      _ => value
    };

BusinessRecord snapshotBusinessPurchase(BusinessRecord record) =>
    BusinessRecord(
        id: record.id,
        workspace: record.workspace,
        kind: record.kind,
        title: record.title,
        status: record.status,
        revision: record.revision,
        isTest: record.isTest,
        data: jsonDecode(jsonEncode(record.data)) as Map<String, dynamic>);

bool sameBusinessPurchase(BusinessRecord a, BusinessRecord b) =>
    a.id == b.id &&
    a.workspace == b.workspace &&
    a.kind == b.kind &&
    a.status == b.status &&
    a.revision == b.revision &&
    a.title == b.title &&
    jsonEncode(_canonical(a.data)) == jsonEncode(_canonical(b.data));

bool sameCoupangOffer(ShoppingAffiliate a, ShoppingAffiliate b) =>
    a.id == b.id &&
    a.program == b.program &&
    a.title == b.title &&
    a.specification == b.specification &&
    a.uri != null &&
    a.uri == b.uri &&
    CoupangPurchasePlan.offerFingerprint(a) ==
        CoupangPurchasePlan.offerFingerprint(b);
