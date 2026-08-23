import 'package:flutter_test/flutter_test.dart';
import 'package:k_youtube/features/ingredient_search/data/ingredient_search_history_store.dart';
import 'package:k_youtube/features/kitchen/data/shopping_persistence.dart';

class _MemoryStore implements KitchenKeyValueStore {
  final Map<String, String> values = <String, String>{};

  @override
  Future<void> remove(String key) async {
    values.remove(key);
  }

  @override
  Future<String?> read(String key) async => values[key];

  @override
  Future<void> write(String key, String value) async {
    values[key] = value;
  }
}

void main() {
  test('stores recent ingredient combinations in newest-first order', () async {
    final store = IngredientSearchHistoryStore(
      storage: _MemoryStore(),
    );

    await store.add('user-1', <String>['감자', '돼지고기']);

    final history = await store.add(
      'user-1',
      <String>['계란', '양파'],
    );

    expect(history, <List<String>>[
      <String>['계란', '양파'],
      <String>['감자', '돼지고기'],
    ]);
  });

  test('removes duplicate ingredient combinations and limits entries',
      () async {
    final store = IngredientSearchHistoryStore(
      storage: _MemoryStore(),
    );

    for (var index = 0; index < 12; index += 1) {
      await store.add('user-1', <String>['재료$index']);
    }

    final history = await store.add(
      'user-1',
      <String>['재료5', '재료5'],
    );

    expect(history.length, IngredientSearchHistoryStore.maxEntries);
    expect(history.first, <String>['재료5']);
    expect(
      history.where((entry) => entry.join('|') == '재료5').length,
      1,
    );
  });

  test('clears saved history for the current user only', () async {
    final store = IngredientSearchHistoryStore(
      storage: _MemoryStore(),
    );

    await store.add('user-1', <String>['감자']);
    await store.add('user-2', <String>['양파']);

    await store.clear('user-1');

    expect(await store.load('user-1'), isEmpty);
    expect(await store.load('user-2'), <List<String>>[
      <String>['양파'],
    ]);
  });
}
