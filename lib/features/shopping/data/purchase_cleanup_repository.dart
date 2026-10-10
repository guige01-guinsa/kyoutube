import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../auth/application/auth_providers.dart';
import '../domain/purchase_cleanup.dart';

abstract class PurchaseCleanupRepository {
  Future<PurchaseCleanupIndex> index(String? workspace);
  Future<List<PurchaseCleanupEntry>> list(
      {String? workspace,
      required String kind,
      required bool archived,
      DateTime? before,
      String query = '',
      int offset = 0});
  Future<int> apply(
      {String? workspace,
      required String kind,
      required List<PurchaseCleanupEntry> entries,
      required bool archive});
}

final purchaseCleanupRepositoryProvider = Provider<PurchaseCleanupRepository>(
    (_) => SupabasePurchaseCleanupRepository(Supabase.instance.client));
final purchaseCleanupIndexProvider = FutureProvider.autoDispose
    .family<PurchaseCleanupIndex, String?>((ref, workspace) async {
  if (ref.watch(activeAccountIdProvider) == null) {
    return const PurchaseCleanupIndex({});
  }
  return ref.watch(purchaseCleanupRepositoryProvider).index(workspace);
});

class SupabasePurchaseCleanupRepository implements PurchaseCleanupRepository {
  SupabasePurchaseCleanupRepository(this.client);
  final SupabaseClient client;
  Future<dynamic> _rpc(String name, Map<String, dynamic> args) async {
    try {
      return await client.rpc(name, params: args);
    } on PostgrestException catch (e) {
      if (e.code == 'PGRST202' || e.code == '42883') {
        throw PurchaseCleanupUnavailable();
      }
      rethrow;
    }
  }

  @override
  Future<PurchaseCleanupIndex> index(String? workspace) async {
    try {
      final rows =
          await _rpc('shopping_cleanup_index', {'p_workspace': workspace})
              as List;
      return PurchaseCleanupIndex(
          rows.map((r) => "${r['kind']}:${r['id']}").toSet());
    } on PurchaseCleanupUnavailable {
      // Until the additive server migration is deployed, ordinary shopping stays usable.
      return const PurchaseCleanupIndex({}, available: false);
    }
  }

  @override
  Future<List<PurchaseCleanupEntry>> list(
      {String? workspace,
      required String kind,
      required bool archived,
      DateTime? before,
      String query = '',
      int offset = 0}) async {
    final rows = await _rpc('shopping_cleanup_list', {
      'p_workspace': workspace,
      'p_kind': kind,
      'p_archived': archived,
      'p_before': before?.toUtc().toIso8601String(),
      'p_query': query.trim(),
      'p_offset': offset
    }) as List;
    return rows
        .map((r) => PurchaseCleanupEntry.fromJson(Map<String, dynamic>.from(r)))
        .toList();
  }

  @override
  Future<int> apply(
          {String? workspace,
          required String kind,
          required List<PurchaseCleanupEntry> entries,
          required bool archive}) async =>
      (await _rpc('shopping_cleanup_apply', {
        'p_workspace': workspace,
        'p_kind': kind,
        'p_targets': entries.map((e) => e.target).toList(),
        'p_archive': archive
      })) as int;
}
