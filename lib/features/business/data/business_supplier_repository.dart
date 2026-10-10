import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../auth/application/auth_providers.dart';
import '../domain/business_supplier.dart';
import '../domain/business_workspace.dart';
import '../domain/business_menu.dart';

typedef BusinessSupplierQuery = ({String workspace, String supplier});
typedef BusinessSupplierSnapshotQuery = ({String workspace, String request});

class BusinessSupplierRepository {
  BusinessSupplierRepository(this.client);
  final SupabaseClient client;
  Future<BusinessSupplier> supplier(String workspace, String id) async => BusinessSupplier.fromJson(
    await client.from('business_suppliers').select().eq('workspace_id', workspace).eq('id', id).single());
  Future<BusinessSupplierProduct> product(String workspace, String supplier, String id) async => BusinessSupplierProduct.fromJson(
    await client.from('business_supplier_products').select().eq('workspace_id', workspace).eq('supplier_id', supplier).eq('id', id).single());
  Future<List<BusinessSupplier>> suppliers(String workspace) async =>
      (await client
              .from('business_suppliers')
              .select()
              .eq('workspace_id', workspace)
              .order('data->>name')
              .order('id')
              .limit(300))
          .map(BusinessSupplier.fromJson)
          .toList();
  Future<List<BusinessSupplierProduct>> products(
          String workspace, String supplier) async =>
      (await client
              .from('business_supplier_products')
              .select()
              .eq('workspace_id', workspace)
              .eq('supplier_id', supplier)
              .order('data->>name')
              .order('id')
              .limit(1000))
          .map(BusinessSupplierProduct.fromJson)
          .toList();
  Future<void> saveSupplier(String workspace, String id, int revision,
      Map<String, dynamic> data) async {
    await client.rpc('business_supplier_save', params: {
      'p_workspace': workspace,
      'p_id': id,
      'p_revision': revision,
      'p_data': data
    });
  }

  Future<void> saveProduct(String workspace, String supplier, String id,
      int revision, Map<String, dynamic> data) async {
    await client.rpc('business_supplier_product_save', params: {
      'p_workspace': workspace,
      'p_supplier': supplier,
      'p_id': id,
      'p_revision': revision,
      'p_data': data
    });
  }

  Future<Map<String, dynamic>?> snapshot(
          String workspace, String request) async =>
      await client
          .from('business_purchase_supplier_snapshots')
          .select('supplier,products,created_at')
          .eq('workspace_id', workspace)
          .eq('request_id', request)
          .maybeSingle();
  Future<BusinessRecord> purchase(
          String workspace,
          String request,
          String purpose,
          List<MenuPurchaseSource> sources,
          List<MenuPurchaseAdjustment> adjustments,
          BusinessSupplier supplier,
          Map<String, BusinessSupplierProduct> products) async =>
      BusinessRecord.fromJson(Map<String, dynamic>.from(
          await client.rpc('business_supplier_purchase', params: {
        'p_workspace': workspace,
        'p_request': request,
        'p_purpose': purpose,
        'p_sources': sources.map((s) => s.toJson()).toList(),
        'p_adjustments': adjustments.map((a) => a.toJson()).toList(),
        'p_supplier': supplier.id,
        'p_supplier_revision': supplier.revision,
        'p_products': [
          for (final a in adjustments)
            if (a.include && products.containsKey(a.requirement['key']))
              products[a.requirement['key']]!
                  .selection(a.requirement['key'] as String)
        ],
      }) as Map));
}

final businessSupplierRepositoryProvider =
    Provider((ref) => BusinessSupplierRepository(Supabase.instance.client));
final businessSuppliersProvider = FutureProvider.autoDispose
    .family<List<BusinessSupplier>, String>((ref, workspace) {
  if (ref.watch(activeAccountIdProvider) == null) return <BusinessSupplier>[];
  return ref.watch(businessSupplierRepositoryProvider).suppliers(workspace);
});
final businessSupplierProductsProvider = FutureProvider.autoDispose
    .family<List<BusinessSupplierProduct>, BusinessSupplierQuery>((ref, q) {
  if (ref.watch(activeAccountIdProvider) == null) {
    return <BusinessSupplierProduct>[];
  }
  return ref
      .watch(businessSupplierRepositoryProvider)
      .products(q.workspace, q.supplier);
});
final businessSupplierSnapshotProvider = FutureProvider.autoDispose
    .family<Map<String, dynamic>?, BusinessSupplierSnapshotQuery>((ref, q) {
  if (ref.watch(activeAccountIdProvider) == null) return null;
  return ref
      .watch(businessSupplierRepositoryProvider)
      .snapshot(q.workspace, q.request);
});
