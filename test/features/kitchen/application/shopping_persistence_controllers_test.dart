import 'package:flutter_test/flutter_test.dart';
import 'package:k_youtube/features/kitchen/application/shopping_persistence_controllers.dart';
import 'package:k_youtube/features/kitchen/data/shopping_persistence.dart';
import 'package:k_youtube/features/kitchen/domain/shopping_review_drafts.dart';

class _MemoryStore implements KitchenKeyValueStore {
  final values = <String, String>{};

  @override
  Future<String?> read(String key) async => values[key];

  @override
  Future<void> write(String key, String value) async => values[key] = value;

  @override
  Future<void> remove(String key) async => values.remove(key);
}

class _FakeUuid implements UuidGenerator {
  int calls = 0;

  @override
  String v4() {
    calls++;
    return calls == 1
        ? '550e8400-e29b-41d4-a716-446655440000'
        : '550e8400-e29b-41d4-a716-446655440001';
  }
}

void main() {
  test('draft controller requires an authenticated user and namespaces storage',
      () async {
    final store = _MemoryStore();
    final uuid = _FakeUuid();
    String? userId = 'user-a';
    final controller = ShoppingReviewDraftController(
      store: ShoppingReviewDraftStore(storage: store, uuidGenerator: uuid),
      currentUserId: () async => userId,
    );
    final draft = await controller.getOrCreate(
      sourceRecipeId: 'recipe-1',
      initialItems: const <ShoppingReviewDraftItem>[
        ShoppingReviewDraftItem(
          localId: 'local-1',
          ingredientText: 'original text',
          name: '',
          quantityInput: '',
          quantity: null,
          unit: null,
        ),
      ],
    );
    expect(draft.sourceRecipeId, 'recipe-1');
    userId = null;
    await expectLater(
      controller.cancel('recipe-1'),
      throwsA(isA<StateError>()),
    );
  });
}
