import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import 'local_first_recipe_repository.dart';

enum LocalRecipeImportMode {
  overwrite,
  append,
}

enum LocalRecipeImportErrorCode {
  payloadTooLarge,
  invalidRoot,
  invalidRecipesField,
  invalidBookmarksField,
  tooManyRecipes,
  tooManyBookmarks,
  invalidRecipeItem,
  missingRequiredField,
  invalidIngredientOrStep,
  invalidBookmarkItem,
  unknown,
}

class LocalRecipeImportException implements Exception {
  const LocalRecipeImportException({
    required this.code,
    required this.message,
  });

  final LocalRecipeImportErrorCode code;
  final String message;

  @override
  String toString() {
    return 'LocalRecipeImportException(code: $code, message: $message)';
  }
}

class LocalRecipeImportResult {
  const LocalRecipeImportResult({
    required this.schemaVersion,
    required this.mode,
    required this.importedRecipeCount,
    required this.importedBookmarkCount,
    required this.recipeCount,
    required this.bookmarkCount,
    required this.skippedRecipeCount,
  });

  final int schemaVersion;
  final LocalRecipeImportMode mode;
  final int importedRecipeCount;
  final int importedBookmarkCount;
  final int recipeCount;
  final int bookmarkCount;
  final int skippedRecipeCount;
}

class LocalRecipeBackupService {
  const LocalRecipeBackupService();

  static const int maxImportBytes = 1024 * 1024;
  static const int maxRecipeCount = 2000;
  static const int maxBookmarkCount = 5000;

  Future<Map<String, dynamic>> exportSnapshot() async {
    final prefs = await SharedPreferences.getInstance();
    final rawRecipes =
        prefs.getString(LocalFirstRecipeRepository.subscriberRecipesStorageKey);
    final rawBookmarks =
        prefs.getStringList(LocalFirstRecipeRepository.bookmarksStorageKey) ??
            const <String>[];

    List<dynamic> recipes = <dynamic>[];
    if (rawRecipes != null && rawRecipes.trim().isNotEmpty) {
      final decoded = jsonDecode(rawRecipes);
      if (decoded is List) {
        recipes = decoded;
      }
    }

    return <String, dynamic>{
      'schema_version': LocalFirstRecipeRepository.localDataSchemaVersion,
      'exported_at': DateTime.now().toUtc().toIso8601String(),
      'subscriber_recipes': recipes,
      'bookmarks': rawBookmarks,
    };
  }

  Future<String> exportAsJsonString() async {
    final snapshot = await exportSnapshot();
    const encoder = JsonEncoder.withIndent('  ');
    return encoder.convert(snapshot);
  }

  Future<Map<String, dynamic>> buildSyncBootstrapPayload({
    String source = 'local_backup',
  }) async {
    final snapshot = await exportSnapshot();
    return <String, dynamic>{
      'source': source,
      'prepared_at': DateTime.now().toUtc().toIso8601String(),
      'payload': snapshot,
    };
  }

  Future<List<Map<String, dynamic>>> _readExistingRecipeMaps() async {
    final prefs = await SharedPreferences.getInstance();
    final raw =
        prefs.getString(LocalFirstRecipeRepository.subscriberRecipesStorageKey);
    if (raw == null || raw.trim().isEmpty) {
      return <Map<String, dynamic>>[];
    }
    final decoded = jsonDecode(raw);
    if (decoded is! List) {
      return <Map<String, dynamic>>[];
    }

    final result = <Map<String, dynamic>>[];
    for (final item in decoded) {
      if (item is Map) {
        result.add(
          item.map(
            (dynamic key, dynamic value) =>
                MapEntry<String, dynamic>(key.toString(), value),
          ),
        );
      }
    }
    return result;
  }

  Future<Set<String>> _readExistingBookmarks() async {
    final prefs = await SharedPreferences.getInstance();
    final raw =
        prefs.getStringList(LocalFirstRecipeRepository.bookmarksStorageKey) ??
            const <String>[];
    return raw.toSet();
  }

  LocalRecipeImportException _buildImportException(
    LocalRecipeImportErrorCode code,
    String message,
  ) {
    return LocalRecipeImportException(code: code, message: message);
  }

