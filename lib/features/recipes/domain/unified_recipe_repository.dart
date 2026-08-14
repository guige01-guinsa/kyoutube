import 'recipe_identity.dart';
import 'unified_recipe.dart';

abstract interface class UnifiedRecipeRepository {
  Future<UnifiedRecipe?> getRecipe(RecipeIdentity identity);
}
