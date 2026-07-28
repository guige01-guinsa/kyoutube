import 'dart:convert';

import '../../../core/ops/ops_monitor_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../data/recipe_repository.dart';
import '../domain/recipe.dart';

class RecipeFetchResult<T> {
  const RecipeFetchResult({
    required this.data,
    required this.fromCache,
    required this.fetchedAt,
    required this.isStale,
    this.networkErrorMessage,
  });

  final T data;
  final bool fromCache;
  final DateTime fetchedAt;
  final bool isStale;
  final String? networkErrorMessage;
}

class RecipeNetworkFallbackException implements Exception {
  const RecipeNetworkFallbackException({
    required this.message,
    this.cause,
  });

  final String message;
  final Object? cause;

  @override
  String toString() => message;
}

class RecipeNetworkFallbackService {
  RecipeNetworkFallbackService._();

  static const Duration _publicListTtl = Duration(minutes: 10);
  static const Duration _publicDetailTtl = Duration(hours: 24);
  static const String _publicListCachePrefix = 'recipes.cache.public_list.v1.';
  static const String _publicDetailCachePrefix =
      'recipes.cache.public_detail.v1.';

  static Future<RecipeFetchResult<List<Recipe>>> fetchPublicRecipes({
    required RecipeRepository repository,
    required String? search,
    required bool useAiSearch,
  }) async {
    final normalizedSearch = (search ?? '').trim();
    final cacheKey = _publicListCacheKey(
      search: normalizedSearch,
      useAiSearch: useAiSearch,
    );

    try {
      final recipes = await repository.listPublicRecipes(
        search: normalizedSearch.isEmpty ? null : normalizedSearch,
        useAiSearch: useAiSearch,
      );

      final now = DateTime.now();
      await _writeRecipesCache(cacheKey, recipes, now);

      return RecipeFetchResult<List<Recipe>>(
        data: recipes,
        fromCache: false,
        fetchedAt: now,
        isStale: false,
      );
    } catch (error) {
      await OpsMonitorService.recordEventCounter(
        'network.fetch.public_list.network_error',
      );
      final cached = await _readRecipesCache(cacheKey);
      if (cached != null) {
        final age = DateTime.now().difference(cached.fetchedAt);
        await OpsMonitorService.recordEventCounter(
          'network.fetch.public_list.cache_hit',
        );
        return RecipeFetchResult<List<Recipe>>(
          data: cached.recipes,
          fromCache: true,
          fetchedAt: cached.fetchedAt,
          isStale: age > _publicListTtl,
          networkErrorMessage: error.toString(),
        );
      }

      await OpsMonitorService.recordEventCounter(
        'network.fetch.public_list.fail_no_cache',
      );

      final message = error is StateError
          ? error.message.toString()
          : '공개 레시피를 불러오지 못했습니다. 네트워크를 확인해 주세요.';

      throw RecipeNetworkFallbackException(
        message: message,
        cause: error,
      );
    }
  }

  static Future<RecipeFetchResult<Recipe?>> fetchPublicRecipeDetail({
    required RecipeRepository repository,
    required String id,
  }) async {
    final normalizedId = id.trim();
    final cacheKey = '$_publicDetailCachePrefix$normalizedId';

    try {
      final recipe = await repository.getRecipeById(normalizedId);
      final now = DateTime.now();
      if (recipe != null) {
        await _writeRecipeCache(cacheKey, recipe, now);
      }

      return RecipeFetchResult<Recipe?>(
        data: recipe,
        fromCache: false,
        fetchedAt: now,
        isStale: false,
      );
    } catch (error) {
      await OpsMonitorService.recordEventCounter(
        'network.fetch.recipe_detail.network_error',
      );
      final cached = await _readRecipeCache(cacheKey);
      if (cached != null) {
        final age = DateTime.now().difference(cached.fetchedAt);
        await OpsMonitorService.recordEventCounter(
          'network.fetch.recipe_detail.cache_hit',
        );
        return RecipeFetchResult<Recipe?>(
          data: cached.recipe,
          fromCache: true,
          fetchedAt: cached.fetchedAt,
          isStale: age > _publicDetailTtl,
          networkErrorMessage: error.toString(),
        );
      }

      await OpsMonitorService.recordEventCounter(
        'network.fetch.recipe_detail.fail_no_cache',
      );

      throw RecipeNetworkFallbackException(
        message: '레시피 상세를 불러오지 못했습니다. 네트워크를 확인해 주세요.',
        cause: error,
      );
    }
  }

