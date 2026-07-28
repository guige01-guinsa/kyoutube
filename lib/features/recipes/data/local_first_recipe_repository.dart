import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../domain/bookmarked_recipe.dart';
import '../domain/recipe.dart';
import '../domain/youtube_metadata.dart';
import 'recipe_repository.dart';
import 'supabase_recipe_repository.dart';

class LocalFirstRecipeRepository implements RecipeRepository {
  LocalFirstRecipeRepository({RecipeRepository? remote})
      : _remote = remote ?? SupabaseRecipeRepository();

  static const int localDataSchemaVersion = 1;
  static const String subscriberRecipesStorageKey =
      'recipes.local.subscriber.items.v1';
  static const String bookmarksStorageKey = 'recipes.local.bookmarks.v1';
    static const String creatorRecipesStorageKey =
      'recipes.local.creator.items.v1';

  final RecipeRepository _remote;

  String _newLocalId(String prefix) {
    final ts = DateTime.now().microsecondsSinceEpoch;
    return '$prefix-$ts';
  }

  Recipe _recipeFromMap(Map<String, dynamic> map) {
    List<String> toStringList(dynamic value) {
      if (value is! List) {
        return const <String>[];
      }
      return value.map((dynamic item) => item.toString()).toList();
    }

    return Recipe(
      id: (map['id'] ?? '').toString(),
      title: (map['title'] ?? '').toString(),
      summary: map['summary']?.toString(),
      tips: map['tips']?.toString(),
      ingredients: toStringList(map['ingredients']),
      steps: toStringList(map['steps']),
      imageUrl: map['imageUrl']?.toString(),
      youtubeUrl: map['youtubeUrl']?.toString(),
      notes: map['notes']?.toString(),
      visibility: map['visibility']?.toString(),
      sourceType: map['sourceType']?.toString(),
    );
  }

