import 'dart:convert';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../auth/application/auth_providers.dart';
import '../domain/workspace_profile.dart';

abstract class WorkspaceProfileRepository {
  Future<WorkspaceProfile> load(String? accountId);
  Future<void> save(String? accountId, WorkspaceProfile profile);
}

class SavedWorkspaceProfileRepository implements WorkspaceProfileRepository {
  SavedWorkspaceProfileRepository(this.auth);
  final GoTrueClient Function() auth;
  static const guestKey = 'scout_workspace_guest_v1';
  @override
  Future<WorkspaceProfile> load(String? accountId) async {
    if (accountId != null) {
      final client = auth();
      var user = client.currentUser;
      if (user?.id != accountId) throw StateError('Account changed');
      // Fetch a fresh preference on account startup; cached metadata supports offline use.
      try {
        user = (await client.getUser()).user ?? user;
      } catch (_) {/* Cached preference only. */}
      if (client.currentUser?.id != accountId || user?.id != accountId) {
        throw StateError('Account changed');
      }
      return WorkspaceProfile.fromJson(
          user!.userMetadata?[WorkspaceProfile.metadataKey]);
    }
    // Guest choices are device-local and never inherited by another account.
    try {
      final text = (await SharedPreferences.getInstance()).getString(guestKey);
      return WorkspaceProfile.fromJson(text == null ? null : jsonDecode(text));
    } catch (_) {
      return const WorkspaceProfile();
    }
  }

  @override
  Future<void> save(String? accountId, WorkspaceProfile profile) async {
    final data = profile.toJson();
    if (accountId == null) {
      if (!await (await SharedPreferences.getInstance())
          .setString(guestKey, jsonEncode(data))) {
        throw StateError('Preference not saved');
      }
      return;
    }
    final client = auth();
    if (client.currentUser?.id != accountId) {
      throw StateError('Account changed');
    }
    final result = await client
        .updateUser(UserAttributes(data: {WorkspaceProfile.metadataKey: data}));
    if (client.currentUser?.id != accountId || result.user?.id != accountId) {
      throw StateError('Account changed');
    }
  }
}

final workspaceProfileRepositoryProvider = Provider<WorkspaceProfileRepository>(
    (ref) =>
        SavedWorkspaceProfileRepository(() => ref.read(authClientProvider)));
final workspaceProfileProvider = StateNotifierProvider<
    WorkspaceProfileController, AsyncValue<WorkspaceProfile>>((ref) {
  final account = ref.watch(activeAccountIdProvider);
  return WorkspaceProfileController(
      ref.watch(workspaceProfileRepositoryProvider),
      account,
      () => ref.read(activeAccountIdProvider) == account)
    ..reload();
});

class WorkspaceProfileController
    extends StateNotifier<AsyncValue<WorkspaceProfile>> {
  WorkspaceProfileController(
      this.repository, this.account, this.isCurrentAccount)
      : super(const AsyncLoading());
  final WorkspaceProfileRepository repository;
  final String? account;
  final bool Function() isCurrentAccount;
  bool _saving = false;
  int _generation = 0;
  Future<void> reload() async {
    final generation = ++_generation;
    try {
      final profile = await repository.load(account);
      if (mounted && isCurrentAccount() && generation == _generation) {
        state = AsyncData(profile);
      }
    } catch (e, s) {
      if (mounted && isCurrentAccount() && generation == _generation) {
        state = AsyncError(e, s);
      }
    }
  }

  Future<bool> save(WorkspaceProfile profile) async {
    if (_saving || !profile.configured || !isCurrentAccount()) return false;
    _saving = true;
    ++_generation;
    try {
      await repository.save(account, profile);
      if (!mounted || !isCurrentAccount()) return false;
      state = AsyncData(profile);
      return true;
    } catch (_) {
      return false;
    } finally {
      _saving = false;
    }
  }
}