  static String _publicListCacheKey({
    required String search,
    required bool useAiSearch,
  }) {
    final raw = 'search=$search|ai=$useAiSearch';
    final encoded = base64UrlEncode(utf8.encode(raw));
    return '$_publicListCachePrefix$encoded';
  }

  static Future<void> _writeRecipesCache(
    String key,
    List<Recipe> recipes,
    DateTime fetchedAt,
  ) async {
    final prefs = await SharedPreferences.getInstance();
    final payload = <String, dynamic>{
      'fetchedAt': fetchedAt.toIso8601String(),
      'recipes': recipes.map(_recipeToJson).toList(),
    };
    await prefs.setString(key, jsonEncode(payload));
  }

  static Future<void> _writeRecipeCache(
    String key,
    Recipe recipe,
    DateTime fetchedAt,
  ) async {
    final prefs = await SharedPreferences.getInstance();
    final payload = <String, dynamic>{
      'fetchedAt': fetchedAt.toIso8601String(),
      'recipe': _recipeToJson(recipe),
    };
    await prefs.setString(key, jsonEncode(payload));
  }

  static Future<_RecipesCacheSnapshot?> _readRecipesCache(String key) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(key);
    if (raw == null || raw.isEmpty) {
      return null;
    }

    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map<String, dynamic>) {
        return null;
      }

      final fetchedAt =
          DateTime.tryParse((decoded['fetchedAt'] ?? '').toString());
      if (fetchedAt == null) {
        return null;
      }

      final rows = decoded['recipes'];
      if (rows is! List) {
        return null;
      }

      final recipes =
          rows.whereType<Map<String, dynamic>>().map(_recipeFromJson).toList();
      return _RecipesCacheSnapshot(fetchedAt: fetchedAt, recipes: recipes);
    } catch (_) {
      return null;
    }
  }

  static Future<_RecipeCacheSnapshot?> _readRecipeCache(String key) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(key);
    if (raw == null || raw.isEmpty) {
      return null;
    }

    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map<String, dynamic>) {
        return null;
      }

      final fetchedAt =
          DateTime.tryParse((decoded['fetchedAt'] ?? '').toString());
      if (fetchedAt == null) {
        return null;
      }

      final recipeMap = decoded['recipe'];
      if (recipeMap is! Map<String, dynamic>) {
        return null;
      }

      return _RecipeCacheSnapshot(
        fetchedAt: fetchedAt,
        recipe: _recipeFromJson(recipeMap),
      );
    } catch (_) {
      return null;
    }
  }

  static Map<String, dynamic> _recipeToJson(Recipe recipe) {
    return <String, dynamic>{
      'id': recipe.id,
      'title': recipe.title,
      'summary': recipe.summary,
      'tips': recipe.tips,
      'ingredients': recipe.ingredients,
      'steps': recipe.steps,
      'imageUrl': recipe.imageUrl,
      'youtubeUrl': recipe.youtubeUrl,
      'notes': recipe.notes,
      'visibility': recipe.visibility,
    };
  }

  static Recipe _recipeFromJson(Map<String, dynamic> json) {
    return Recipe(
      id: (json['id'] ?? '').toString(),
      title: (json['title'] ?? '').toString(),
      summary: json['summary'] as String?,
      tips: json['tips'] as String?,
      ingredients: ((json['ingredients'] as List?) ?? const <dynamic>[])
          .map((dynamic item) => item.toString())
          .toList(),
      steps: ((json['steps'] as List?) ?? const <dynamic>[])
          .map((dynamic item) => item.toString())
          .toList(),
      imageUrl: json['imageUrl'] as String?,
      youtubeUrl: json['youtubeUrl'] as String?,
      notes: json['notes'] as String?,
      visibility: json['visibility'] as String?,
    );
  }
}

class _RecipesCacheSnapshot {
  const _RecipesCacheSnapshot({
    required this.fetchedAt,
    required this.recipes,
  });

  final DateTime fetchedAt;
  final List<Recipe> recipes;
}

class _RecipeCacheSnapshot {
  const _RecipeCacheSnapshot({
    required this.fetchedAt,
    required this.recipe,
  });

  final DateTime fetchedAt;
  final Recipe recipe;
}
