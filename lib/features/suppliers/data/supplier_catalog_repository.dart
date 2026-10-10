import 'dart:typed_data';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../auth/application/auth_providers.dart';
import '../../shopping/domain/supplier_request.dart';
import '../domain/supplier_catalog.dart';
import '../domain/public_supplier.dart';

abstract class SupplierCatalogRepository {
  Future<List<PublicSupplier>> publicReferences(
          {String query = '',
          String category = '',
          String region = '',
          int offset = 0}) async =>
      [];
  Future<ShoppingSupplier> selectPublicReference(String id) =>
      throw UnimplementedError();
  Future<CatalogSupplier?> myBusiness();
  Future<List<CatalogProduct>> myProducts(String supplierId);
  Future<CatalogSupplier> saveBusiness(CatalogSupplier supplier);
  Future<CatalogProduct> saveProduct(CatalogProduct product);
  Future<List<SupplierOffer>> search(
      {String query = '',
      String category = '',
      String subcategory = '',
      String region = '',
      String origin = '',
      String brand = '',
      bool priced = false,
      bool verified = false,
      bool rated = false,
      int offset = 0});
  Future<List<SupplierOffer>> currentOffers(List<String> ids);
  Future<ShoppingSupplier> selectSupplier(String id);
  Future<String> uploadImage(String supplierId, Uint8List bytes);
  Future<String> imageUrl(String path);
  Future<void> discardImage(String path);
  Future<void> rate(String requestId, int stars, String note);
}

final supplierCatalogRepositoryProvider = Provider<SupplierCatalogRepository>(
    (ref) => SupabaseSupplierCatalogRepository(Supabase.instance.client));
final mySupplierBusinessProvider =
    FutureProvider.autoDispose<CatalogSupplier?>((ref) async {
  if (ref.watch(activeAccountIdProvider) == null) return null;
  return ref.watch(supplierCatalogRepositoryProvider).myBusiness();
});
final myCatalogProductsProvider = FutureProvider.autoDispose
    .family<List<CatalogProduct>, String>((ref, id) async {
  if (ref.watch(activeAccountIdProvider) == null) return [];
  return ref.watch(supplierCatalogRepositoryProvider).myProducts(id);
});
final supplierProductImageProvider =
    FutureProvider.autoDispose.family<String, String>((ref, path) async {
  if (ref.watch(activeAccountIdProvider) == null || path.isEmpty) {
    throw StateError('Image unavailable');
  }
  return ref.watch(supplierCatalogRepositoryProvider).imageUrl(path);
});

String? supplierImageType(Uint8List bytes) {
  if (bytes.length < 12 || bytes.length > 5 * 1024 * 1024) return null;
  if (bytes[0] == 0xff && bytes[1] == 0xd8 && bytes[2] == 0xff) return 'jpeg';
  if ([137, 80, 78, 71, 13, 10, 26, 10]
      .asMap()
      .entries
      .every((e) => bytes[e.key] == e.value)) {
    return 'png';
  }
  if (String.fromCharCodes(bytes.take(4)) == 'RIFF' &&
      String.fromCharCodes(bytes.skip(8).take(4)) == 'WEBP') {
    return 'webp';
  }
  return null;
}

class SupabaseSupplierCatalogRepository implements SupplierCatalogRepository {
  SupabaseSupplierCatalogRepository(this.client);
  final SupabaseClient client;
  @override
  Future<List<PublicSupplier>> publicReferences(
      {String query = '',
      String category = '',
      String region = '',
      int offset = 0}) async {
    try {
      return (await client.rpc('search_public_supplier_listings', params: {
        'p_query': query,
        'p_category': category,
        'p_region': region,
        'p_offset': offset
      }) as List)
          .map((j) => PublicSupplier.fromJson(Map<String, dynamic>.from(j)))
          .toList();
    } on PostgrestException catch (e) {
      // The separate reference directory may roll out after the existing catalog.
      if (e.code == 'PGRST202') return [];
      rethrow;
    }
  }

