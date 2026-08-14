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
