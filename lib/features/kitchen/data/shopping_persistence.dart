import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:shared_preferences/shared_preferences.dart';

import '../domain/shopping_review_drafts.dart';

abstract interface class UuidGenerator {
  String v4();
}

class SecureUuidGenerator implements UuidGenerator {
  SecureUuidGenerator({Random? random}) : _random = random ?? Random.secure();

  final Random _random;

  @override
  String v4() {
    final bytes = List<int>.generate(16, (_) => _random.nextInt(256));
    bytes[6] = (bytes[6] & 0x0f) | 0x40;
    bytes[8] = (bytes[8] & 0x3f) | 0x80;
    final hex =
        bytes.map((value) => value.toRadixString(16).padLeft(2, '0')).join();
    return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-${hex.substring(12, 16)}-${hex.substring(16, 20)}-${hex.substring(20)}';
  }
}

abstract interface class KitchenKeyValueStore {
  Future<String?> read(String key);
  Future<void> write(String key, String value);
  Future<void> remove(String key);
}

class SharedPreferencesKeyValueStore implements KitchenKeyValueStore {
  SharedPreferencesKeyValueStore(this._preferences);

  final SharedPreferences _preferences;

  @override
  Future<String?> read(String key) async => _preferences.getString(key);

  @override
  Future<void> write(String key, String value) async {
    if (!await _preferences.setString(key, value)) {
      throw const KitchenStorageException('Unable to persist kitchen data');
    }
  }

  @override
  Future<void> remove(String key) async {
    if (!await _preferences.remove(key)) {
      // remove returns false when the key is already absent; that is idempotent.
    }
  }
}

class KitchenStorageException implements Exception {
  const KitchenStorageException(this.message);

  final String message;

  @override
  String toString() => 'KitchenStorageException';
}

class ShoppingReviewDraftStore {
  ShoppingReviewDraftStore({
    required KitchenKeyValueStore storage,
    UuidGenerator? uuidGenerator,
    DateTime Function()? clock,
  })  : _storage = storage,
        _uuid = uuidGenerator ?? SecureUuidGenerator(),
        _clock = clock ?? DateTime.now;

  static const _prefix = 'kitchen.shopping_review_draft.v1.';
  final KitchenKeyValueStore _storage;
  final UuidGenerator _uuid;
  final DateTime Function() _clock;
  final Map<String, Future<void>> _locks = <String, Future<void>>{};

  String _key(String userId, String sourceRecipeId) {
    if (userId.trim().isEmpty || sourceRecipeId.trim().isEmpty) {
      throw const KitchenStorageException(
          'Authenticated user and recipe are required');
    }
    return '$_prefix${Uri.encodeComponent(userId)}.${Uri.encodeComponent(sourceRecipeId)}';
  }

  Future<T> _withLock<T>(String key, Future<T> Function() action) async {
    final previous = _locks[key];
    final completer = Completer<void>();
    _locks[key] = completer.future;
    if (previous != null) await previous;
    try {
      return await action();
    } finally {
      completer.complete();
      if (identical(_locks[key], completer.future)) _locks.remove(key);
    }
  }

  Future<ShoppingReviewDraft> getOrCreateDraft({
    required String userId,
    required String sourceRecipeId,
    required List<ShoppingReviewDraftItem> initialItems,
  }) async {
    final key = _key(userId, sourceRecipeId);
    return _withLock(key, () async {
      final stored = await _storage.read(key);
      if (stored != null) {
        try {
          return ShoppingReviewDraft.fromJson(_decode(stored));
        } catch (_) {
          throw const KitchenStorageException(
              'Stored shopping review draft requires re-review');
        }
      }
      final now = _clock().toUtc();
      final draft = ShoppingReviewDraft(
        schemaVersion: shoppingReviewDraftSchemaVersion,
        draftId: _uuid.v4(),
        sourceRecipeId: sourceRecipeId,
        createIdempotencyKey: _uuid.v4(),
        createdAt: now,
        updatedAt: now,
        items: List.unmodifiable(initialItems),
      );
      _validateIdentifiers(draft.draftId, draft.createIdempotencyKey);
      draft.validate();
      await _storage.write(key, draft.serialize());
      return draft;
    });
  }

  Future<void> saveDraft(
      {required String userId, required ShoppingReviewDraft draft}) async {
    final key = _key(userId, draft.sourceRecipeId);
    draft.validate();
    await _withLock(key, () => _storage.write(key, draft.serialize()));
  }

  Future<void> clearDraft(
      {required String userId, required String sourceRecipeId}) async {
    await _storage.remove(_key(userId, sourceRecipeId));
  }

  static Map<String, dynamic> _decode(String value) {
    final decoded = jsonDecode(value);
    if (decoded is! Map<String, dynamic>) {
      throw const FormatException('Invalid stored draft');
    }
    return decoded;
  }

  static void _validateIdentifiers(String draftId, String key) {
    final uuid = RegExp(
        r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
        caseSensitive: false);
    if (!uuid.hasMatch(draftId) || !uuid.hasMatch(key)) {
      throw const KitchenStorageException(
          'Unable to create shopping review draft');
    }
  }
}

class CompletionKeyStore {
  CompletionKeyStore(
      {required KitchenKeyValueStore storage, UuidGenerator? uuidGenerator})
      : _storage = storage,
        _uuid = uuidGenerator ?? SecureUuidGenerator();

  static const _prefix = 'kitchen.shopping_completion.v1.';
  final KitchenKeyValueStore _storage;
  final UuidGenerator _uuid;
  final Map<String, Future<void>> _locks = <String, Future<void>>{};

  String _key(String userId, String listId) {
    if (userId.trim().isEmpty || listId.trim().isEmpty) {
      throw const KitchenStorageException(
          'Authenticated user and list are required');
    }
    return '$_prefix${Uri.encodeComponent(userId)}.${Uri.encodeComponent(listId)}';
  }

  Future<T> _withLock<T>(String key, Future<T> Function() action) async {
    final previous = _locks[key];
    final completer = Completer<void>();
    _locks[key] = completer.future;
    if (previous != null) await previous;
    try {
      return await action();
    } finally {
      completer.complete();
      if (identical(_locks[key], completer.future)) _locks.remove(key);
    }
  }

  Future<String> getOrCreateCompletionKey(
      {required String userId, required String listId}) async {
    final key = _key(userId, listId);
    return _withLock(key, () async {
      final existing = await _storage.read(key);
      if (existing != null && _isUuid(existing)) return existing;
      if (existing != null) {
        throw const KitchenStorageException(
            'Stored completion key requires re-review');
      }
      final generated = _uuid.v4();
      if (!_isUuid(generated)) {
        throw const KitchenStorageException('Unable to create completion key');
      }
      await _storage.write(key, generated);
      return generated;
    });
  }

  Future<void> clearCompletionKey(
      {required String userId, required String listId}) async {
    await _storage.remove(_key(userId, listId));
  }

  static bool _isUuid(String value) => RegExp(
          r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
          caseSensitive: false)
      .hasMatch(value);
}
