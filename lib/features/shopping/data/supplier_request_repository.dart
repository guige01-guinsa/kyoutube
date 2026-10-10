import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../auth/application/auth_providers.dart';
import '../domain/shopping_assistant.dart';
import '../domain/supplier_request.dart';
import 'business_document_store.dart';

abstract class SupplierRequestRepository {
  Future<List<ShoppingSupplier>> suppliers();
  Future<void> saveSupplier(ShoppingSupplier supplier,
      {required bool existing});
  Future<void> deleteSupplier(String id);
  Future<List<SupplierRequest>> requests({int limit = 50});
  Future<SupplierRequest?> request(String id);
  Future<SupplierRequest> save(SupplierRequest request, {String? status});
  Future<void> deleteRequest(String id);
  Future<void> deleteDraft(SupplierRequest request) =>
      throw UnsupportedError('Safe draft deletion is unavailable');
}

final supplierRequestRepositoryProvider = Provider<SupplierRequestRepository>(
    (_) => SupabaseSupplierRequestRepository(Supabase.instance.client));
final shoppingSuppliersProvider = FutureProvider.autoDispose((ref) async {
  if (ref.watch(activeAccountIdProvider) == null) return <ShoppingSupplier>[];
  return shoppingSupplierDirectory(
      await ref.watch(supplierRequestRepositoryProvider).suppliers());
});
final supplierRequestsProvider = FutureProvider.autoDispose((ref) async {
  if (ref.watch(activeAccountIdProvider) == null) return <SupplierRequest>[];
  return ref
      .watch(supplierRequestRepositoryProvider)
      .requests(limit: ref.watch(supplierRequestLimitProvider));
});
final supplierRequestLimitProvider = StateProvider.autoDispose<int>((ref) {
  ref.watch(activeAccountIdProvider);
  return 50;
});

class SupabaseSupplierRequestRepository implements SupplierRequestRepository {
  SupabaseSupplierRequestRepository(this.client);
  final SupabaseClient client;
  String get owner =>
      client.auth.currentUser?.id ?? (throw StateError('Sign in required'));
  @override
  Future<List<ShoppingSupplier>> suppliers() async => (await client
          .from('shopping_suppliers')
          .select()
          .eq('owner_id', owner)
          .order('name')
          .limit(200))
      .map(ShoppingSupplier.fromJson)
      .toList();
  @override
  Future<void> saveSupplier(ShoppingSupplier supplier,
      {required bool existing}) async {
    if (supplier.website.isNotEmpty &&
        shoppingProductUri(supplier.website) == null) {
      throw const FormatException('Invalid store link');
    }
    final data = supplier.toJson()..remove('id');
    if (existing) {
      final result = await client
          .from('shopping_suppliers')
          .update(data)
          .eq('owner_id', owner)
          .eq('id', supplier.id)
          .select('id');
      if (result.length != 1) throw StateError('Supplier unavailable');
    } else {
      // Explicit id makes a retry safe without overwriting another supplier.
      await client.from('shopping_suppliers').upsert(
          {...data, 'id': supplier.id, 'owner_id': owner},
          ignoreDuplicates: true);
    }
  }

  @override
  Future<void> deleteSupplier(String id) async {
    throw UnsupportedError('Use reversible supplier archive');
  }

  @override
  Future<List<SupplierRequest>> requests({int limit = 50}) async =>
      (await client
              .from('supplier_purchase_requests')
              .select()
              .eq('owner_id', owner)
              .order('created_at', ascending: false)
              .limit(limit.clamp(1, 1000)))
          .map(SupplierRequest.fromJson)
          .toList();
  @override
  Future<SupplierRequest?> request(String id) async {
    final account = owner;
    final row = await client
        .from('supplier_purchase_requests')
        .select()
        .eq('owner_id', account)
        .eq('id', id)
        .maybeSingle();
    if (owner != account) throw StateError('Account changed');
    return row == null ? null : SupplierRequest.fromJson(row);
  }

  @override
  Future<SupplierRequest> save(SupplierRequest request,
          {String? status}) async =>
      SupplierRequest.fromJson(Map<String, dynamic>.from(
          await client.rpc('save_supplier_purchase_request', params: {
        'p_id': request.id,
        'p_revision': request.revision,
        'p_data': request.data,
        'p_status': status ?? request.status
      })));
  @override
  Future<void> deleteRequest(String id) async {
    final current = await request(id);
    if (current == null) throw StateError('MANAGEMENT_STALE');
    await deleteDraft(current);
  }

  @override
  Future<void> deleteDraft(SupplierRequest draft) async {
    final user = owner;
    final result = await client.rpc('delete_unused_purchase_draft', params: {
      'p_id': draft.id,
      'p_revision': draft.revision,
    });
    if (owner != user) return;
    final store = SupabaseBusinessDocumentStore(client);
    for (final row in [
      if (result != null) Map<String, dynamic>.from(result as Map)
    ]) {
      final request = SupplierRequest.fromJson(row);
      for (final path in {
        request.buyerBusiness.imagePath,
        request.supplierBusiness.imagePath
      }.where((p) => p.isNotEmpty)) {
        // A shared certificate remains protected by reference-checking Storage RLS.
        try {
          await store.discard(path);
        } catch (_) {/* Account cleanup retries abandoned files. */}
      }
    }
  }
}
