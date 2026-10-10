import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../domain/public_supplier.dart';

abstract class PublicSupplierAdminRepository {
  Future<List<PublicSupplier>> discover(String query);
  Future<List<PublicSupplier>> search(String query, String status,
      {int offset = 0});
  Future<PublicSupplier> save(PublicSupplier row, {required bool confirmed});
  Future<void> publish(List<PublicSupplier> rows);
}

final publicSupplierAdminRepositoryProvider =
    Provider<PublicSupplierAdminRepository>((ref) =>
        SupabasePublicSupplierAdminRepository(Supabase.instance.client));

class SupabasePublicSupplierAdminRepository
    implements PublicSupplierAdminRepository {
  SupabasePublicSupplierAdminRepository(this.client);
  final SupabaseClient client;
  @override
  Future<List<PublicSupplier>> discover(String query) async {
    final result = await client.functions
        .invoke('supplier_discovery', body: {'query': query});
    final candidates = (result.data['suppliers'] as List)
        .map((j) => PublicSupplier.fromJson(Map<String, dynamic>.from(j)))
        .toList();
    if (candidates.isEmpty) return candidates;
    final matches = (await client.rpc('admin_match_public_suppliers', params: {
      'p_websites': candidates.map((r) => r.website).toList()
    }) as List)
        .map((j) => PublicSupplier.fromJson(Map<String, dynamic>.from(j)))
        .toList();
    return matchPublicSupplierCandidates(candidates, matches);
  }

  @override
  Future<List<PublicSupplier>> search(String query, String status,
          {int offset = 0}) async =>
      (await client.rpc('admin_search_public_suppliers', params: {
        'p_query': query,
        'p_status': status,
        'p_offset': offset
      }) as List)
          .map((j) => PublicSupplier.fromJson(Map<String, dynamic>.from(j)))
          .toList();
  @override
  Future<PublicSupplier> save(PublicSupplier row,
          {required bool confirmed}) async =>
      PublicSupplier.fromJson(Map<String, dynamic>.from(await client
          .rpc('admin_save_public_supplier', params: {
        'p_data': row.toJson(),
        'p_revision': row.revision,
        'p_confirmed': confirmed
      })));
  @override
  Future<void> publish(List<PublicSupplier> rows) async {
    await client.rpc('admin_publish_public_suppliers', params: {
      'p_selected': rows
          .map((r) => {
                ...r.toJson(),
                'revision': r.revision,
                'checked_on': r.checkedOn.isEmpty
                    ? DateTime.now().toIso8601String().substring(0, 10)
                    : r.checkedOn
              })
          .toList(),
      'p_confirmed': true
    });
  }
}
