import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../auth/application/auth_providers.dart';
import '../domain/shopping_assistant.dart';

abstract class ShoppingAssistantRepository {
  Future<List<ShoppingFavorite>> favorites();
  Future<void> saveFavorite(ShoppingFavorite favorite);
  Future<void> removeFavorite(String id);
  Future<List<ShoppingPurchaseRecord>> records({String? ingredientName});
  Future<String> record(String requestKey, Map<String, dynamic> payload);
  Future<void> correctAmount(String id, double? amount, String currency);
}

final shoppingAssistantRepositoryProvider =
    Provider<ShoppingAssistantRepository>(
        (ref) => SupabaseShoppingAssistantRepository(Supabase.instance.client));

final shoppingFavoritesProvider = FutureProvider.autoDispose((ref) async {
  if (ref.watch(activeAccountIdProvider) == null) return <ShoppingFavorite>[];
  return ref.watch(shoppingAssistantRepositoryProvider).favorites();
});

final shoppingRecordsProvider = FutureProvider.autoDispose
    .family<List<ShoppingPurchaseRecord>, String?>((ref, name) async {
  if (ref.watch(activeAccountIdProvider) == null) {
    return <ShoppingPurchaseRecord>[];
  }
  return ref
      .watch(shoppingAssistantRepositoryProvider)
      .records(ingredientName: name);
});

final shoppingLinkLauncherProvider = Provider<Future<bool> Function(Uri)>(
    (ref) => (uri) => launchUrl(uri, mode: LaunchMode.externalApplication));

class SupabaseShoppingAssistantRepository
    implements ShoppingAssistantRepository {
  SupabaseShoppingAssistantRepository(this.client);
  final SupabaseClient client;
  String get _owner =>
      client.auth.currentUser?.id ?? (throw StateError('Sign in required'));
  @override
  Future<List<ShoppingFavorite>> favorites() async {
    final rows = await client
        .from('shopping_product_favorites')
        .select()
        .eq('owner_id', _owner)
        .order('ingredient_name')
        .limit(200);
    return rows.map(ShoppingFavorite.fromJson).toList();
  }

  @override
  Future<void> saveFavorite(ShoppingFavorite favorite) async {
    if (shoppingProductUri(favorite.url) == null) {
      throw const FormatException('Invalid product link');
    }
    await client.from('shopping_product_favorites').upsert({
      'owner_id': _owner,
      'ingredient_name': favorite.ingredientName.trim(),
      'unit': favorite.unit,
      'product_name': favorite.productName.trim(),
      'product_url': favorite.url.trim(),
      'pack_quantity': favorite.packQuantity,
    }, onConflict: 'owner_id,ingredient_key,unit');
  }

  @override
  Future<void> removeFavorite(String id) async {
    await client
        .from('shopping_product_favorites')
        .delete()
        .eq('id', id)
        .eq('owner_id', _owner);
  }

  @override
  Future<List<ShoppingPurchaseRecord>> records({String? ingredientName}) async {
    var query = client
        .from('shopping_purchase_records')
        .select(
            'id,ingredient_name,quantity,unit,paid_amount,currency,product_name,created_at')
        .eq('owner_id', _owner);
    if (ingredientName != null) {
      query = query.eq('ingredient_key', shoppingNameKey(ingredientName));
    }
    final rows = await query.order('created_at', ascending: false).limit(100);
    return rows.map(ShoppingPurchaseRecord.fromJson).toList();
  }

  @override
  Future<String> record(
          String requestKey, Map<String, dynamic> payload) async =>
      (await client.rpc('record_shopping_purchase', params: {
        'p_request_key': requestKey,
        'p_payload': payload,
      })) as String;
  @override
  Future<void> correctAmount(String id, double? amount, String currency) async {
    final rows = await client
        .from('shopping_purchase_records')
        .update({'paid_amount': amount, 'currency': currency})
        .eq('id', id)
        .eq('owner_id', _owner)
        .select('id');
    if (rows.length != 1) throw StateError('Purchase record unavailable');
  }
}
