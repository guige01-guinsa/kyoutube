import 'dart:convert';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../auth/application/auth_providers.dart';

Object? _orderedJson(Object? value) {
  if (value is double && value.isFinite && value.abs() <= 9007199254740991 && value == value.truncateToDouble()) {
    return value.toInt();
  }
  if (value is List) return value.map(_orderedJson).toList();
  if (value is Map) {
    final keys = value.keys.cast<String>().toList()..sort();
    return {for (final key in keys) key: _orderedJson(value[key])};
  }
  return value;
}

final shoppingPreparationStoreProvider =
    Provider<ShoppingPreparationStore>((ref) {
  ref.watch(activeAccountIdProvider);
  return SyncedShoppingPreparationStore(
      SupabasePreparationRemote(Supabase.instance.client));
});

enum PreparationSync { local, synced, offline, conflict }

class PreparationConflict implements Exception {
  const PreparationConflict();
}

/// Each signed-in account has a separate local draft. No purchase or stock is
/// written to the server by preparing a list.
class ShoppingPreparationStore {
  PreparationSync status = PreparationSync.local;
  // Each open editor needs its own revision, even in the same application.
  ShoppingPreparationStore session() => this;
  Future<void> discardPending(String account) async {}
  Future<Map<String, dynamic>?> read(String account) async {
    final prefs = await SharedPreferences.getInstance();
    final value = prefs.getString('shopping-preparation-v1:$account');
    return value == null ? null : jsonDecode(value) as Map<String, dynamic>;
  }

  Future<void> write(String account, Map<String, dynamic> value) async {
    final prefs = await SharedPreferences.getInstance();
    if (!await prefs.setString(
        'shopping-preparation-v1:$account', jsonEncode(value))) {
      throw StateError('Could not save preparation');
    }
  }
}

class PreparationSnapshot {
  const PreparationSnapshot(this.revision, this.document);
  final int revision;
  final Map<String, dynamic>? document;
}

abstract class PreparationRemote {
  Future<PreparationSnapshot> read(String account);
  Future<PreparationSnapshot> save(
      String account, int revision, Map<String, dynamic> value);
}

class SupabasePreparationRemote implements PreparationRemote {
  SupabasePreparationRemote(this.client);
  final SupabaseClient client;
  void _check(String account) {
    if (client.auth.currentUser?.id != account ||
        client.auth.currentUser?.isAnonymous != false) {
      throw StateError('Account changed');
    }
  }

  @override
  Future<PreparationSnapshot> read(String account) async {
    _check(account);
    final row = await client
        .from('shopping_preparation_drafts')
        .select('revision,document')
        .eq('owner_id', account)
        .maybeSingle();
    _check(account);
    return PreparationSnapshot(row?['revision'] as int? ?? 0,
        row == null ? null : Map<String, dynamic>.from(row['document'] as Map));
  }

  @override
  Future<PreparationSnapshot> save(
      String account, int revision, Map<String, dynamic> value) async {
    _check(account);
    try {
      final result = await client.rpc('save_shopping_preparation', params: {
        'p_revision': revision,
        'p_document': value,
      });
      _check(account);
      return PreparationSnapshot(result['revision'] as int,
          Map<String, dynamic>.from(result['document'] as Map));
    } on PostgrestException catch (e) {
      if (e.code == '40001') throw const PreparationConflict();
      rethrow;
    }
  }
}

/// Persist pending edits before networking. A revision mismatch never overwrites
/// another device. The user can retry or explicitly discard their pending copy.
class SyncedShoppingPreparationStore extends ShoppingPreparationStore {
  SyncedShoppingPreparationStore(this.remote);
  final PreparationRemote remote;
  int? _revision;
  String? _account;
  String _key(String account) => 'shopping-preparation-sync-v1:$account';
  @override
  ShoppingPreparationStore session() => SyncedShoppingPreparationStore(remote);

  Future<void> _cache(String account, Map<String, dynamic> document,
      {required bool pending}) async {
    final prefs = await SharedPreferences.getInstance();
    if (!await prefs.setString(
        _key(account),
        jsonEncode({
          'revision': _revision,
          'pending': pending,
          'document': document,
        }))) {
      throw StateError('Could not save preparation');
    }
  }

  @override
  Future<Map<String, dynamic>?> read(String account) async {
    _account = account;
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key(account));
    final cache = raw == null ? null : jsonDecode(raw) as Map<String, dynamic>;
    _revision = cache?['revision'] as int?;
    final local = cache?['document'] as Map<String, dynamic>? ??
        await super.read(account);
    try {
      final server = await remote.read(account);
      if (cache?['pending'] == true) {
        // A retry after an ambiguous network failure is already saved if equal.
        if (jsonEncode(_orderedJson(server.document)) == jsonEncode(_orderedJson(local))) {
          _revision = server.revision;
          await _cache(account, local!, pending: false);
          status = PreparationSync.synced;
          return local;
        }
        if (_revision == null || server.revision != _revision) {
          status = PreparationSync.conflict;
          return local;
        }
        await write(account, local!);
        return local;
      }
      _revision = server.revision;
      status = PreparationSync.synced;
      if (server.document != null) {
        await _cache(account, server.document!, pending: false);
        return server.document;
      }
      // Import a legacy local draft only when no cloud draft exists, on save.
      // A successful server read is not evidence that this local draft synced.
      status = PreparationSync.local;
      return local;
    } on PreparationConflict {
      status = PreparationSync.conflict;
      return local;
    } catch (_) {
      status = PreparationSync.offline;
      return local;
    }
  }

  @override
  Future<void> write(String account, Map<String, dynamic> value) async {
    if (_account != account) {
      throw StateError('Read this account before saving');
    }
    await _cache(account, value, pending: true);
    if (status == PreparationSync.conflict) throw const PreparationConflict();
    try {
      if (_revision == null) {
        final server = await remote.read(account);
        if (server.revision != 0) throw const PreparationConflict();
        _revision = 0;
      }
      final saved = await remote.save(account, _revision!, value);
      _revision = saved.revision;
      await _cache(account, value, pending: false);
      status = PreparationSync.synced;
    } on PreparationConflict {
      status = PreparationSync.conflict;
      rethrow;
    } catch (_) {
      status = PreparationSync.offline;
    }
  }

  @override
  Future<void> discardPending(String account) async {
    // Check the server before deleting the only local pending copy.
    final server = await remote.read(account);
    final prefs = await SharedPreferences.getInstance();
    if (!await prefs.remove(_key(account))) {
      throw StateError('Could not clear draft');
    }
    if (!await prefs.remove('shopping-preparation-v1:$account')) {
      throw StateError('Could not clear draft');
    }
    _revision = server.revision;
    if (server.document != null) {
      await _cache(account, server.document!, pending: false);
    }
    status = PreparationSync.synced;
  }
}
