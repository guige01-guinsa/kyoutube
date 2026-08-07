import '../domain/recipe.dart';
import '../domain/bookmarked_recipe.dart';

abstract class RecipeRepository {
  Future<Map<String, int>> getKitchenSummary();
  Future<Recipe> createSubscriberRecipeFromPublic({
    required Recipe source,
    String? notes,
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
  Future<Recipe> updateSubscriberRecipeNotes({
    required String id,
    required String notes,
  });
}
