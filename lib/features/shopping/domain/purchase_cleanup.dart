class PurchaseCleanupEntry {
  const PurchaseCleanupEntry(
      {required this.id,
      required this.title,
      required this.detail,
      required this.status,
      required this.token,
      required this.eligible,
      required this.archived,
      this.date,
      this.archivedAt});
  final String id, title, detail, status, token;
  final bool eligible, archived;
  final DateTime? date, archivedAt;
  factory PurchaseCleanupEntry.fromJson(Map<String, dynamic> j) =>
      PurchaseCleanupEntry(
          id: j['id'] as String,
          title: j['title'] as String,
          detail: j['detail'] as String,
          status: j['status'] as String,
          token: j['token'] as String,
          eligible: j['eligible'] == true,
          archived: j['archived'] == true,
          date: DateTime.tryParse(j['record_date']?.toString() ?? ''),
          archivedAt: DateTime.tryParse(j['archived_at']?.toString() ?? ''));
  Map<String, String> get target => {'id': id, 'token': token};
}

class PurchaseCleanupIndex {
  const PurchaseCleanupIndex(this.keys, {this.available = true});
  final Set<String> keys;
  final bool available;
  bool contains(String kind, String id) => keys.contains('$kind:$id');
  // A request that has advanced since this index was loaded must stay visible.
  bool hidesRequest(String kind, String id, String status) =>
      const {'draft', 'received', 'cancelled'}.contains(status) &&
      contains(kind, id);
}

class PurchaseCleanupUnavailable implements Exception {}
