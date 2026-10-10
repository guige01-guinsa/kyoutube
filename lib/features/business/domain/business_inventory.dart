class BusinessStockItem {
  const BusinessStockItem(
      {required this.id,
      required this.name,
      required this.spec,
      required this.unit,
      this.onHand = 0,
      this.reserved = 0,
      this.note = '',
      this.managementRevision = 1,
      this.available = 0});
  final String note;
  final int managementRevision;
  final String id, name, spec, unit;
  final double onHand, reserved, available;
  factory BusinessStockItem.fromJson(Map<String, dynamic> j) =>
      BusinessStockItem(
          id: j['id'] as String,
          name: j['name'] as String,
          spec: j['spec'] as String,
          unit: j['unit'] as String,
          note: j['management_note'] as String? ?? '',
          managementRevision: (j['management_revision'] as num? ?? 1).toInt(),
          onHand: (j['on_hand'] as num? ?? 0).toDouble(),
          reserved: (j['reserved'] as num? ?? 0).toDouble(),
          available: (j['available'] as num? ?? 0).toDouble());
  String get label => [name, if (spec.isNotEmpty) spec, unit].join(' · ');
}

/// Accepts bounded decimal quantities without silently rounding inventory.
bool stockQuantityValid(double? n, {bool signed = false}) =>
    n != null &&
    n.isFinite &&
    n.abs() <= 1e9 &&
    n.abs() >= 0.000001 &&
    (signed || n > 0) &&
    (n * 1e6 - (n * 1e6).round()).abs() < 0.000001;

List<BusinessStockItem> findStockItems(
    List<BusinessStockItem> items, String query) {
  final terms = query.trim().toLowerCase().split(RegExp(r'\s+'));
  return items
      .where((i) =>
          terms.every((t) => '${i.label} ${i.note}'.toLowerCase().contains(t)))
      .toList();
}

class BusinessReceiving {
  const BusinessReceiving(
      {required this.request,
      required this.revision,
      required this.status,
      required this.lines,
      this.closure,
      this.legacy = false,
      this.title = ''});
  final String request, status, title;
  final int revision;
  final List<Map<String, dynamic>> lines;
  final Map<String, dynamic>? closure;
  final bool legacy;
  bool get hasShortage => lines.any((l) => (l['outstanding'] as num? ?? 0) > 0);
  factory BusinessReceiving.fromJson(Map<String, dynamic> j) =>
      BusinessReceiving(
          request: j['request_id'] as String,
          title: j['title'] as String? ?? '',
          revision: (j['revision'] as num).toInt(),
          status: j['status'] as String,
          lines: (j['lines'] as List)
              .map((l) => Map<String, dynamic>.from(l as Map))
              .toList(),
          closure: j['closure'] == null
              ? null
              : Map<String, dynamic>.from(j['closure'] as Map),
          legacy: j['legacy'] == true);
}
