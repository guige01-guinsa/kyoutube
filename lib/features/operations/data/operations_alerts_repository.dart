import '../../auth/application/auth_providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

abstract class OpsAlertsRepository {
  Future<Map<String, dynamic>> inbox(int? before);
  Future<void> markRead(int id);
  Future<void> setDatabaseBudget(int bytes);
}

final opsAlertsRepositoryProvider = Provider<OpsAlertsRepository>(
    (ref) => SupabaseOpsAlertsRepository(Supabase.instance.client));
final opsInboxProvider = FutureProvider.autoDispose
    .family<Map<String, dynamic>, int?>((ref, before) {
  ref.watch(activeAccountIdProvider);
  return ref.watch(opsAlertsRepositoryProvider).inbox(before);
});

class SupabaseOpsAlertsRepository implements OpsAlertsRepository {
  SupabaseOpsAlertsRepository(this.client);
  final SupabaseClient client;
  @override
  Future<Map<String, dynamic>> inbox(int? before) async =>
      Map<String, dynamic>.from(await client.rpc('admin_ops_inbox',
              params: {'p_before': before}).timeout(const Duration(seconds: 15))
          as Map);
  @override
  Future<void> markRead(int id) async {
    await client.rpc('admin_read_ops_alert', params: {'p_id': id});
  }

  @override
  Future<void> setDatabaseBudget(int bytes) async {
    await client
        .rpc('admin_set_ops_database_budget', params: {'p_bytes': bytes});
  }
}
