import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../domain/shopping_affiliate.dart';

class CoupangPartnersException implements Exception {
  const CoupangPartnersException(this.code);
  final String code;
}

class CoupangProduct {
  const CoupangProduct(
      {required this.id,
      required this.title,
      required this.url,
      this.price,
      this.imageUrl});
  final String id, title, url;
  final num? price;
  final String? imageUrl;
}

class CoupangPartnersRepository {
  CoupangPartnersRepository(this.client);
  final SupabaseClient client;

  Future<Map<String, dynamic>> _invoke(Map<String, dynamic> body) async {
    try {
      final response =
          await client.functions.invoke('coupang_partners', body: body);
      if (response.data is! Map) {
        throw const CoupangPartnersException('upstream_invalid');
      }
      final data = Map<String, dynamic>.from(response.data as Map);
      if (data['error'] is String) {
        throw CoupangPartnersException(data['error'] as String);
      }
      return data;
    } on FunctionException catch (error) {
      final details = error.details;
      throw CoupangPartnersException(
          details is Map && details['error'] is String
              ? details['error'] as String
              : 'service_unavailable');
    }
  }

  Future<List<CoupangProduct>> search(String keyword) async {
    final data = await _invoke({'action': 'search', 'keyword': keyword.trim()});
    if (data['items'] is! List) {
      throw const CoupangPartnersException('upstream_invalid');
    }
    return (data['items'] as List).map((row) {
      if (row is! Map ||
          row['productId'] is! String ||
          row['title'] is! String ||
          !isCoupangProductUrl(
              row['productUrl'] is String ? row['productUrl'] as String : '')) {
        throw const CoupangPartnersException('upstream_invalid');
      }
      return CoupangProduct(
          id: row['productId'] as String,
          title: row['title'] as String,
          url: row['productUrl'] as String,
          price: row['price'] is num ? row['price'] as num : null,
          imageUrl: _coupangImageUrl(row['imageUrl']));
    }).toList();
  }

  Future<String> deeplink(String url) async {
    if (!isCoupangProductUrl(url)) {
      throw const CoupangPartnersException('invalid_input');
    }
    final data = await _invoke({'action': 'deeplink', 'url': url});
    final link = data['link'];
    if (link is! String || affiliateUri('coupang', link) == null) {
      throw const CoupangPartnersException('upstream_invalid');
    }
    return link;
  }
}

String? _coupangImageUrl(Object? value) {
  if (value is! String || value.length > 2048) return null;
  final uri = Uri.tryParse(value);
  if (uri == null ||
      uri.scheme != 'https' ||
      uri.userInfo.isNotEmpty ||
      uri.hasPort ||
      !uri.host.toLowerCase().endsWith('coupangcdn.com')) {
    return null;
  }
  return value;
}

bool isCoupangProductUrl(String value) =>
    value.length <= 2048 &&
    !RegExp(r'[\s\\\x00-\x1f\x7f]').hasMatch(value) &&
    RegExp(r'^https://www\.coupang\.com/vp/products/[0-9]+(?:\?[^#]+)?$')
        .hasMatch(value);

final coupangPartnersRepositoryProvider =
    Provider((ref) => CoupangPartnersRepository(Supabase.instance.client));
