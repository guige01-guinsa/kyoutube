import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../auth/application/auth_providers.dart';
import '../domain/shopping_affiliate.dart';

class ShoppingAffiliateRepository {
  ShoppingAffiliateRepository(this.client);
  final SupabaseClient client;
  Future<List<PurchaseNameSuggestion>> searchNames(String query, int offset,
      {String? workspace}) async {
    final rows = await client.rpc('search_purchase_names', params: {
      'p_query': query,
      'p_surface': kIsWeb ? 'web' : 'mobile',
      'p_offset': offset,
      'p_workspace': workspace,
    }) as List;
    return rows
        .map((r) => PurchaseNameSuggestion(
            r['name'] as String, r['example_title'] as String))
        .toList();
  }

  Future<List<ShoppingAffiliate>> find(String ingredient) =>
      _findForSurface(ingredient);

  Future<List<ShoppingAffiliate>> findForSurface(
          String ingredient, String surface) =>
      _findForSurface(ingredient, surface: surface);

  Future<List<ShoppingAffiliate>> _findForSurface(String ingredient,
      {String? surface}) async {
    final direct = await _findExact(ingredient, surface: surface);
    if (direct.isNotEmpty || ingredient.trim().isEmpty) return direct;

    // Recipe spelling can differ from a catalog alias, for example
    // "다진 마늘" and "다진마늘". Only use candidates returned by the
    // server-backed catalog search after the exact lookup failed.
    try {
      final suggestions = await searchNames(ingredient, 0);
      final related = <ShoppingAffiliate>[];
      final seen = <String>{};
      for (final suggestion in suggestions) {
        if (!_relatedIngredient(ingredient, suggestion.name)) continue;
        for (final offer
            in await _findExact(suggestion.name, surface: surface)) {
          if (seen.add(offer.id)) {
            related.add(ShoppingAffiliate({
              ...offer.data,
              '_suggested_match': true,
              '_matched_ingredient': suggestion.name,
            }));
          }
        }
      }
      return related;
    } catch (_) {
      // Discovery is optional. Older servers keep the normal empty state.
      return direct;
    }
  }

  bool _relatedIngredient(String query, String candidate) {
    String key(String value) =>
        value.trim().toLowerCase().replaceAll(RegExp(r'\s+'), '');
    final q = key(query), c = key(candidate);
    if (q.isEmpty || c.isEmpty) return false;
    return q == c || q.contains(c) || c.contains(q);
  }

  Future<List<ShoppingAffiliate>> _findExact(String ingredient,
      {String? surface}) async {
    final params = {
      'p_ingredient': ingredient,
      'p_surface': surface ?? (kIsWeb ? 'web' : 'mobile'),
    };
    dynamic rows;
    try {
      rows = await client.rpc('find_shopping_affiliates_v3', params: params);
    } on PostgrestException catch (e) {
      // Older servers can still show links, without product photos.
      if (!['PGRST202', '42883'].contains(e.code)) rethrow;
      try {
        rows = await client.rpc('find_shopping_affiliates_v2', params: params);
      } on PostgrestException catch (v2Error) {
        if (!['PGRST202', '42883'].contains(v2Error.code)) rethrow;
        rows = await client.rpc('find_shopping_affiliates', params: params);
      }
    }
    return (rows as List)
        .map((e) => ShoppingAffiliate(Map<String, dynamic>.from(e)))
        .where((e) => e.uri != null)
        .toList();
  }

  Future<List<Map<String, dynamic>>> adminList() async =>
      (await client.rpc('admin_shopping_affiliates') as List)
          .map((e) => Map<String, dynamic>.from(e))
          .toList();
  Future<Map<String, dynamic>> page(
          String query, String status, int offset) async =>
      Map<String, dynamic>.from(
          await client.rpc('admin_shopping_affiliate_page', params: {
        'p_query': query,
        'p_status': status,
        'p_offset': offset,
        'p_limit': 25,
      }));
  Future<void> change(Map<String, dynamic> row, String action) async {
    await client.rpc('admin_change_shopping_affiliate', params: {
      'p_id': row['id'],
      'p_revision': row['revision'],
      'p_action': action,
    });
  }

  Future<List<Map<String, dynamic>>> history(String id, {int? before}) async =>
      (await client.rpc('admin_shopping_affiliate_history', params: {
        'p_id': id,
        'p_before': before,
      }) as List)
          .map((e) => Map<String, dynamic>.from(e))
          .toList();
  Future<List<Map<String, dynamic>>> preview(
          List<Map<String, dynamic>> rows) async =>
      (await client.rpc('admin_preview_shopping_affiliates',
              params: {'p_rows': rows}) as List)
          .map((e) => Map<String, dynamic>.from(e))
          .toList();
  Future<List<Map<String, dynamic>>> importRows(
          List<Map<String, dynamic>> rows) async =>
      (await client.rpc('admin_import_shopping_affiliates',
              params: {'p_rows': rows}) as List)
          .map((e) => Map<String, dynamic>.from(e))
          .toList();
  Future<Map<String, dynamic>?> recovery(
      {String? id, String? program, String? link}) async {
    final result = await client.rpc('admin_affiliate_recovery',
        params: {'p_id': id, 'p_program': program, 'p_link': link});
    return result == null ? null : Map<String, dynamic>.from(result as Map);
  }

  Future<void> save(Map<String, dynamic> data) async {
    if (affiliateUri(data['program'] as String, data['link'] as String) ==
        null) {
      throw const FormatException('Invalid affiliate link');
    }
    await client.rpc('admin_save_shopping_affiliate',
        params: {'p_data': data, 'p_revision': data['revision'] ?? 0});
  }
}

final shoppingAffiliateRepositoryProvider =
    Provider((ref) => ShoppingAffiliateRepository(Supabase.instance.client));
final shoppingAffiliatesProvider = FutureProvider.autoDispose
    .family<List<ShoppingAffiliate>, String>((ref, ingredient) async {
  if (ref.watch(activeAccountIdProvider) == null) return [];
  return ref.watch(shoppingAffiliateRepositoryProvider).find(ingredient);
});

class PurchaseNameSuggestion {
  const PurchaseNameSuggestion(this.name, this.exampleTitle);
  final String name, exampleTitle;
}

final purchaseNamesProvider = FutureProvider.autoDispose.family<
    List<PurchaseNameSuggestion>,
    ({String query, int offset, String? workspace})>((ref, input) async {
  if (ref.watch(activeAccountIdProvider) == null ||
      input.query.trim().isEmpty) {
    return [];
  }
  return ref
      .watch(shoppingAffiliateRepositoryProvider)
      .searchNames(input.query, input.offset, workspace: input.workspace);
});
