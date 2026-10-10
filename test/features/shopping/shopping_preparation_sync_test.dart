import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:k_youtube/features/shopping/data/shopping_preparation_store.dart';

class FakeRemote implements PreparationRemote {
  final rows = <String, PreparationSnapshot>{};
  bool offline = false;
  bool raceOnSave = false;
  @override
  Future<PreparationSnapshot> read(String account) async {
    if (offline) throw StateError('offline');
    return rows[account] ?? const PreparationSnapshot(0, null);
  }
  @override
  Future<PreparationSnapshot> save(String account, int revision, Map<String, dynamic> value) async {
    final old = await read(account);
    if (raceOnSave || old.revision != revision) throw const PreparationConflict();
    return rows[account] = PreparationSnapshot(revision + 1, Map.of(value));
  }
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));
  test('a legacy device draft is not labelled synced until saved remotely', () async {
    await ShoppingPreparationStore().write('alice', {'value': 7});
    final remote = FakeRemote();
    final store = SyncedShoppingPreparationStore(remote);
    expect(await store.read('alice'), {'value': 7});
    expect(store.status, PreparationSync.local);
    expect(remote.rows, isEmpty);
    await store.write('alice', {'value': 7});
    expect(store.status, PreparationSync.synced);
    expect(remote.rows['alice']!.document, {'value': 7});
  });
  test('an ambiguous completed save ignores JSON object key order', () async {
    final remote = FakeRemote();
    final store = SyncedShoppingPreparationStore(remote);
    await store.read('alice');
    remote.offline = true;
    await store.write('alice', {'a': 1.0, 'nested': {'b': 2.0, 'c': 3}});
    remote.offline = false;
    remote.rows['alice'] = const PreparationSnapshot(1, {'nested': {'c': 3, 'b': 2}, 'a': 1});
    final reopened = SyncedShoppingPreparationStore(remote);
    expect(await reopened.read('alice'), {'a': 1, 'nested': {'b': 2, 'c': 3}});
    expect(reopened.status, PreparationSync.synced);
    expect(remote.rows['alice']!.revision, 1);
  });
  test('a retry racing another device remains a conflict, not offline', () async {
    final remote = FakeRemote();
    final store = SyncedShoppingPreparationStore(remote);
    await store.read('alice');
    remote.offline = true;
    await store.write('alice', {'value': 1});
    remote.offline = false;
    remote.raceOnSave = true;
    final reopened = SyncedShoppingPreparationStore(remote);
    expect(await reopened.read('alice'), {'value': 1});
    expect(reopened.status, PreparationSync.conflict);
  });
  test('two devices sync account drafts without mixing accounts', () async {
    final remote = FakeRemote();
    final a = SyncedShoppingPreparationStore(remote);
    await a.read('alice');
    await a.write('alice', {'value': 1});
    SharedPreferences.setMockInitialValues({}); // fresh device
    final b = SyncedShoppingPreparationStore(remote);
    expect(await b.read('alice'), {'value': 1});
    expect(await b.read('bob'), isNull);
    expect(() => a.write('bob', {'value': 2}), throwsStateError);
  });
  test('concurrent edits preserve remote and offer explicit recovery', () async {
    final remote = FakeRemote();
    final a = SyncedShoppingPreparationStore(remote), b = SyncedShoppingPreparationStore(remote);
    await a.read('alice');
    await b.read('alice');
    await a.write('alice', {'value': 1});
    await expectLater(b.write('alice', {'value': 2}), throwsA(isA<PreparationConflict>()));
    expect(remote.rows['alice']!.document, {'value': 1});
    final reopened = SyncedShoppingPreparationStore(remote);
    expect(await reopened.read('alice'), {'value': 2});
    expect(reopened.status, PreparationSync.conflict);
    await reopened.discardPending('alice');
    expect(await reopened.read('alice'), {'value': 1});
    expect(reopened.status, PreparationSync.synced);
  });
  test('offline edits persist and retry only against the known base revision', () async {
    final remote = FakeRemote();
    final store = SyncedShoppingPreparationStore(remote);
    await store.read('alice');
    remote.offline = true;
    await store.write('alice', {'value': 3});
    expect(store.status, PreparationSync.offline);
    final reopened = SyncedShoppingPreparationStore(remote);
    expect(await reopened.read('alice'), {'value': 3});
    remote.offline = false;
    expect(await reopened.read('alice'), {'value': 3});
    expect(reopened.status, PreparationSync.synced);
    expect(remote.rows['alice']!.document, {'value': 3});
  });
  test('failed discard retains pending edits', () async {
    final remote = FakeRemote();
    final store = SyncedShoppingPreparationStore(remote);
    await store.read('alice');
    remote.offline = true;
    await store.write('alice', {'value': 4});
    await expectLater(store.discardPending('alice'), throwsStateError);
    expect(await SyncedShoppingPreparationStore(remote).read('alice'), {'value': 4});
  });
}
