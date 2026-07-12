import '../domain/recipe.dart';

abstract class RecipeRepository {
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
  Future<Recipe?> getCreatorRecipeById(String id);
  Future<List<Recipe>> listPublicRecipes();
  Future<List<Recipe>> listCreatorRecipes();
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
}
