import '../domain/recipe.dart';
import '../domain/bookmarked_recipe.dart';
import '../domain/youtube_metadata.dart';

class KitchenShoppingCreateResult {
  const KitchenShoppingCreateResult({
    required this.missingCount,
    this.reusedActiveList = false,
    this.reopenedFromCompleted = false,
    this.resetFromFullyChecked = false,
    this.noMissingItems = false,
  });

  final int missingCount;
  final bool reusedActiveList;
  final bool reopenedFromCompleted;
  final bool resetFromFullyChecked;
  final bool noMissingItems;
}

abstract class RecipeRepository {
  Future<Map<String, int>> getKitchenSummary();
  Future<KitchenShoppingCreateResult> createKitchenShoppingFromRecipe({
    required String recipeType,
    required Recipe recipe,
  });
  Future<Recipe> createSubscriberRecipeFromPublic({
    required Recipe source,
    String? notes,
  });
  Future<Recipe> createSubscriberRecipe({
    required String title,
    required List<String> ingredients,
    required List<String> steps,
    String? summary,
    String? notes,
    String? imageUrl,
    String? youtubeUrl,
    String? sourceType,
  });
  Future<Recipe> createCreatorRecipe({
    required String title,
    String? summary,
    required List<String> ingredients,
    required List<String> steps,
    String? tips,
    String? imagePath,
    String? youtubeUrl,
  });
  Future<void> deleteCreatorRecipe(String id);
  Future<void> deleteSubscriberRecipe(String id);
  Future<Recipe?> getCreatorRecipeById(String id);
  Future<RecipeYoutubeMetadata?> getCreatorRecipeYoutubeMetadata(String id);
  Future<Recipe?> getSubscriberRecipeById(String id);
  Future<bool> isBookmarked({required String recipeType, required String recipeId});
  Future<void> addBookmark({required String recipeType, required String recipeId});
  Future<void> removeBookmark({required String recipeType, required String recipeId});
  Future<List<BookmarkedRecipe>> listBookmarkedRecipes();
  Future<List<Recipe>> listPublicRecipes({
    String? search,
    bool useAiSearch,
  });
  Future<List<Recipe>> listCreatorRecipes({String? search});
  Future<List<Recipe>> listSubscriberRecipes();
  Future<Recipe> updateCreatorRecipe({
    required String id,
    required String title,
    String? summary,
    required List<String> ingredients,
    required List<String> steps,
    String? tips,
    String? imagePath,
    String? youtubeUrl,
  });
  Future<Recipe?> getRecipeById(String id);
  Future<Recipe> updateSubscriberRecipe({
    required String id,
    required String title,
    required List<String> ingredients,
    required List<String> steps,
    String? summary,
    String? notes,
    String? imageUrl,
    String? youtubeUrl,
  });
  Future<Recipe> updateSubscriberRecipeNotes({
    required String id,
    required String notes,
  });
  Future<Recipe> promoteSubscriberRecipeToCreator({
    required String id,
    bool deleteSource,
    bool includeSummary,
    bool includeYoutubeUrl,
    bool includeImageUrl,
    bool includeNotesAsTips,
  });
}
