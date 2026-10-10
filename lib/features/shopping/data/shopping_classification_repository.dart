import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../domain/shopping_preparation.dart';

final shoppingClassificationRepositoryProvider =
    Provider((ref) => ShoppingClassificationRepository());

/// Transmits ingredient names only, never inventory, quantities or recipe text.
class ShoppingClassificationRepository {
  Future<ShoppingClassification> classify(List<String> names) async {
    if (names.isEmpty ||
        names.length > 20 ||
        names.any((n) => n.trim().isEmpty || n.length > 120)) {
      throw const FormatException('Invalid classification names');
    }
    final client = Supabase.instance.client;
    final account = client.auth.currentUser;
    if (account == null || account.isAnonymous) {
      throw StateError('Sign in required');
    }
    final response =
        await client.functions.invoke('ai_purchase_request_review', body: {
      'task': 'categorize',
      'items': [
        for (var i = 0; i < names.length; i++) {'id': '$i', 'name': names[i]}
      ]
    });
    if (client.auth.currentUser?.id != account.id || response.status != 200) {
      throw StateError('Classification unavailable');
    }
    return parseClassification(response.data, names.length);
  }

  static ShoppingClassification parseClassification(dynamic data, int count) {
    final categories = parseCategories(data, count);
    final matches = <List<int>>[];
    final seen = <int>{};
    final raw = data['matches'] ?? [];
    if (raw is! List || raw.length > 10) {
      throw const FormatException('Invalid matches');
    }
    for (final group in raw) {
      if (group is! List || group.length < 2 || group.length > count) {
        throw const FormatException('Invalid match group');
      }
      final ids = <int>[];
      for (final value in group) {
        final id = value is String ? int.tryParse(value) : null;
        if (id == null || id < 0 || id >= count || !seen.add(id)) {
          throw const FormatException('Invalid match identity');
        }
        ids.add(id);
      }
      matches.add(ids);
    }
    return ShoppingClassification(categories, matches);
  }

  static List<ShoppingCategory> parseCategories(dynamic data, int count) {
    if (data is! Map ||
        data.keys.any((k) => k != 'categories' && k != 'matches') ||
        data['categories'] is! List) {
      throw const FormatException('Invalid categories');
    }
    final rows = data['categories'] as List;
    final values = <int, ShoppingCategory>{};
    for (final row in rows) {
      if (row is! Map ||
          row.length != 2 ||
          row['id'] is! String ||
          row['category'] is! String) {
        throw const FormatException('Invalid category');
      }
      final id = int.tryParse(row['id'] as String);
      final category = ShoppingCategory.values
          .where((c) => c.name == row['category'])
          .firstOrNull;
      if (id == null ||
          id < 0 ||
          id >= count ||
          values.containsKey(id) ||
          category == null) {
        throw const FormatException('Invalid category identity');
      }
      values[id] = category;
    }
    if (values.length != count) {
      throw const FormatException('Incomplete categories');
    }
    return [for (var i = 0; i < count; i++) values[i]!];
  }
}
