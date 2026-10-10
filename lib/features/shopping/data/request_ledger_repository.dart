import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../domain/purchase_request_ledger.dart';
import '../domain/supplier_request.dart';

abstract class RequestLedgerRepository {
  Future<RequestLedgerPageData> search(RequestLedgerFilter filter,
      {int offset = 0, int limit = 50});
  Future<SupplierRequest> request(String id);
  Future<List<Map<String, dynamic>>> events(String id);
}

final requestLedgerRepositoryProvider = Provider<RequestLedgerRepository>(
    (_) => SupabaseRequestLedgerRepository(Supabase.instance.client));

class SupabaseRequestLedgerRepository implements RequestLedgerRepository {
  SupabaseRequestLedgerRepository(this.client);
  final SupabaseClient client;
  String get owner =>
      client.auth.currentUser?.id ?? (throw StateError('Sign in required'));
  @override
  Future<RequestLedgerPageData> search(RequestLedgerFilter filter,
      {int offset = 0, int limit = 50}) async {
    final user = owner;
    final result = await client.rpc('search_purchase_request_ledger',
        params: filter.params(offset: offset, limit: limit));
    if (owner != user) throw StateError('Account changed');
    return RequestLedgerPageData.fromJson(Map<String, dynamic>.from(result));
  }

  @override
  Future<SupplierRequest> request(String id) async {
    final user = owner;
    final result = await client
        .from('supplier_purchase_requests')
        .select()
        .eq('owner_id', user)
        .eq('id', id)
        .single();
    if (owner != user) throw StateError('Account changed');
    return SupplierRequest.fromJson(result);
  }

  @override
  Future<List<Map<String, dynamic>>> events(String id) async {
    final user = owner;
    final result = await client
        .from('supplier_request_events')
        .select('event,from_status,to_status,revision,recorded_at')
        .eq('owner_id', user)
        .eq('request_id', id)
        .order('id', ascending: false)
        .limit(200);
    if (owner != user) throw StateError('Account changed');
    return result;
  }
}
