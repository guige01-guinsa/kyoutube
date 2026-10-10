import '../../shopping/domain/supplier_request.dart';

class BusinessSupplier {
  const BusinessSupplier(
      {required this.id, required this.revision, required this.data});
  final String id;
  final int revision;
  final Map<String, dynamic> data;
  String get name => data['name'] as String;
  bool get active => data['active'] == true;
  factory BusinessSupplier.fromJson(Map<String, dynamic> j) => BusinessSupplier(
      id: j['id'] as String,
      revision: (j['revision'] as num).toInt(),
      data: Map<String, dynamic>.from(j['data'] as Map));
}

class BusinessSupplierProduct {
  const BusinessSupplierProduct(
      {required this.id,
      required this.supplierId,
      required this.revision,
      required this.data});
  final String id, supplierId;
  final int revision;
  final Map<String, dynamic> data;
  String get name => data['name'] as String;
  String get spec => data['spec'] as String;
  String get contentUnit => data['content_unit'] as String;
  String get packUnit => data['pack_unit'] as String;
  double get contentQuantity => (data['content_quantity'] as num).toDouble();
  bool get active => data['active'] == true;
  bool matchesUnit(String unit) =>
      active && contentUnit.trim().toLowerCase() == unit.trim().toLowerCase();
  factory BusinessSupplierProduct.fromJson(Map<String, dynamic> j) =>
      BusinessSupplierProduct(
          id: j['id'] as String,
          supplierId: j['supplier_id'] as String,
          revision: (j['revision'] as num).toInt(),
          data: Map<String, dynamic>.from(j['data'] as Map));
  Map<String, dynamic> selection(String key) =>
      {'key': key, 'id': id, 'revision': revision};
}

/// Only explicitly selected directory fields can cross into shared business data.
Map<String, dynamic> sharedSupplierCopy(
        ShoppingSupplier supplier, Set<String> fields) =>
    {
      'name': supplier.name,
      'contact': fields.contains('contact') ? supplier.contact : '',
      'phone': fields.contains('phone') ? supplier.phone : '',
      'address': fields.contains('address') ? supplier.address : '',
      'website': fields.contains('website') ? supplier.website : '',
      'active': true,
    };

List<BusinessSupplier> findBusinessSuppliers(
    Iterable<BusinessSupplier> rows, String query,
    {bool includeInactive = false}) {
  final term = query.trim().toLowerCase();
  return rows
      .where((s) =>
          (includeInactive || s.active) &&
          ['name', 'contact', 'phone', 'address', 'website'].any(
              (k) => (s.data[k] as String? ?? '').toLowerCase().contains(term)))
      .toList();
}
