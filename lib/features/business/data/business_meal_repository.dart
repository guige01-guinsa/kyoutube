import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../auth/application/auth_providers.dart';
import '../domain/business_meal.dart';

class BusinessMealRepository {
  BusinessMealRepository(this.client);
  final SupabaseClient client;
  Future<List<BusinessMeal>> list(
      String workspace, DateTime start, DateTime end) async {
    final result = <BusinessMeal>[];
    for (var offset = 0;; offset += 200) {
      final rows = await client
          .from('business_meal_plans')
          .select()
          .eq('workspace_id', workspace)
          .gte('meal_date', mealDate(start))
          .lte('meal_date', mealDate(end))
          .order('meal_date')
          .order('slot')
          .order('id')
          .range(offset, offset + 199);
      result.addAll(rows.map(BusinessMeal.new));
      if (rows.length < 200) return result;
    }
  }

  Future<void> save(Map<String, dynamic> payload) async {
    await client.rpc('business_meal_save', params: payload);
  }

  Future<void> transition(
      String workspace, BusinessMeal meal, String status) async {
    await client.rpc('business_meal_transition', params: {
      'p_workspace': workspace,
      'p_id': meal.id,
      'p_revision': meal.revision,
      'p_status': status
    });
  }

  Future<void> copy(Map<String, dynamic> payload) async {
    await client.rpc('business_meal_copy', params: payload);
  }

  Future<List<Map<String, dynamic>>> history(
          String workspace, String id) async =>
      List<Map<String, dynamic>>.from(await client
          .from('business_meal_history')
          .select()
          .eq('workspace_id', workspace)
          .eq('meal_id', id)
          .order('revision', ascending: false));
  Future<List<Map<String, dynamic>>> links(String workspace) async {
    final result = <Map<String, dynamic>>[];
    for (var offset = 0;; offset += 200) {
      final rows = await client
          .from('business_meal_purchase_links')
          .select('meal_id,batch_id')
          .eq('workspace_id', workspace)
          .order('meal_id')
          .range(offset, offset + 199);
      result.addAll(rows);
      if (rows.length < 200) return result;
    }
  }

  Future<List<Map<String, dynamic>>> recipes(
          String workspace, String query, int offset) async =>
      List<Map<String, dynamic>>.from(await client
          .from('business_records')
          .select('id,title,revision,data')
          .eq('workspace_id', workspace)
          .eq('kind', 'recipe')
          .eq('status', 'draft')
          .ilike('title', '%${query.replaceAll('%', '').replaceAll('_', '')}%')
          .order('title')
          .order('id')
          .range(offset, offset + 49));
}

final businessMealRepositoryProvider = Provider((ref) {
  ref.watch(activeAccountIdProvider);
  return BusinessMealRepository(Supabase.instance.client);
});
final businessMealsProvider = FutureProvider.autoDispose.family<
    List<BusinessMeal>,
    ({String workspace, DateTime start, DateTime end})>((ref, p) {
  if (ref.watch(activeAccountIdProvider) == null) return <BusinessMeal>[];
  return ref
      .watch(businessMealRepositoryProvider)
      .list(p.workspace, p.start, p.end);
});
final businessMealLinksProvider = FutureProvider.autoDispose
    .family<List<Map<String, dynamic>>, String>((ref, w) {
  if (ref.watch(activeAccountIdProvider) == null) {
    return <Map<String, dynamic>>[];
  }
  return ref.watch(businessMealRepositoryProvider).links(w);
});
