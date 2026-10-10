import '../../shopping/domain/supplier_request.dart';

const businessPermissions = [
  'recipes.read',
  'recipes.write',
  'purchasing.read',
  'purchasing.write',
  'finance.read',
  'finance.write',
  'purchases.approve',
  'menus.approve'
];
const businessRolePermissions = <String, Set<String>>{
  'purchasing': {'recipes.read', 'purchasing.read', 'purchasing.write'},
  'culinary': {'recipes.read', 'recipes.write', 'purchasing.read'},
  'management': {
    'recipes.read',
    'purchasing.read',
    'finance.read',
    'finance.write',
    'purchases.approve',
    'menus.approve'
  },
};
String businessPermission(String kind, {bool write = false}) =>
    '${switch (kind) {
      'recipe' || 'meal' => 'recipes',
      'purchase' => 'purchasing',
      'cost' || 'sale' => 'finance',
      _ => 'invalid'
    }}.${write ? 'write' : 'read'}';

class BusinessContext {
  const BusinessContext(
      {required this.id,
      required this.name,
      required this.owner,
      required this.paid,
      required this.approval,
      this.isTest = false,
      required this.permissions});
  final String id, name;
  final bool owner, paid, approval, isTest;
  final Set<String> permissions;
  bool can(String permission) =>
      businessPermissions.contains(permission) &&
      (owner || permissions.contains(permission)) &&
      (paid ||
          (!permission.endsWith('.write') &&
              !permission.startsWith('finance.') &&
              permission != 'purchases.approve' &&
              permission != 'menus.approve'));
  factory BusinessContext.fromJson(Map<String, dynamic> j) => BusinessContext(
      id: j['id'] as String,
      name: j['name'] as String,
      owner: j['owner'] == true,
      paid: j['paid'] == true,
      approval: j['require_approval'] == true,
      isTest: j['is_test'] == true,
      permissions: Set<String>.from(j['permissions'] as List));
}

class BusinessRecord {
  const BusinessRecord(
      {required this.id,
      required this.workspace,
      required this.kind,
      required this.title,
      required this.data,
      this.status = 'draft',
      this.revision = 0,
      this.isTest = false,
      this.updatedAt});
  final String id, workspace, kind, title, status;
  final Map<String, dynamic> data;
  final int revision;
  final bool isTest;
  final DateTime? updatedAt;
  factory BusinessRecord.fromJson(Map<String, dynamic> j) => BusinessRecord(
      id: j['id'] as String,
      workspace: j['workspace_id'] as String,
      kind: j['kind'] as String,
      title: j['title'] as String,
      data: Map<String, dynamic>.from(j['data'] as Map),
      status: j['status'] as String,
      revision: (j['revision'] as num).toInt(),
      isTest: j['is_test'] == true,
      updatedAt: DateTime.tryParse(j['updated_at'] as String? ?? ''));
  SupplierRequest asPurchase({required bool english}) => SupplierRequest(
      id: id,
      supplier:
          ShoppingSupplier(id: id, name: data['supplier'] as String? ?? ''),
      buyer: data['buyer'] as String? ?? '',
      phone: data['phone'] as String? ?? '',
      address: data['address'] as String? ?? '',
      deliveryDate: data['delivery_date'] as String? ?? '',
      currency: data['currency'] as String? ?? 'KRW',
      notes:
          '${status == 'draft' || status == 'review' ? (english ? 'DRAFT FOR REVIEW — purchase not approved.\n' : '검토용 초안 — 구매 승인 전입니다.\n') : ''}${data['notes'] ?? ''}',
      lines: (data['lines'] as List)
          .map((v) =>
              SupplierRequestLine.fromJson(Map<String, dynamic>.from(v as Map)))
          .toList());
}

List<String> businessNextStatuses(
    BusinessContext context, BusinessRecord record) {
  if (record.kind != 'purchase') return [];
  final write = context.can('purchasing.write'),
      approve = context.can('purchases.approve');
  return [
    if (record.status == 'draft' && write)
      context.approval ? 'review' : 'approved',
    if (record.status == 'review' && approve) 'approved',
    if ((record.status == 'review' || record.status == 'approved') &&
        (write || approve))
      'draft',
    if (record.status == 'approved' && write) 'sent',
    if (['draft', 'review', 'approved', 'sent'].contains(record.status) &&
        (write || approve))
      'cancelled',
  ];
}
