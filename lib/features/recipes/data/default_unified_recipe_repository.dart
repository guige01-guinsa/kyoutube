import '../domain/recipe_identity.dart';
import '../domain/unified_recipe.dart';
import '../domain/unified_recipe_repository.dart';
import 'recipe_repository.dart';
import 'unified_recipe_mappers.dart';

class DefaultUnifiedRecipeRepository implements UnifiedRecipeRepository {
  const DefaultUnifiedRecipeRepository(this._recipeRepository);

  final RecipeRepository _recipeRepository;

  @override
  Future<UnifiedRecipe?> getRecipe(RecipeIdentity identity) async {
    final recipe = switch (identity.sourceType) {
      'public' => await _recipeRepository.getRecipeById(identity.sourceId),
      'creator' =>
        await _recipeRepository.getCreatorRecipeById(identity.sourceId),
      'user' =>
        await _recipeRepository.getSubscriberRecipeById(identity.sourceId),
      _ => null,
    };

    if (recipe == null) {
      return null;
    }

    return mapRecipeToUnifiedRecipe(
      recipe: recipe,
      identity: identity,
    );
  }
}
