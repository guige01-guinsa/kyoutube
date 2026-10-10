import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:k_youtube/features/kitchen/data/shopping_persistence.dart';
import 'package:k_youtube/features/shopping/application/shopping_purchase_controller.dart';
import 'package:k_youtube/features/shopping/data/shopping_assistant_repository.dart';

class MemoryShoppingStore implements KitchenKeyValueStore {
  final values = <String, String>{};
  @override
  Future<String?> read(String key) async => values[key];
  @override
  Future<void> write(String key, String value) async {
    values[key] = value;
  }

  @override
  Future<void> remove(String key) async {
    values.remove(key);
  }
}

class PurchaseRepository extends ShoppingAssistantRepository {
  final requests = <String>[];
  Completer<void>? barrier;
  bool failOnce = false;
  @override
  Future<String> record(String key, Map<String, dynamic> payload) async {
    requests.add(key);
    await barrier?.future;
    if (failOnce) {
      failOnce = false;
      throw TimeoutException('test');
    }
    return 'receipt';
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  test(
      'uncertain response reuses key after controller restart and isolates accounts',
      () async {
    final store = MemoryShoppingStore();
    final repository = PurchaseRepository()..failOnce = true;
    var account = 'user-a';
    ShoppingPurchaseController create() => ShoppingPurchaseController(
        repository: repository,
        keys: CompletionKeyStore(storage: store),
        currentUser: () => account);
    final payload = <String, dynamic>{'name': 'Tofu', 'quantity': 500};
    await expectLater(
        create().record(payload), throwsA(isA<TimeoutException>()));
    expect(await create().record(payload), 'receipt');
    expect(repository.requests[0], repository.requests[1]);
    account = 'user-b';
    await create().record(payload);
    expect(repository.requests[2], isNot(repository.requests[0]));
  });
  test('double tap joins one request', () async {
    final repository = PurchaseRepository()..barrier = Completer<void>();
    final controller = ShoppingPurchaseController(
        repository: repository,
        keys: CompletionKeyStore(storage: MemoryShoppingStore()),
        currentUser: () => 'user');
    final first = controller.record({'quantity': 500});
    final second = controller.record({'quantity': 500});
    await Future<void>.delayed(Duration.zero);
    expect(repository.requests, hasLength(1));
    repository.barrier!.complete();
    expect(await first, 'receipt');
    expect(await second, 'receipt');
  });
}
