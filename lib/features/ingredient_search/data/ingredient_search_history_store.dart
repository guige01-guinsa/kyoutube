import 'dart:convert';

import '../../kitchen/data/shopping_persistence.dart';

class IngredientSearchHistoryStore {
  IngredientSearchHistoryStore({
    required KitchenKeyValueStore storage,
  }) : _storage = storage;

  static const int maxEntries = 10;
  static const String _prefix = 'ingredient_search.history.v1.';

  final KitchenKeyValueStore _storage;

  String _key(String userId) {
    final normalizedUserId = userId.trim();

    if (normalizedUserId.isEmpty) {
      throw const IngredientSearchHistoryException(
        'Authenticated user is required',
      );
    }

    return '$_prefix${Uri.encodeComponent(normalizedUserId)}';
  }

  Future<List<List<String>>> load(String userId) async {
    final raw = await _storage.read(_key(userId));

    if (raw == null || raw.trim().isEmpty) {
      return const <List<String>>[];
    }

    try {
      final decoded = jsonDecode(raw);

      if (decoded is! List) {
        throw const FormatException();
      }

      final entries = <List<String>>[];

      for (final value in decoded) {
        if (value is! List) {
          continue;
        }

        final normalized = _normalize(value.map((item) => '$item'));

        if (normalized.isNotEmpty) {
          entries.add(normalized);
        }
      }

      return List<List<String>>.unmodifiable(entries);
    } catch (_) {
      throw const IngredientSearchHistoryException(
        'Stored ingredient search history is invalid',
      );
    }
  }

  Future<List<List<String>>> add(
    String userId,
    List<String> ingredients,
  ) async {
    final normalized = _normalize(ingredients);

    if (normalized.isEmpty) {
      return load(userId);
    }

    final existing = await load(userId);
    final key = _entryKey(normalized);

    final next = <List<String>>[
      normalized,
      ...existing.where((entry) => _entryKey(entry) != key),
    ].take(maxEntries).toList(growable: false);

    await _storage.write(
      _key(userId),
      jsonEncode(next),
    );

    return List<List<String>>.unmodifiable(next);
  }

  Future<void> clear(String userId) async {
    await _storage.remove(_key(userId));
  }

  static List<String> _normalize(Iterable<String> ingredients) {
    final seen = <String>{};
    final result = <String>[];

    for (final raw in ingredients) {
      final value = raw.trim();

      if (value.isEmpty) {
        continue;
      }

      final key = value.toLowerCase();

      if (seen.add(key)) {
        result.add(value);
      }
    }

    return List<String>.unmodifiable(result.take(5));
  }

  static String _entryKey(List<String> ingredients) {
    return ingredients
        .map((item) => item.trim().toLowerCase())
        .toList(growable: false)
        .join('|');
  }
}

class IngredientSearchHistoryException implements Exception {
  const IngredientSearchHistoryException(this.message);

  final String message;

  @override
  String toString() => 'IngredientSearchHistoryException';
}
