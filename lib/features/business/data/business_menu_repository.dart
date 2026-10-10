import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../auth/application/auth_providers.dart';
import '../domain/business_menu.dart';
import '../domain/business_workspace.dart';

class BusinessMenuRepository {
  BusinessMenuRepository(this.client);
  final SupabaseClient client;
  Future<Map<String, dynamic>> revisions(String workspace) async =>
      Map<String, dynamic>.from(await client.rpc('business_menu_revisions',
          params: {'p_workspace': workspace}) as Map);
  Future<List<BusinessMenuItem>> menus(String workspace) async => (await client
          .from('business_menu_items')
          .select()
          .eq('workspace_id', workspace)
          .order('category')
          .order('name')
          .order('id')
          .limit(300))
      .map(BusinessMenuItem.fromJson)
      .toList();
  Future<List<Map<String, dynamic>>> reviews(
          String workspace, String recipe) async =>
      List<Map<String, dynamic>>.from(await client
          .from('business_recipe_reviews')
          .select()
          .eq('workspace_id', workspace)
          .eq('recipe_id', recipe)
          .order('id', ascending: false)
          .limit(300));
  Future<List<Map<String, dynamic>>> history(
          String workspace, String menu) async =>
      List<Map<String, dynamic>>.from(await client
          .from('business_menu_history')
          .select()
          .eq('workspace_id', workspace)
          .eq('menu_id', menu)
          .order('revision', ascending: false)
          .limit(50));
  Future<Map<String, dynamic>?> basis(String workspace, String request) async =>
      await client
          .from('business_purchase_bases')
          .select('purpose,sources,requirements,adjustments,created_at')
          .eq('workspace_id', workspace)
          .eq('request_id', request)
          .maybeSingle();
  Future<Map<String, dynamic>> review(BusinessRecord recipe, int expected,
          String stage, String note) async =>
      Map<String, dynamic>.from(
          await client.rpc('business_recipe_review', params: {
        'p_workspace': recipe.workspace,
        'p_recipe': recipe.id,
        'p_revision': recipe.revision,
        'p_expected': expected,
        'p_stage': stage,
        'p_note': note
      }) as Map);
  Future<BusinessMenuItem> save(String workspace, String id, int revision,
          Map<String, dynamic> data) async =>
      BusinessMenuItem.fromJson(Map<String, dynamic>.from(await client
          .rpc('business_menu_save', params: {
        'p_workspace': workspace,
        'p_id': id,
        'p_revision': revision,
        'p_data': data
      }) as Map));
  Future<Map<String, dynamic>> plan(String workspace, String purpose,
          List<MenuPurchaseSource> sources) async =>
      Map<String, dynamic>.from(await client.rpc('business_menu_plan', params: {
        'p_workspace': workspace,
        'p_purpose': purpose,
        'p_sources': sources.map((s) => s.toJson()).toList()
      }) as Map);
  Future<BusinessRecord> purchase(
          String workspace,
          String request,
          String purpose,
          List<MenuPurchaseSource> sources,
          List<MenuPurchaseAdjustment> adjustments,
          String supplier) async =>
      BusinessRecord.fromJson(Map<String, dynamic>.from(
          await client.rpc('business_menu_purchase', params: {
        'p_workspace': workspace,
        'p_request': request,
        'p_purpose': purpose,
        'p_sources': sources.map((s) => s.toJson()).toList(),
        'p_adjustments': adjustments.map((a) => a.toJson()).toList(),
        'p_supplier': supplier
      }) as Map));
}

final businessMenuRepositoryProvider =
    Provider((ref) => BusinessMenuRepository(Supabase.instance.client));
final businessMenusProvider = FutureProvider.autoDispose
    .family<List<BusinessMenuItem>, String>((ref, workspace) {
  if (ref.watch(activeAccountIdProvider) == null) return <BusinessMenuItem>[];
  return ref.watch(businessMenuRepositoryProvider).menus(workspace);
});
typedef BusinessMenuRecordQuery = ({String workspace, String id});
final businessRecipeReviewsProvider = FutureProvider.autoDispose
    .family<List<Map<String, dynamic>>, BusinessMenuRecordQuery>((ref, q) {
  if (ref.watch(activeAccountIdProvider) == null) {
    return <Map<String, dynamic>>[];
  }
  return ref.watch(businessMenuRepositoryProvider).reviews(q.workspace, q.id);
});
final businessPurchaseBasisProvider = FutureProvider.autoDispose
    .family<Map<String, dynamic>?, BusinessMenuRecordQuery>((ref, q) {
  if (ref.watch(activeAccountIdProvider) == null) return null;
  return ref.watch(businessMenuRepositoryProvider).basis(q.workspace, q.id);
});

final businessMenuRevisionsProvider = FutureProvider.autoDispose
    .family<Map<String, dynamic>, String>((ref, workspace) {
  ref.watch(activeAccountIdProvider);
  return Future.sync(
      () => ref.watch(businessMenuRepositoryProvider).revisions(workspace));
});
