import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:k_youtube/features/recipes/data/local_first_recipe_repository.dart';
import 'package:k_youtube/features/recipes/data/recipe_repository.dart';
import 'package:k_youtube/features/recipes/domain/bookmarked_recipe.dart';
import 'package:k_youtube/features/recipes/domain/recipe.dart';
import 'package:k_youtube/features/recipes/domain/youtube_metadata.dart';

class _NoopRemoteRepository implements RecipeRepository {
  @override
  Future<void> addBookmark({
    required String recipeType,
    required String recipeId,
  }) async {}

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
    throw UnimplementedError();
  }

  @override
  Future<KitchenShoppingCreateResult> createKitchenShoppingFromRecipe({
    required String recipeType,
    required Recipe recipe,
  }) async {
    return const KitchenShoppingCreateResult(missingCount: 0);
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
    throw UnimplementedError();
  }

  @override
  Future<Recipe> createSubscriberRecipeFromPublic({
    required Recipe source,
    String? notes,
  }) async {
    throw UnimplementedError();
  }

  @override
  Future<void> deleteCreatorRecipe(String id) async {}

  @override
  Future<void> deleteSubscriberRecipe(String id) async {}

  @override
  Future<Recipe?> getCreatorRecipeById(String id) async {
    return Recipe(
      id: id,
      title: 'creator-$id',
      ingredients: const <String>['x'],
      steps: const <String>['y'],
    );
  }

  @override
  Future<RecipeYoutubeMetadata?> getCreatorRecipeYoutubeMetadata(String id) async {
    return null;
  }

  @override
  Future<Map<String, int>> getKitchenSummary() async {
    return const <String, int>{};
  }

  @override
  Future<Recipe?> getRecipeById(String id) async {
    return Recipe(
      id: id,
      title: 'public-$id',
      ingredients: const <String>['x'],
      steps: const <String>['y'],
    );
  }

  @override
  Future<Recipe?> getSubscriberRecipeById(String id) async {
    throw UnimplementedError();
  }

  @override
  Future<bool> isBookmarked({
    required String recipeType,
    required String recipeId,
  }) async {
    return false;
  }

  @override
  Future<List<BookmarkedRecipe>> listBookmarkedRecipes() async {
    return const <BookmarkedRecipe>[];
  }

  @override
  Future<List<Recipe>> listCreatorRecipes({String? search}) async {
    return const <Recipe>[];
  }

  @override
  Future<List<Recipe>> listPublicRecipes({
    String? search,
    bool useAiSearch = false,
  }) async {
    return const <Recipe>[];
  }

  @override
  Future<List<Recipe>> listSubscriberRecipes() async {
    throw UnimplementedError();
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
    throw UnimplementedError();
  }

  @override
  Future<void> removeBookmark({
    required String recipeType,
    required String recipeId,
  }) async {}

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
    throw UnimplementedError();
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
    throw UnimplementedError();
  }

  @override
  Future<Recipe> updateSubscriberRecipeNotes({
    required String id,
    required String notes,
  }) async {
    throw UnimplementedError();
  }
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  test('subscriber recipe CRUD persists in local storage', () async {
    final repo = LocalFirstRecipeRepository(remote: _NoopRemoteRepository());

    final created = await repo.createSubscriberRecipe(
      title: '김치볶음밥',
      ingredients: const <String>['밥', '김치'],
      steps: const <String>['볶는다'],
      notes: '맵게',
    );

    expect(created.id, isNotEmpty);

    final listed = await repo.listSubscriberRecipes();
    expect(listed.length, 1);
    expect(listed.first.title, '김치볶음밥');

    final updated = await repo.updateSubscriberRecipe(
      id: created.id,
      title: '참치김치볶음밥',
      ingredients: const <String>['밥', '김치', '참치'],
      steps: const <String>['볶는다'],
      notes: '중간매운맛',
    );

    expect(updated.title, '참치김치볶음밥');

    final reloadedRepo =
        LocalFirstRecipeRepository(remote: _NoopRemoteRepository());
    final afterReload = await reloadedRepo.getSubscriberRecipeById(created.id);

    expect(afterReload, isNotNull);
    expect(afterReload!.title, '참치김치볶음밥');

    await reloadedRepo.deleteSubscriberRecipe(created.id);
    final afterDelete = await reloadedRepo.listSubscriberRecipes();
    expect(afterDelete, isEmpty);
  });

  test('user bookmark can be listed from local recipes', () async {
    final repo = LocalFirstRecipeRepository(remote: _NoopRemoteRepository());

    final created = await repo.createSubscriberRecipe(
      title: '된장찌개',
      ingredients: const <String>['된장', '두부'],
      steps: const <String>['끓인다'],
    );

    await repo.addBookmark(recipeType: 'user', recipeId: created.id);

    final bookmarked = await repo.listBookmarkedRecipes();
    expect(bookmarked.length, 1);
    expect(bookmarked.first.recipeType, 'user');
    expect(bookmarked.first.recipe.id, created.id);
  });
}
