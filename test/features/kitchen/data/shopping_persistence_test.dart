import 'package:flutter_test/flutter_test.dart';
import 'package:k_youtube/features/ingredient_search/domain/shopping_plan.dart';
import 'package:k_youtube/features/kitchen/data/shopping_persistence.dart';
import 'package:k_youtube/features/kitchen/domain/shopping_review_drafts.dart';

class _MemoryStore implements KitchenKeyValueStore {
  final values = <String, String>{};

  @override
  Future<String?> read(String key) async => values[key];

  @override
  Future<void> remove(String key) async => values.remove(key);

  @override
  Future<void> write(String key, String value) async => values[key] = value;
}

class _FakeUuid implements UuidGenerator {
  _FakeUuid(this.values);

  final List<String> values;
  int index = 0;

  @override
  String v4() => values[index++];
}

const _uuidA = '550e8400-e29b-41d4-a716-446655440000';
const _uuidB = '550e8400-e29b-41d4-a716-446655440001';

ShoppingReviewDraftItem _item({String name = ''}) => ShoppingReviewDraftItem(
      localId: 'local-1',
      ingredientText: '2 kg potato',
      name: name,
      quantityInput: '2',
      quantity: 2,
      unit: 'kg',
      purchaseConfirmed: true,
    );

void main() {
  test('UUID generator emits RFC 4122 v4 values', () {
    final generator = SecureUuidGenerator();
    final values = List<String>.generate(20, (_) => generator.v4());
    expect(values.toSet(), hasLength(values.length));
    for (final value in values) {
      expect(
          value,
          matches(RegExp(
              r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$')));
    }
  });

  test('draft round trips and preserves ingredient text and input text', () {
    final draft = ShoppingReviewDraft(
      schemaVersion: shoppingReviewDraftSchemaVersion,
      draftId: _uuidA,
      sourceRecipeId: 'recipe-1',
      createIdempotencyKey: _uuidB,
      createdAt: DateTime.utc(2026, 1, 1),
      updatedAt: DateTime.utc(2026, 1, 2),
      items: <ShoppingReviewDraftItem>[_item()],
    );
    final restored = ShoppingReviewDraft.fromJson(draft.toJson());
    expect(restored.items.single.ingredientText, '2 kg potato');
    expect(restored.items.single.quantityInput, '2');
    expect(restored.createIdempotencyKey, _uuidB);
  });

  test('draft submission validation rejects invalid values and duplicates', () {
    final draft = ShoppingReviewDraft(
      schemaVersion: shoppingReviewDraftSchemaVersion,
      draftId: _uuidA,
      sourceRecipeId: 'recipe-1',
      createIdempotencyKey: _uuidB,
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
      items: <ShoppingReviewDraftItem>[_item()],
    );
    expect(() => draft.validate(forSubmission: true), throwsFormatException);
    expect(
      () => ShoppingReviewDraft(
        schemaVersion: 99,
        draftId: _uuidA,
        sourceRecipeId: 'recipe-1',
        createIdempotencyKey: _uuidB,
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
        items: <ShoppingReviewDraftItem>[
          _item(name: 'Potato'),
          _item(name: ' potato ')
        ],
      ).validate(forSubmission: true),
      throwsFormatException,
    );
  });

  test('draft store isolates users and recipes and reuses valid drafts',
      () async {
    final store = _MemoryStore();
    final uuids = _FakeUuid(<String>[
      _uuidA,
      _uuidB,
      '550e8400-e29b-41d4-a716-446655440002',
      '550e8400-e29b-41d4-a716-446655440003',
      '550e8400-e29b-41d4-a716-446655440004',
      '550e8400-e29b-41d4-a716-446655440005',
      '550e8400-e29b-41d4-a716-446655440006',
      '550e8400-e29b-41d4-a716-446655440007',
    ]);
    final drafts =
        ShoppingReviewDraftStore(storage: store, uuidGenerator: uuids);
    final first = await drafts.getOrCreateDraft(
        userId: 'user-a',
        sourceRecipeId: 'recipe-1',
        initialItems: <ShoppingReviewDraftItem>[_item()]);
    final reused = await drafts.getOrCreateDraft(
        userId: 'user-a',
        sourceRecipeId: 'recipe-1',
        initialItems: <ShoppingReviewDraftItem>[_item()]);
    final otherUser = await drafts.getOrCreateDraft(
        userId: 'user-b',
        sourceRecipeId: 'recipe-1',
        initialItems: <ShoppingReviewDraftItem>[_item()]);
    final otherRecipe = await drafts.getOrCreateDraft(
        userId: 'user-a',
        sourceRecipeId: 'recipe-2',
        initialItems: <ShoppingReviewDraftItem>[_item()]);
    expect(reused.draftId, first.draftId);
    expect(otherUser.draftId, isNot(first.draftId));
    expect(otherRecipe.draftId, isNot(first.draftId));
    await drafts.clearDraft(userId: 'user-a', sourceRecipeId: 'recipe-1');
    final replacement = await drafts.getOrCreateDraft(
        userId: 'user-a',
        sourceRecipeId: 'recipe-1',
        initialItems: <ShoppingReviewDraftItem>[_item()]);
    expect(replacement.draftId, isNot(first.draftId));
  });

  test('corrupt and unsupported drafts return typed storage errors', () async {
    final store = _MemoryStore();
    final drafts = ShoppingReviewDraftStore(
        storage: store, uuidGenerator: _FakeUuid(<String>[_uuidA, _uuidB]));
    await drafts.getOrCreateDraft(
        userId: 'user-a',
        sourceRecipeId: 'recipe-1',
        initialItems: <ShoppingReviewDraftItem>[_item()]);
    final key = store.values.keys.single;
    store.values[key] = '{bad json';
    expect(
        () => drafts.getOrCreateDraft(
            userId: 'user-a',
            sourceRecipeId: 'recipe-1',
            initialItems: <ShoppingReviewDraftItem>[_item()]),
        throwsA(isA<KitchenStorageException>()));
    store.values[key] = '{"schema_version":99}';
    expect(
        () => drafts.getOrCreateDraft(
            userId: 'user-a',
            sourceRecipeId: 'recipe-1',
            initialItems: <ShoppingReviewDraftItem>[_item()]),
        throwsA(isA<KitchenStorageException>()));
  });

  test(
      'edited rice and egg replace saved review while unchanged choices survive',
      () async {
    final memory = _MemoryStore();
    final store = ShoppingReviewDraftStore(storage: memory);
    List<ShoppingReviewDraftItem> items(List<String> ingredients) {
      final plan = ShoppingPlanBuilder.build(
          recipeIngredients: ingredients, availableIngredients: []);
      return List.generate(plan.items.length, (index) {
        final item = plan.items[index];
        return ShoppingReviewDraftItem(
          localId: 'ingredient-$index',
          ingredientText: item.rawIngredientText,
          name: item.normalizedName,
          quantityInput: '',
          quantity: null,
          unit: null,
          needsReview: item.needsReview,
          selected: item.normalizedName != '참기름',
        );
      });
    }

    final first = await store.getOrCreateDraft(
      userId: 'chef',
      sourceRecipeId: 'creator:bibimbap',
      initialItems: items([
        '참기름 1 큰술',
        '[확인 필요] 밥',
        '[확인 필요] 달걀 (기호에 따라 올림)',
      ]),
    );
    // A new store represents closing/reopening the app with a saved draft.
    final reopened = ShoppingReviewDraftStore(storage: memory);
    final edited = items(['밥 120g', '달걀 1개', '참기름 1 큰술', '당근 ½ 개 (채 썸)']);
    final refreshed = await reopened.getOrCreateDraft(
      userId: 'chef',
      sourceRecipeId: 'creator:bibimbap',
      initialItems: edited,
    );
    expect(refreshed.items.map((item) => item.ingredientText),
        ['밥 120g', '달걀 1개', '참기름 1 큰술', '당근 ½ 개 (채 썸)']);
    expect(refreshed.items[0].quantity, isNull);
    expect(refreshed.items[0].unit, isNull);
    expect(refreshed.items[1].quantity, isNull);
    expect(refreshed.items[1].unit, isNull);
    expect(refreshed.items.take(2).every((item) => !item.needsReview), isTrue);
    expect(refreshed.items[2].selected, isFalse);
    expect(refreshed.items[3].quantity, isNull);
    expect(refreshed.createIdempotencyKey, isNot(first.createIdempotencyKey));
    final retry = await reopened.getOrCreateDraft(
      userId: 'chef',
      sourceRecipeId: 'creator:bibimbap',
      initialItems: edited,
    );
    expect(retry.createIdempotencyKey, refreshed.createIdempotencyKey);
    expect(retry.serialize(), refreshed.serialize());
    final removed = await reopened.getOrCreateDraft(
      userId: 'chef',
      sourceRecipeId: 'creator:bibimbap',
      initialItems: items(['달걀 1개', '참기름 1 큰술']),
    );
    expect(removed.items.map((item) => item.name), ['달걀', '참기름']);
    expect(removed.items.last.selected, isFalse);
  });

  test(
      'legacy cooking amount is cleared without losing exclusion or original text',
      () async {
    final memory = _MemoryStore();
    final store = ShoppingReviewDraftStore(storage: memory);
    await store.getOrCreateDraft(
        userId: 'chef',
        sourceRecipeId: 'creator:half',
        initialItems: [
          const ShoppingReviewDraftItem(
              localId: '0',
              ingredientText: '당근 ½ 개',
              name: '당근',
              quantityInput: '0.5',
              quantity: 0.5,
              unit: 'ea',
              needsReview: true,
              selected: false),
        ]);
    final restored = await store.getOrCreateDraft(
        userId: 'chef',
        sourceRecipeId: 'creator:half',
        initialItems: [
          const ShoppingReviewDraftItem(
              localId: '0',
              ingredientText: '당근 ½ 개',
              name: '당근',
              quantityInput: '',
              quantity: null,
              unit: null),
        ]);
    expect(restored.items.single.quantity, isNull);
    expect(restored.items.single.unit, isNull);
    expect(restored.items.single.ingredientText, '당근 ½ 개');
    expect(restored.items.single.needsReview, isFalse);
    expect(restored.items.single.selected, isFalse);
  });

  test('concurrent draft creation returns one persisted key', () async {
    final store = _MemoryStore();
    final drafts = ShoppingReviewDraftStore(
        storage: store, uuidGenerator: _FakeUuid(<String>[_uuidA, _uuidB]));
    final results = await Future.wait(<Future<ShoppingReviewDraft>>[
      drafts.getOrCreateDraft(
          userId: 'user-a',
          sourceRecipeId: 'recipe-1',
          initialItems: <ShoppingReviewDraftItem>[_item()]),
      drafts.getOrCreateDraft(
          userId: 'user-a',
          sourceRecipeId: 'recipe-1',
          initialItems: <ShoppingReviewDraftItem>[_item()]),
    ]);
    expect(results[0].createIdempotencyKey, results[1].createIdempotencyKey);
    expect(store.values, hasLength(1));
  });

  test('completion key is reused on failure and cleared on success', () async {
    final store = _MemoryStore();
    final keys = CompletionKeyStore(
        storage: store,
        uuidGenerator: _FakeUuid(<String>[
          _uuidA,
          _uuidB,
          '550e8400-e29b-41d4-a716-446655440002',
        ]));
    final first =
        await keys.getOrCreateCompletionKey(userId: 'user-a', listId: 'list-1');
    final retry =
        await keys.getOrCreateCompletionKey(userId: 'user-a', listId: 'list-1');
    expect(retry, first);
    await keys.clearCompletionKey(userId: 'user-a', listId: 'list-1');
    final next =
        await keys.getOrCreateCompletionKey(userId: 'user-a', listId: 'list-1');
    expect(next, isNot(first));
    final other =
        await keys.getOrCreateCompletionKey(userId: 'user-b', listId: 'list-1');
    expect(other, isNot(next));
  });

  test('concurrent completion key creation returns one key', () async {
    final store = _MemoryStore();
    final keys = CompletionKeyStore(
        storage: store, uuidGenerator: _FakeUuid(<String>[_uuidA]));
    final results = await Future.wait(<Future<String>>[
      keys.getOrCreateCompletionKey(userId: 'user-a', listId: 'list-1'),
      keys.getOrCreateCompletionKey(userId: 'user-a', listId: 'list-1'),
    ]);
    expect(results[0], results[1]);
  });

  test(
      'draft validation enforces quantity pairing, canonical units, and submission names',
      () {
    ShoppingReviewDraft make(ShoppingReviewDraftItem item) =>
        ShoppingReviewDraft(
          schemaVersion: shoppingReviewDraftSchemaVersion,
          draftId: _uuidA,
          sourceRecipeId: 'recipe-1',
          createIdempotencyKey: _uuidB,
          createdAt: DateTime.now(),
          updatedAt: DateTime.now(),
          items: <ShoppingReviewDraftItem>[item],
        );
    expect(() => make(_item()).validate(), returnsNormally);
    expect(
        () => make(const ShoppingReviewDraftItem(
                localId: '1',
                ingredientText: 'x',
                name: '',
                quantityInput: '1',
                quantity: 1,
                unit: null))
            .validate(),
        throwsFormatException);
    expect(
        () => make(const ShoppingReviewDraftItem(
                localId: '1',
                ingredientText: 'x',
                name: '',
                quantityInput: '1',
                quantity: 1,
                unit: 'unsupported-unit'))
            .validate(),
        throwsFormatException);
    expect(
        () => make(const ShoppingReviewDraftItem(
                localId: '1',
                ingredientText: 'x',
                name: '',
                quantityInput: '1',
                quantity: 1,
                unit: 'kg'))
            .validate(forSubmission: true),
        throwsFormatException);
  });
}
