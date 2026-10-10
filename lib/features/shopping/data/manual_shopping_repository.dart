import 'dart:convert';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../auth/application/auth_providers.dart';
import '../../kitchen/application/kitchen_providers.dart';
import '../../kitchen/data/shopping_persistence.dart';
import '../domain/manual_shopping.dart';

class ManualShoppingRepository {
  Future<String> create(String key, List<ManualShoppingItem> items) async =>
      (await Supabase.instance.client
          .rpc('create_manual_shopping_list', params: {
        'p_request_key': key,
        'p_items': items.map((e) => e.toJson()).toList(),
      })) as String;
}

final manualShoppingRepositoryProvider =
    Provider((ref) => ManualShoppingRepository());

class ManualShoppingDraftStore {
  final Map<String, Future<void>> _writes = {};
  Future<Map<String, dynamic>?> read(String owner) async {
    await _writes[owner]?.catchError((Object _) {});
    final value = (await SharedPreferences.getInstance())
        .getString('manual-shopping-v1:$owner');
    return value == null ? null : jsonDecode(value) as Map<String, dynamic>;
  }

  Future<void> write(String owner, Map<String, dynamic>? data) {
    final encoded = data == null ? null : jsonEncode(data);
    final next = (_writes[owner] ?? Future<void>.value())
        .catchError((Object _) {})
        .then((_) async {
      final prefs = await SharedPreferences.getInstance();
      final ok = encoded == null
          ? await prefs.remove('manual-shopping-v1:$owner')
          : await prefs.setString('manual-shopping-v1:$owner', encoded);
      if (!ok) throw const KitchenStorageException('Manual draft save failed');
    });
    _writes[owner] = next;
    return next;
  }
}

final manualShoppingDraftStoreProvider =
    Provider((ref) => ManualShoppingDraftStore());

final manualShoppingControllerProvider =
    FutureProvider((ref) async => ManualShoppingController(
          repository: ref.watch(manualShoppingRepositoryProvider),
          keys: await ref.watch(completionKeyStoreProvider.future),
          currentUser: () => ref.read(activeAccountIdProvider),
        ));

class ManualShoppingController {
  ManualShoppingController(
      {required this.repository,
      required this.keys,
      required this.currentUser});
  final ManualShoppingRepository repository;
  final CompletionKeyStore keys;
  final String? Function() currentUser;
  final Map<String, Future<String>> _pending = {};
  Future<String> create(String owner, List<ManualShoppingItem> items) {
    if (currentUser() != owner ||
        items.isEmpty ||
        items.length > 100 ||
        items.any((e) => !e.valid)) {
      throw StateError('Invalid manual shopping submission');
    }
    final snapshot = List<ManualShoppingItem>.unmodifiable(items);
    final identity =
        'manual-shopping:${jsonEncode(snapshot.map((e) => e.toJson()).toList())}';
    final lock = '$owner:$identity';
    return _pending[lock] ??=
        _create(owner, identity, snapshot).whenComplete(() {
      _pending.remove(lock);
    });
  }

  Future<String> _create(
      String owner, String identity, List<ManualShoppingItem> items) async {
    final key =
        await keys.getOrCreateCompletionKey(userId: owner, listId: identity);
    if (currentUser() != owner) throw StateError('Account changed');
    final id = await repository.create(key, items);
    if (currentUser() != owner) throw StateError('Account changed');
    // Keep the key until the UI has cleared its persisted draft. A lost response,
    // restart or draft-clear failure can safely replay the same server result.
    return id;
  }

  Future<void> acknowledge(String owner, List<ManualShoppingItem> items) =>
      keys.clearCompletionKey(
          userId: owner,
          listId:
              'manual-shopping:${jsonEncode(items.map((e) => e.toJson()).toList())}');
}
