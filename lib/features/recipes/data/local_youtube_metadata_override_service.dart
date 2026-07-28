import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

class CreatorYoutubeMetadataOverride {
  const CreatorYoutubeMetadataOverride({
    this.displayTitle,
    this.note,
  });

  final String? displayTitle;
  final String? note;

  bool get isEmpty =>
      (displayTitle ?? '').trim().isEmpty && (note ?? '').trim().isEmpty;

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'display_title': displayTitle,
      'note': note,
    };
  }

  static CreatorYoutubeMetadataOverride? fromJson(Map<String, dynamic> json) {
    final displayTitle = json['display_title']?.toString().trim();
    final note = json['note']?.toString().trim();

    final normalizedDisplayTitle =
        displayTitle == null || displayTitle.isEmpty ? null : displayTitle;
    final normalizedNote = note == null || note.isEmpty ? null : note;

    final value = CreatorYoutubeMetadataOverride(
      displayTitle: normalizedDisplayTitle,
      note: normalizedNote,
    );

    return value.isEmpty ? null : value;
  }
}

class LocalYoutubeMetadataOverrideService {
  const LocalYoutubeMetadataOverrideService();

  static const String _storageKey =
      'recipes.local.youtube_metadata_overrides.v1';

  Future<Map<String, CreatorYoutubeMetadataOverride>> _readAll() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_storageKey);
    if (raw == null || raw.trim().isEmpty) {
      return <String, CreatorYoutubeMetadataOverride>{};
    }

    final decoded = jsonDecode(raw);
    if (decoded is! Map<String, dynamic>) {
      return <String, CreatorYoutubeMetadataOverride>{};
    }

    final result = <String, CreatorYoutubeMetadataOverride>{};
    for (final entry in decoded.entries) {
      final value = entry.value;
      if (value is Map<String, dynamic>) {
        final override = CreatorYoutubeMetadataOverride.fromJson(value);
        if (override != null) {
          result[entry.key] = override;
        }
      }
    }
    return result;
  }

  Future<void> _writeAll(Map<String, CreatorYoutubeMetadataOverride> values) async {
    final prefs = await SharedPreferences.getInstance();
    final payload = values.map(
      (String key, CreatorYoutubeMetadataOverride value) =>
          MapEntry<String, dynamic>(key, value.toJson()),
    );
    await prefs.setString(_storageKey, jsonEncode(payload));
  }

  Future<CreatorYoutubeMetadataOverride?> getForRecipe(String recipeId) async {
    final values = await _readAll();
    return values[recipeId];
  }

  Future<void> saveForRecipe({
    required String recipeId,
    String? displayTitle,
    String? note,
  }) async {
    final values = await _readAll();
    final override = CreatorYoutubeMetadataOverride(
      displayTitle: displayTitle?.trim().isEmpty ?? true ? null : displayTitle!.trim(),
      note: note?.trim().isEmpty ?? true ? null : note!.trim(),
    );

    if (override.isEmpty) {
      values.remove(recipeId);
    } else {
      values[recipeId] = override;
    }

    await _writeAll(values);
  }

  Future<void> clearForRecipe(String recipeId) async {
    final values = await _readAll();
    values.remove(recipeId);
    await _writeAll(values);
  }
}