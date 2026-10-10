import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class OwnerRecordManagementRepository {
  OwnerRecordManagementRepository(this.client);
  final SupabaseClient client;
  Future<List<Map<String, dynamic>>> stockRecovery(String workspace, String id, String unit) async =>
    (await client.rpc('owner_stock_recovery', params: {'p_workspace': workspace, 'p_id': id, 'p_target_unit': unit}) as List)
      .map((r) => Map<String, dynamic>.from(r as Map)).toList();
  Future<Map<String, dynamic>> preview(String kind, String id,
          {String? workspace, Map<String, dynamic> change = const {}}) async =>
      Map<String, dynamic>.from(
          await client.rpc('owner_record_manage', params: {
        'p_kind': kind,
        'p_id': id,
        'p_workspace': workspace,
        'p_change': change,
      }) as Map);
  Future<Map<String, dynamic>> apply(Map<String, dynamic> preview) async {
    if (preview['token'] is! String || (preview['token'] as String).isEmpty) {
      throw StateError('MANAGEMENT_STALE');
    }
    final result = Map<String, dynamic>.from(
        await client.rpc('owner_record_manage', params: {
      'p_kind': preview['kind'],
      'p_id': preview['id'],
      'p_workspace': preview['workspace'],
      'p_change': preview['change'],
      'p_token': preview['token'],
    }) as Map);
    if (result['applied'] != true) throw StateError('MANAGEMENT_STALE');
    return result;
  }
}

final ownerRecordManagementRepositoryProvider = Provider(
    (ref) => OwnerRecordManagementRepository(Supabase.instance.client));

/// Only dimensionally defined conversions are suggested. Packs/counts need confirmation.
double? suggestedStockConversion(String from, String to) {
  const units = {
    'g': ('mass', 1.0),
    'kg': ('mass', 1000.0),
    'ml': ('volume', 1.0),
    'l': ('volume', 1000.0)
  };
  final a = units[from.trim().toLowerCase()],
      b = units[to.trim().toLowerCase()];
  return a == null || b == null || a.$1 != b.$1 ? null : a.$2 / b.$2;
}