  Map<String, dynamic> _recipeToMap(Recipe recipe) {
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
      'sourceType': recipe.sourceType,
    };
  }

  Future<List<Recipe>> _readSubscriberRecipes() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(subscriberRecipesStorageKey);
    if (raw == null || raw.trim().isEmpty) {
      return <Recipe>[];
    }

    final decoded = jsonDecode(raw);
    if (decoded is! List) {
      return <Recipe>[];
    }

    final recipes = <Recipe>[];
    for (final dynamic item in decoded) {
      if (item is Map<String, dynamic>) {
        final recipe = _recipeFromMap(item);
        if (recipe.id.isNotEmpty && recipe.title.isNotEmpty) {
          recipes.add(recipe);
        }
      }
    }
    return recipes;
  }

  Future<void> _writeSubscriberRecipes(List<Recipe> recipes) async {
    final prefs = await SharedPreferences.getInstance();
    final serialized = recipes.map(_recipeToMap).toList(growable: false);
    await prefs.setString(subscriberRecipesStorageKey, jsonEncode(serialized));
  }

  Future<Set<String>> _readBookmarks() async {
    final prefs = await SharedPreferences.getInstance();
    final list =
        prefs.getStringList(bookmarksStorageKey) ?? const <String>[];
    return list.toSet();
  }

  Future<List<Recipe>> _readCreatorRecipes() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(creatorRecipesStorageKey);
    if (raw == null || raw.trim().isEmpty) {
      return <Recipe>[];
    }

    final decoded = jsonDecode(raw);
    if (decoded is! List) {
      return <Recipe>[];
    }

    final recipes = <Recipe>[];
    for (final dynamic item in decoded) {
      if (item is Map<String, dynamic>) {
        final recipe = _recipeFromMap(item);
        if (recipe.id.isNotEmpty && recipe.title.isNotEmpty) {
          recipes.add(recipe);
        }
      }
    }
    return recipes;
  }

  Future<void> _writeCreatorRecipes(List<Recipe> recipes) async {
    final prefs = await SharedPreferences.getInstance();
    final serialized = recipes.map(_recipeToMap).toList(growable: false);
    await prefs.setString(creatorRecipesStorageKey, jsonEncode(serialized));
  }

  Future<void> _upsertLocalCreatorRecipe(Recipe recipe) async {
    final creators = await _readCreatorRecipes();
    final index = creators.indexWhere((Recipe item) => item.id == recipe.id);
    if (index >= 0) {
      creators[index] = recipe;
    } else {
      creators.insert(0, recipe);
    }
    await _writeCreatorRecipes(creators);
  }

  Future<void> _deleteLocalCreatorRecipe(String id) async {
    final creators = await _readCreatorRecipes();
    creators.removeWhere((Recipe recipe) => recipe.id == id);
    await _writeCreatorRecipes(creators);
  }

  bool _matchesSearch(Recipe recipe, String search) {
    final q = search.trim().toLowerCase();
    if (q.isEmpty) {
      return true;
    }
    final haystack = <String>[
      recipe.title,
      recipe.summary ?? '',
      recipe.tips ?? '',
      recipe.ingredients.join(' '),
    ].join(' ').toLowerCase();
    return haystack.contains(q);
  }

  Future<void> _writeBookmarks(Set<String> values) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(
      bookmarksStorageKey,
      values.toList(growable: false),
    );
  }

  @override
  Future<Recipe> createSubscriberRecipeFromPublic({
    required Recipe source,
    String? notes,
  }) async {
    final recipes = await _readSubscriberRecipes();
    final created = Recipe(
      id: _newLocalId('user'),
      title: source.title,
      summary: source.summary,
      tips: source.tips,
      ingredients: List<String>.from(source.ingredients),
      steps: List<String>.from(source.steps),
      imageUrl: source.imageUrl,
      youtubeUrl: source.youtubeUrl,
      notes: (notes ?? source.notes)?.trim().isEmpty ?? true
          ? null
          : (notes ?? source.notes)!.trim(),
      visibility: 'private',
      sourceType: RecipeSourceType.publicImport,
    );

    recipes.insert(0, created);
    await _writeSubscriberRecipes(recipes);
    return created;
  }

  @override
  Future<Recipe> createSubscriberRecipe({
    required String title,
    required List<String> ingredients,
    required List<String> steps,
    String? summary,
    String? notes,
    String? imageUrl,
    String? youtubeUrl,
    String? sourceType,
  }) async {
    final recipes = await _readSubscriberRecipes();
    final created = Recipe(
      id: _newLocalId('user'),
      title: title.trim(),
      summary: summary?.trim().isEmpty ?? true ? null : summary!.trim(),
      ingredients: List<String>.from(ingredients),
      steps: List<String>.from(steps),
      imageUrl: imageUrl?.trim().isEmpty ?? true ? null : imageUrl!.trim(),
      youtubeUrl:
          youtubeUrl?.trim().isEmpty ?? true ? null : youtubeUrl!.trim(),
      notes: notes?.trim().isEmpty ?? true ? null : notes!.trim(),
      visibility: 'private',
        sourceType: sourceType?.trim().isEmpty ?? true
          ? RecipeSourceType.manual
          : sourceType!.trim(),
    );
    recipes.insert(0, created);
    await _writeSubscriberRecipes(recipes);
    return created;
  }

  @override
  Future<void> deleteSubscriberRecipe(String id) async {
    final recipes = await _readSubscriberRecipes();
    recipes.removeWhere((Recipe recipe) => recipe.id == id);
    await _writeSubscriberRecipes(recipes);
  }

  @override
  Future<Recipe?> getSubscriberRecipeById(String id) async {
    final recipes = await _readSubscriberRecipes();
    for (final recipe in recipes) {
      if (recipe.id == id) {
        return recipe;
      }
    }
    return null;
  }

  @override
  Future<List<Recipe>> listSubscriberRecipes() async {
    return _readSubscriberRecipes();
  }

  @override
  Future<Recipe> updateSubscriberRecipe({
    required String id,
    required String title,
    required List<String> ingredients,
    required List<String> steps,
    String? summary,
    String? notes,
    String? imageUrl,
    String? youtubeUrl,
  }) async {
    final recipes = await _readSubscriberRecipes();
    final index = recipes.indexWhere((Recipe recipe) => recipe.id == id);
    if (index < 0) {
      throw StateError('개인 레시피를 찾을 수 없습니다.');
    }

    final existing = recipes[index];
    final updated = Recipe(
      id: existing.id,
      title: title.trim(),
      summary: summary?.trim().isEmpty ?? true ? null : summary!.trim(),
      tips: existing.tips,
      ingredients: List<String>.from(ingredients),
      steps: List<String>.from(steps),
      imageUrl: imageUrl?.trim().isEmpty ?? true ? null : imageUrl!.trim(),
      youtubeUrl:
          youtubeUrl?.trim().isEmpty ?? true ? null : youtubeUrl!.trim(),
      notes: notes?.trim().isEmpty ?? true ? null : notes!.trim(),
      visibility: existing.visibility,
      sourceType: existing.sourceType,
    );

    recipes[index] = updated;
    await _writeSubscriberRecipes(recipes);
    return updated;
  }

  @override
  Future<Recipe> updateSubscriberRecipeNotes({
    required String id,
    required String notes,
  }) async {
    final recipe = await getSubscriberRecipeById(id);
    if (recipe == null) {
      throw StateError('개인 레시피를 찾을 수 없습니다.');
    }

    return updateSubscriberRecipe(
      id: id,
      title: recipe.title,
      summary: recipe.summary,
      ingredients: recipe.ingredients,
      steps: recipe.steps,
      notes: notes,
      imageUrl: recipe.imageUrl,
      youtubeUrl: recipe.youtubeUrl,
    );
  }

  @override
  Future<bool> isBookmarked({
    required String recipeType,
    required String recipeId,
  }) async {
    final values = await _readBookmarks();
    return values.contains('$recipeType:$recipeId');
  }

  @override
  Future<void> addBookmark({
    required String recipeType,
    required String recipeId,
  }) async {
    final values = await _readBookmarks();
    values.add('$recipeType:$recipeId');
    await _writeBookmarks(values);
  }

  @override
  Future<void> removeBookmark({
    required String recipeType,
    required String recipeId,
  }) async {
    final values = await _readBookmarks();
    values.remove('$recipeType:$recipeId');
    await _writeBookmarks(values);
  }

  @override
  Future<List<BookmarkedRecipe>> listBookmarkedRecipes() async {
    final values = await _readBookmarks();
    final localSubscribers = await _readSubscriberRecipes();
    final result = <BookmarkedRecipe>[];

    for (final value in values) {
      final split = value.split(':');
      if (split.length != 2) {
        continue;
      }
      final recipeType = split[0];
      final recipeId = split[1];

      Recipe? recipe;
      if (recipeType == 'user') {
        for (final item in localSubscribers) {
          if (item.id == recipeId) {
            recipe = item;
            break;
          }
        }
      } else if (recipeType == 'creator') {
        recipe = await _remote.getCreatorRecipeById(recipeId);
      } else {
        recipe = await _remote.getRecipeById(recipeId);
      }

      if (recipe != null) {
        result.add(BookmarkedRecipe(recipeType: recipeType, recipe: recipe));
      }
    }

    return result;
  }

  @override
  Future<Recipe> promoteSubscriberRecipeToCreator({
    required String id,
    bool deleteSource = false,
    bool includeSummary = true,
    bool includeYoutubeUrl = true,
    bool includeImageUrl = true,
    bool includeNotesAsTips = true,
  }) async {
    final recipes = await _readSubscriberRecipes();
    final index = recipes.indexWhere((Recipe recipe) => recipe.id == id);
    if (index < 0) {
      throw StateError('승격할 개인 레시피를 찾을 수 없습니다.');
    }

    final source = recipes[index];
    final creatorRecipe = await _remote.createCreatorRecipe(
      title: source.title,
      summary: includeSummary ? source.summary : null,
      ingredients: List<String>.from(source.ingredients),
      steps: List<String>.from(source.steps),
      tips: includeNotesAsTips ? source.notes : null,
      imagePath: includeImageUrl ? source.imageUrl : null,
      youtubeUrl: includeYoutubeUrl ? source.youtubeUrl : null,
    );

    await _upsertLocalCreatorRecipe(creatorRecipe);

    if (deleteSource) {
      recipes.removeAt(index);
      await _writeSubscriberRecipes(recipes);

      final bookmarks = await _readBookmarks();
      final removed = bookmarks.remove('user:$id');
      if (removed) {
        await _writeBookmarks(bookmarks);
      }
    }

    return creatorRecipe;
  }

  @override
  Future<Map<String, int>> getKitchenSummary() => _remote.getKitchenSummary();

  @override
  Future<KitchenShoppingCreateResult> createKitchenShoppingFromRecipe({
    required String recipeType,
    required Recipe recipe,
  }) {
    return _remote.createKitchenShoppingFromRecipe(
      recipeType: recipeType,
      recipe: recipe,
    );
  }

  @override
  Future<Recipe> createCreatorRecipe({
    required String title,
    String? summary,
    required List<String> ingredients,
    required List<String> steps,
    String? tips,
    String? imagePath,
    String? youtubeUrl,
  }) async {
    final created = await _remote.createCreatorRecipe(
      title: title,
      summary: summary,
      ingredients: ingredients,
      steps: steps,
      tips: tips,
      imagePath: imagePath,
      youtubeUrl: youtubeUrl,
    );
    await _upsertLocalCreatorRecipe(created);
    return created;
  }

  @override
  Future<void> deleteCreatorRecipe(String id) async {
    await _remote.deleteCreatorRecipe(id);
    await _deleteLocalCreatorRecipe(id);
  }

  @override
  Future<Recipe?> getCreatorRecipeById(String id) async {
    try {
      final remote = await _remote.getCreatorRecipeById(id);
      if (remote != null) {
        await _upsertLocalCreatorRecipe(remote);
        return remote;
      }
    } catch (_) {
      // Fall back to local cache when server fetch fails.
    }

    final creators = await _readCreatorRecipes();
    for (final recipe in creators) {
      if (recipe.id == id) {
        return recipe;
      }
    }
    return null;
  }

  @override
  Future<RecipeYoutubeMetadata?> getCreatorRecipeYoutubeMetadata(String id) {
    return _remote.getCreatorRecipeYoutubeMetadata(id);
  }

  @override
  Future<List<Recipe>> listPublicRecipes({
    String? search,
    bool useAiSearch = false,
  }) {
    return _remote.listPublicRecipes(search: search, useAiSearch: useAiSearch);
  }

  @override
  Future<List<Recipe>> listCreatorRecipes({String? search}) async {
    final normalizedSearch = (search ?? '').trim();
    final localCreators = await _readCreatorRecipes();

    try {
      final remoteCreators = await _remote.listCreatorRecipes(
        search: normalizedSearch,
      );

      final merged = <Recipe>[];
      final seen = <String>{};

      for (final recipe in remoteCreators) {
        merged.add(recipe);
        seen.add(recipe.id);
        await _upsertLocalCreatorRecipe(recipe);
      }

      for (final recipe in localCreators) {
        if (!seen.contains(recipe.id) && _matchesSearch(recipe, normalizedSearch)) {
          merged.add(recipe);
        }
      }

      return merged;
    } catch (_) {
      if (normalizedSearch.isEmpty) {
        return localCreators;
      }
      return localCreators
          .where((Recipe recipe) => _matchesSearch(recipe, normalizedSearch))
          .toList();
    }
  }

  @override
  Future<Recipe> updateCreatorRecipe({
    required String id,
    required String title,
    String? summary,
    required List<String> ingredients,
    required List<String> steps,
    String? tips,
    String? imagePath,
    String? youtubeUrl,
  }) async {
    final updated = await _remote.updateCreatorRecipe(
      id: id,
      title: title,
      summary: summary,
      ingredients: ingredients,
      steps: steps,
      tips: tips,
      imagePath: imagePath,
      youtubeUrl: youtubeUrl,
    );
    await _upsertLocalCreatorRecipe(updated);
    return updated;
  }

  @override
  Future<Recipe?> getRecipeById(String id) => _remote.getRecipeById(id);
}