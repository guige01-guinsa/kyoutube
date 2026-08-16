import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/default_unified_recipe_repository.dart';
import '../domain/recipe_identity.dart';
import '../domain/unified_recipe.dart';
import '../domain/unified_recipe_repository.dart';
import 'recipe_providers.dart';

final unifiedRecipeRepositoryProvider =
    Provider<UnifiedRecipeRepository>((ref) {
  final recipeRepository = ref.watch(recipeRepositoryProvider);

  return DefaultUnifiedRecipeRepository(recipeRepository);
});

final unifiedRecipeByIdentityProvider =
    FutureProvider.family<UnifiedRecipe?, RecipeIdentity>(
  (ref, RecipeIdentity identity) async {
    final repository = ref.watch(unifiedRecipeRepositoryProvider);

    return repository.getRecipe(identity);
  },
);

final myUnifiedRecipesProvider =
    FutureProvider.family<List<UnifiedRecipe>, String>(
  (ref, String search) async {
    final repository = ref.watch(unifiedRecipeRepositoryProvider);

    return repository.listMyRecipes(
      search: search.trim().isEmpty ? null : search.trim(),
    );
  },
);
