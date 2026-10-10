import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../auth/application/auth_providers.dart';
import '../domain/business_inventory.dart';

typedef StockItemQuery = ({String workspace, String item});
typedef ReceivingQuery = ({String workspace, String request});
typedef StockEventQuery = ({
  String workspace,
  String? item,
  String? request,
  int offset
});

class BusinessInventoryRepository {
  BusinessInventoryRepository(this.client);
  final SupabaseClient client;
  Future<void> saveNote(
      String workspace, BusinessStockItem item, String note) async {
    await client.rpc('business_stock_note', params: {
      'p_workspace': workspace,
      'p_id': item.id,
      'p_revision': item.managementRevision,
      'p_note': note,
    });
  }

  Future<List<BusinessStockItem>> items(String workspace) async =>
      (await client.rpc('business_stock_overview',
              params: {'p_workspace': workspace}) as List)
          .map((j) =>
              BusinessStockItem.fromJson(Map<String, dynamic>.from(j as Map)))
          .toList();
  Future<BusinessReceiving> receiving(String workspace, String request) async =>
      BusinessReceiving.fromJson(Map<String, dynamic>.from(await client.rpc(
          'business_receiving_overview',
          params: {'p_workspace': workspace, 'p_request': request}) as Map));
  Future<List<Map<String, dynamic>>> reservations(
          String workspace, String item) async =>
      await client
          .from('business_stock_reservations')
          .select()
          .eq('workspace_id', workspace)
          .eq('item_id', item)
          .gt('remaining', 0)
          .order('created_at')
          .order('id')
          .limit(1000);
  Future<List<Map<String, dynamic>>> events(StockEventQuery q) async =>
      (await client.rpc('business_stock_events_page', params: {
        'p_workspace': q.workspace,
        'p_item': q.item,
        'p_request': q.request,
        'p_offset': q.offset
      }) as List)
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList();
  Future<Map<String, dynamic>> action(String workspace, String id, String action,
      Map<String, dynamic> data) async {
    final result = await client.rpc('business_stock_action', params: {
      'p_workspace': workspace,
      'p_id': id,
      'p_action': action,
      'p_data': data
    });
    return Map<String, dynamic>.from(result as Map);
  }

  Future<List<Map<String, dynamic>>> hints(
          String workspace, List<Map<String, dynamic>> requirements) async =>
      (await client.rpc('business_stock_purchase_hints', params: {
        'p_workspace': workspace,
        'p_requirements': requirements
      }) as List)
          .map((j) => Map<String, dynamic>.from(j as Map))
          .toList();
}

final businessInventoryRepositoryProvider =
    Provider((ref) => BusinessInventoryRepository(Supabase.instance.client));
final businessStockItemsProvider = FutureProvider.autoDispose
    .family<List<BusinessStockItem>, String>((ref, workspace) {
  if (ref.watch(activeAccountIdProvider) == null) return <BusinessStockItem>[];
  return ref.watch(businessInventoryRepositoryProvider).items(workspace);
});
final businessReceivingProvider = FutureProvider.autoDispose
    .family<BusinessReceiving, ReceivingQuery>((ref, q) {
  if (ref.watch(activeAccountIdProvider) == null) {
    throw StateError('BUSINESS_AUTH');
  }
  return ref
      .watch(businessInventoryRepositoryProvider)
      .receiving(q.workspace, q.request);
});
final businessReservationsProvider = FutureProvider.autoDispose
    .family<List<Map<String, dynamic>>, StockItemQuery>((ref, q) {
  if (ref.watch(activeAccountIdProvider) == null) {
    return <Map<String, dynamic>>[];
  }
  return ref
      .watch(businessInventoryRepositoryProvider)
      .reservations(q.workspace, q.item);
});
final businessStockEventsProvider = FutureProvider.autoDispose
    .family<List<Map<String, dynamic>>, StockEventQuery>((ref, q) {
  if (ref.watch(activeAccountIdProvider) == null) {
    return <Map<String, dynamic>>[];
  }
  return ref.watch(businessInventoryRepositoryProvider).events(q);
});