  @override
  Future<ShoppingSupplier> selectPublicReference(String id) async =>
      ShoppingSupplier.fromJson(Map<String, dynamic>.from(await client
          .rpc('import_public_supplier_listing', params: {'p_id': id})));
  String get owner =>
      client.auth.currentUser?.id ?? (throw StateError('Sign in required'));
  @override
  Future<CatalogSupplier?> myBusiness() async {
    final row = await client
        .from('supplier_businesses')
        .select()
        .eq('owner_id', owner)
        .maybeSingle();
    return row == null ? null : CatalogSupplier.fromJson(row);
  }

  @override
  Future<List<CatalogProduct>> myProducts(String supplierId) async =>
      (await client
              .from('supplier_catalog_products')
              .select()
              .eq('supplier_id', supplierId)
              .order('name')
              .limit(300))
          .map(CatalogProduct.fromJson)
          .toList();
  @override
  Future<CatalogSupplier> saveBusiness(CatalogSupplier supplier) async =>
      CatalogSupplier.fromJson(Map<String, dynamic>.from(await client
          .rpc('save_supplier_business', params: {
        'p_data': supplier.toJson(),
        'p_revision': supplier.revision
      })));
  @override
  Future<CatalogProduct> saveProduct(CatalogProduct product) async =>
      CatalogProduct.fromJson(Map<String, dynamic>.from(await client
          .rpc('save_supplier_catalog_product', params: {
        'p_data': product.toJson(),
        'p_revision': product.revision
      })));
  @override
  Future<void> discardImage(String path) async {
    if (!path.startsWith('$owner/')) throw StateError('Image owner mismatch');
    await client.storage.from('supplier-products').remove([path]);
  }

  @override
  Future<List<SupplierOffer>> search(
          {String query = '',
          String category = '',
          String subcategory = '',
          String region = '',
          String origin = '',
          String brand = '',
          bool priced = false,
          bool verified = false,
          bool rated = false,
          int offset = 0}) async =>
      (await client.rpc('search_supplier_catalog', params: {
        'p_query': query,
        'p_category': category,
        'p_subcategory': subcategory,
        'p_region': region,
        'p_origin': origin,
        'p_brand': brand,
        'p_filters': {'priced': priced, 'verified': verified, 'rated': rated},
        'p_offset': offset,
        'p_limit': 30
      }) as List)
          .map((j) => SupplierOffer.fromJson(Map<String, dynamic>.from(j)))
          .toList();
  @override
  Future<List<SupplierOffer>> currentOffers(List<String> ids) async =>
      (await client.rpc('get_supplier_catalog_offers', params: {'p_ids': ids})
              as List)
          .map((j) => SupplierOffer.fromJson(Map<String, dynamic>.from(j)))
          .toList();
  @override
  Future<ShoppingSupplier> selectSupplier(String id) async =>
      ShoppingSupplier.fromJson(Map<String, dynamic>.from(
          await client.rpc('import_catalog_supplier', params: {'p_id': id})));
  @override
  Future<String> uploadImage(String supplierId, Uint8List bytes) async {
    final type = supplierImageType(bytes);
    if (type == null) {
      throw const FormatException('Use JPEG, PNG or WebP up to 5 MB');
    }
    final path =
        '$owner/$supplierId/${newShoppingId()}.${type == 'jpeg' ? 'jpg' : type}';
    await client.storage.from('supplier-products').uploadBinary(path, bytes,
        fileOptions: FileOptions(contentType: 'image/$type', upsert: false));
    return path;
  }

  @override
  Future<String> imageUrl(String path) =>
      client.storage.from('supplier-products').createSignedUrl(path, 900);
  @override
  Future<void> rate(String requestId, int stars, String note) async =>
      client.rpc('rate_catalog_supplier', params: {
        'p_request_id': requestId,
        'p_stars': stars,
        'p_note': note
      });
}
