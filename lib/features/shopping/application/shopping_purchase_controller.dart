import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../auth/application/auth_providers.dart';
import '../../kitchen/application/kitchen_providers.dart';
import '../../kitchen/data/shopping_persistence.dart';
import '../data/shopping_assistant_repository.dart';

final shoppingPurchaseControllerProvider =
    FutureProvider((ref) async => ShoppingPurchaseController(
          repository: ref.watch(shoppingAssistantRepositoryProvider),
          keys: await ref.watch(completionKeyStoreProvider.future),
          currentUser: () => ref.read(activeAccountIdProvider),
        ));

class ShoppingPurchaseController {
  ShoppingPurchaseController(
      {required this.repository,
      required this.keys,
      required this.currentUser});
  final ShoppingAssistantRepository repository;
  final CompletionKeyStore keys;
  final String? Function() currentUser;
  final Map<String, Future<String>> _pending = {};

  Future<String> record(Map<String, dynamic> payload) {
    final user = currentUser();
    if (user == null) throw StateError('Sign in required');
    final identity = 'purchase:${jsonEncode(payload)}';
    final lock = '$user:$identity';
    return _pending[lock] ??= _record(user, identity, payload).whenComplete(() {
      _pending.remove(lock);
    });
  }

  Future<String> _record(
      String user, String identity, Map<String, dynamic> payload) async {
    final key =
        await keys.getOrCreateCompletionKey(userId: user, listId: identity);
    if (currentUser() != user) throw StateError('Account changed');
    final result = await repository.record(key, payload);
    if (currentUser() != user) throw StateError('Account changed');
    // A timeout retains the key, including after an app restart. Once committed
    // and acknowledged, pending items disappear and cannot be purchased again.
    try {
      await keys.clearCompletionKey(userId: user, listId: identity);
    } on KitchenStorageException {/* acknowledgement is still successful */}
    return result;
  }
}
