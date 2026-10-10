import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../domain/chef_sales.dart';

abstract class ChefSalesRepository {
  Future<ChefSalesTotals> totals(ChefSalesRange range, String currency,
      {String? recipeId});
  Future<List<ChefSale>> list(ChefSalesRange range, String currency,
      {String? recipeId, int? beforeId});
  Future<void> record(String recipeId, int revision, DateTime date,
      int quantity, String requestKey);
  Future<void> update(int id, DateTime date, int quantity);
  Future<void> remove(int id);
  Future<void> correct(
          ChefSale sale, DateTime date, int quantity, String reason) =>
      throw UnsupportedError('Safe correction unavailable');
  Future<void> setVoided(ChefSale sale, bool voided, String reason) =>
      throw UnsupportedError('Safe correction unavailable');
  Future<List<ChefSale>> voidedSales(ChefSalesRange range, String currency,
          {String? recipeId, int? beforeId}) =>
      throw UnsupportedError('Unavailable');
  Future<List<Map<String, dynamic>>> history(int id) =>
      throw UnsupportedError('Unavailable');
}

final chefSalesRepositoryProvider = Provider<ChefSalesRepository>(
    (ref) => SupabaseChefSalesRepository(Supabase.instance.client));

class SupabaseChefSalesRepository implements ChefSalesRepository {
  SupabaseChefSalesRepository(this.client);
  final SupabaseClient client;
  @override
  Future<ChefSalesTotals> totals(ChefSalesRange range, String currency,
      {String? recipeId}) async {
    final data = await client.rpc('chef_sales_totals', params: {
      'p_from': chefDate(range.from),
      'p_until': chefDate(range.until),
      'p_currency': currency,
      'p_recipe_id': recipeId
    });
    return ChefSalesTotals.fromJson(Map<String, dynamic>.from(data as Map));
  }

  @override
  Future<List<ChefSale>> list(ChefSalesRange range, String currency,
      {String? recipeId, int? beforeId}) async {
    var query = client
        .from('chef_sales')
        .select(
            'id,sale_date,recipe_title,quantity,unit_price,unit_cost,currency,revision,voided')
        .eq('currency', currency)
        .gte('sale_date', chefDate(range.from))
        .lt('sale_date', chefDate(range.until));
    if (recipeId != null) query = query.eq('recipe_id', recipeId);
    if (beforeId != null) query = query.lt('id', beforeId);
    final rows = await query.order('id', ascending: false).limit(50);
    return rows.map(ChefSale.fromJson).toList();
  }

  @override
  Future<void> record(String recipeId, int revision, DateTime date,
      int quantity, String requestKey) async {
    await client.rpc('record_chef_sale', params: {
      'p_recipe_id': recipeId,
      'p_expected_revision': revision,
      'p_sale_date': chefDate(date),
      'p_quantity': quantity,
      'p_request_key': requestKey
    });
  }

  @override
  Future<void> update(int id, DateTime date, int quantity) async {
    throw UnsupportedError('Use a revision and correction reason');
  }

  @override
  Future<void> remove(int id) async {
    throw UnsupportedError('Use reversible voiding');
  }

  @override
  Future<void> correct(
      ChefSale sale, DateTime date, int quantity, String reason) async {
    await client.rpc('chef_sale_manage', params: {
      'p_id': sale.id,
      'p_revision': sale.revision,
      'p_action': 'correct',
      'p_reason': reason,
      'p_date': chefDate(date),
      'p_quantity': quantity,
    });
  }

  @override
  Future<void> setVoided(ChefSale sale, bool voided, String reason) async {
    await client.rpc('chef_sale_manage', params: {
      'p_id': sale.id,
      'p_revision': sale.revision,
      'p_action': voided ? 'void' : 'restore',
      'p_reason': reason,
    });
  }

  @override
  Future<List<ChefSale>> voidedSales(ChefSalesRange range, String currency,
          {String? recipeId, int? beforeId}) async =>
      (await client.rpc('chef_voided_sales', params: {
        'p_from': chefDate(range.from),
        'p_until': chefDate(range.until),
        'p_currency': currency,
        'p_recipe': recipeId,
        'p_before': beforeId,
      }) as List)
          .map((r) => ChefSale.fromJson(Map<String, dynamic>.from(r as Map)))
          .toList();
  @override
  Future<List<Map<String, dynamic>>> history(int id) async => await client
      .from('chef_sale_events')
      .select('action,reason,before_data,after_data,recorded_at')
      .eq('sale_id', id)
      .order('id', ascending: false)
      .limit(100);
}