  Future<LocalRecipeImportResult> importFromJsonString(
    String raw, {
    LocalRecipeImportMode mode = LocalRecipeImportMode.overwrite,
  }) async {
    if (raw.length > maxImportBytes) {
      throw _buildImportException(
        LocalRecipeImportErrorCode.payloadTooLarge,
        '백업 파일이 너무 큽니다. 1MB 이하만 가져올 수 있습니다.',
      );
    }

    final decoded = jsonDecode(raw);
    if (decoded is! Map<String, dynamic>) {
      throw _buildImportException(
        LocalRecipeImportErrorCode.invalidRoot,
        '백업 형식이 올바르지 않습니다.',
      );
    }

    final schemaVersionRaw = decoded['schema_version'];
    final schemaVersion = schemaVersionRaw is int
        ? schemaVersionRaw
        : int.tryParse(schemaVersionRaw?.toString() ?? '') ?? 1;

    final recipesRaw = decoded['subscriber_recipes'];
    final bookmarksRaw = decoded['bookmarks'];

    if (recipesRaw is! List) {
      throw _buildImportException(
        LocalRecipeImportErrorCode.invalidRecipesField,
        'subscriber_recipes 필드가 올바르지 않습니다.',
      );
    }
    if (bookmarksRaw is! List) {
      throw _buildImportException(
        LocalRecipeImportErrorCode.invalidBookmarksField,
        'bookmarks 필드가 올바르지 않습니다.',
      );
    }

    if (recipesRaw.length > maxRecipeCount) {
      throw _buildImportException(
        LocalRecipeImportErrorCode.tooManyRecipes,
        '레시피 개수가 제한을 초과했습니다.',
      );
    }
    if (bookmarksRaw.length > maxBookmarkCount) {
      throw _buildImportException(
        LocalRecipeImportErrorCode.tooManyBookmarks,
        '북마크 개수가 제한을 초과했습니다.',
      );
    }

    final sanitizedRecipes = <Map<String, dynamic>>[];
    for (var i = 0; i < recipesRaw.length; i += 1) {
      final item = recipesRaw[i];
      if (item is! Map<String, dynamic>) {
        throw _buildImportException(
          LocalRecipeImportErrorCode.invalidRecipeItem,
          '레시피 항목 형식이 잘못되었습니다. index=$i',
        );
      }

      final id = (item['id'] ?? '').toString().trim();
      final title = (item['title'] ?? '').toString().trim();
      if (id.isEmpty || title.isEmpty) {
        throw _buildImportException(
          LocalRecipeImportErrorCode.missingRequiredField,
          '필수 필드(id/title)가 누락되었습니다. index=$i',
        );
      }

      final ingredients = item['ingredients'];
      final steps = item['steps'];
      if (ingredients is! List || steps is! List) {
        throw _buildImportException(
          LocalRecipeImportErrorCode.invalidIngredientOrStep,
          '재료/조리순서 형식이 잘못되었습니다. index=$i',
        );
      }

      sanitizedRecipes.add(<String, dynamic>{
        'id': id,
        'title': title,
        'summary': item['summary']?.toString(),
        'tips': item['tips']?.toString(),
        'ingredients': ingredients
            .map((dynamic e) => e.toString())
            .toList(growable: false),
        'steps': steps.map((dynamic e) => e.toString()).toList(growable: false),
        'imageUrl': item['imageUrl']?.toString(),
        'youtubeUrl': item['youtubeUrl']?.toString(),
        'notes': item['notes']?.toString(),
        'visibility': item['visibility']?.toString(),
        'sourceType': item['sourceType']?.toString(),
      });
    }

    final sanitizedBookmarks = <String>{};
    for (final item in bookmarksRaw) {
      final value = item.toString().trim();
      if (value.isEmpty || !value.contains(':')) {
        throw _buildImportException(
          LocalRecipeImportErrorCode.invalidBookmarkItem,
          '북마크 항목 형식이 올바르지 않습니다.',
        );
      }
      sanitizedBookmarks.add(value);
    }

    List<Map<String, dynamic>> targetRecipes;
    Set<String> targetBookmarks;
    var skippedRecipes = 0;

    if (mode == LocalRecipeImportMode.overwrite) {
      targetRecipes = List<Map<String, dynamic>>.from(sanitizedRecipes);
      targetBookmarks = Set<String>.from(sanitizedBookmarks);
    } else {
      final existingRecipes = await _readExistingRecipeMaps();
      final existingRecipeIds = <String>{};
      for (final item in existingRecipes) {
        final id = (item['id'] ?? '').toString().trim();
        if (id.isNotEmpty) {
          existingRecipeIds.add(id);
        }
      }

      targetRecipes = List<Map<String, dynamic>>.from(existingRecipes);
      for (final item in sanitizedRecipes) {
        final id = (item['id'] ?? '').toString().trim();
        if (existingRecipeIds.contains(id)) {
          skippedRecipes += 1;
          continue;
        }
        targetRecipes.add(item);
        existingRecipeIds.add(id);
      }

      final existingBookmarks = await _readExistingBookmarks();
      targetBookmarks = <String>{...existingBookmarks, ...sanitizedBookmarks};
    }

    if (targetRecipes.length > maxRecipeCount) {
      throw _buildImportException(
        LocalRecipeImportErrorCode.tooManyRecipes,
        '병합 후 레시피 개수가 제한을 초과했습니다.',
      );
    }
    if (targetBookmarks.length > maxBookmarkCount) {
      throw _buildImportException(
        LocalRecipeImportErrorCode.tooManyBookmarks,
        '병합 후 북마크 개수가 제한을 초과했습니다.',
      );
    }

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      LocalFirstRecipeRepository.subscriberRecipesStorageKey,
      jsonEncode(targetRecipes),
    );
    await prefs.setStringList(
      LocalFirstRecipeRepository.bookmarksStorageKey,
      targetBookmarks.toList(growable: false),
    );

    return LocalRecipeImportResult(
      schemaVersion: schemaVersion,
      mode: mode,
      importedRecipeCount: sanitizedRecipes.length,
      importedBookmarkCount: sanitizedBookmarks.length,
      recipeCount: targetRecipes.length,
      bookmarkCount: targetBookmarks.length,
      skippedRecipeCount: skippedRecipes,
    );
  }
}