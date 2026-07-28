import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import 'local_recipe_backup_service.dart';

class LocalSyncBetaStatus {
  const LocalSyncBetaStatus({
    this.lastPreparedAt,
    required this.recipeCount,
    required this.bookmarkCount,
    this.lastError,
  });

  final DateTime? lastPreparedAt;
  final int recipeCount;
  final int bookmarkCount;
  final String? lastError;

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'last_prepared_at': lastPreparedAt?.toUtc().toIso8601String(),
      'recipe_count': recipeCount,
      'bookmark_count': bookmarkCount,
      'last_error': lastError,
    };
  }

  static LocalSyncBetaStatus fromJson(Map<String, dynamic> json) {
    final rawTime = json['last_prepared_at']?.toString();
    DateTime? parsed;
    if (rawTime != null && rawTime.isNotEmpty) {
      parsed = DateTime.tryParse(rawTime);
    }
    return LocalSyncBetaStatus(
      lastPreparedAt: parsed,
      recipeCount: (json['recipe_count'] as num?)?.toInt() ?? 0,
      bookmarkCount: (json['bookmark_count'] as num?)?.toInt() ?? 0,
      lastError: json['last_error']?.toString(),
    );
  }
}

class LocalSyncBetaService {
  const LocalSyncBetaService({LocalRecipeBackupService? backupService})
      : _backupService = backupService ?? const LocalRecipeBackupService();

  static const String _statusStorageKey = 'recipes.local.sync_beta.status.v1';

  final LocalRecipeBackupService _backupService;

  Future<LocalSyncBetaStatus> getStatus() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_statusStorageKey);
    if (raw == null || raw.trim().isEmpty) {
      return const LocalSyncBetaStatus(
        recipeCount: 0,
        bookmarkCount: 0,
      );
    }

    final decoded = jsonDecode(raw);
    if (decoded is! Map<String, dynamic>) {
      return const LocalSyncBetaStatus(
        recipeCount: 0,
        bookmarkCount: 0,
      );
    }
    return LocalSyncBetaStatus.fromJson(decoded);
  }

  Future<LocalSyncBetaStatus> prepareBootstrapPreview() async {
    try {
      final payload = await _backupService.buildSyncBootstrapPayload(
        source: 'beta_preview',
      );
      final data = payload['payload'];
      if (data is! Map<String, dynamic>) {
        throw const FormatException('동기화 페이로드 형식이 올바르지 않습니다.');
      }

      final recipes = data['subscriber_recipes'];
      final bookmarks = data['bookmarks'];
      final recipeCount = recipes is List ? recipes.length : 0;
      final bookmarkCount = bookmarks is List ? bookmarks.length : 0;

      final status = LocalSyncBetaStatus(
        lastPreparedAt: DateTime.now().toUtc(),
        recipeCount: recipeCount,
        bookmarkCount: bookmarkCount,
      );
      await _saveStatus(status);
      return status;
    } catch (error) {
      final failed = LocalSyncBetaStatus(
        lastPreparedAt: DateTime.now().toUtc(),
        recipeCount: 0,
        bookmarkCount: 0,
        lastError: error.toString(),
      );
      await _saveStatus(failed);
      rethrow;
    }
  }

  Future<void> _saveStatus(LocalSyncBetaStatus status) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_statusStorageKey, jsonEncode(status.toJson()));
  }
}