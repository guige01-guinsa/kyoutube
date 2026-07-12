import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'recipe_image_service.dart';
import '../data/recipe_repository.dart';
import '../data/supabase_recipe_repository.dart';
import '../domain/recipe.dart';

final recipeRepositoryProvider = Provider<RecipeRepository>(
  (ref) => SupabaseRecipeRepository(),
);

final recipeImageServiceProvider = Provider<RecipeImageService>(
  (ref) => RecipeImageService(),
);

final publicRecipesProvider = FutureProvider<List<Recipe>>(
  (ref) async {
    final repository = ref.watch(recipeRepositoryProvider);
    final recipes = await repository.listPublicRecipes();

    if (recipes.isEmpty) {
      return <Recipe>[
        Recipe(
          id: 'sample-1',
          title: '두부 스테이크',
          summary: '담백하고 단백질이 풍부한 한 접시',
          ingredients: <String>['두부 1모', '양파 1/2개', '간장 1큰술'],
          steps: <String>['두부 물기 제거', '재료 혼합 후 굽기', '소스 뿌려 완성'],
        ),
      ];
    }

    return recipes;
  },
);

final creatorRecipesProvider = FutureProvider<List<Recipe>>(
  (ref) async {
    final repository = ref.watch(recipeRepositoryProvider);
    return repository.listCreatorRecipes();
  },
);

final creatorRecipeByIdProvider = FutureProvider.family<Recipe?, String>(
  (ref, String id) async {
    final repository = ref.watch(recipeRepositoryProvider);
    return repository.getCreatorRecipeById(id);
  },
);

final recipeByIdProvider = FutureProvider.family<Recipe?, String>(
  (ref, String id) async {
    final repository = ref.watch(recipeRepositoryProvider);
    return repository.getRecipeById(id);
  },
);
