import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'recipe_image_service.dart';
import '../data/recipe_repository.dart';
import '../data/supabase_recipe_repository.dart';
import '../domain/bookmarked_recipe.dart';
import '../domain/recipe.dart';

class PublicRecipeQuery {
  const PublicRecipeQuery({
    required this.search,
    required this.useAiSearch,
  });

  final String search;
  final bool useAiSearch;

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) {
      return true;
    }

    return other is PublicRecipeQuery &&
        other.search == search &&
        other.useAiSearch == useAiSearch;
  }

  @override
  int get hashCode => Object.hash(search, useAiSearch);
}

final recipeRepositoryProvider = Provider<RecipeRepository>(
  (ref) => SupabaseRecipeRepository(),
);

final recipeImageServiceProvider = Provider<RecipeImageService>(
  (ref) => RecipeImageService(),
);

final publicRecipesProvider =
    FutureProvider.family<List<Recipe>, PublicRecipeQuery>(
  (ref, PublicRecipeQuery query) async {
    final repository = ref.watch(recipeRepositoryProvider);
    final recipes = await repository.listPublicRecipes(
      search: query.search.trim().isEmpty ? null : query.search.trim(),
      useAiSearch: query.useAiSearch,
    );

    return recipes;
  },
);

final creatorRecipesProvider = FutureProvider.family<List<Recipe>, String>(
  (ref, String search) async {
    final repository = ref.watch(recipeRepositoryProvider);
    return repository.listCreatorRecipes(
      search: search.trim().isEmpty ? null : search.trim(),
    );
  },
);

final creatorRecipeByIdProvider = FutureProvider.family<Recipe?, String>(
  (ref, String id) async {
    final repository = ref.watch(recipeRepositoryProvider);
    return repository.getCreatorRecipeById(id);
  },
);

final subscriberRecipesProvider = FutureProvider<List<Recipe>>(
  (ref) async {
    final repository = ref.watch(recipeRepositoryProvider);
    return repository.listSubscriberRecipes();
  },
);

final subscriberRecipeByIdProvider = FutureProvider.family<Recipe?, String>(
  (ref, String id) async {
    final repository = ref.watch(recipeRepositoryProvider);
    return repository.getSubscriberRecipeById(id);
  },
);

final recipeByIdProvider = FutureProvider.family<Recipe?, String>(
  (ref, String id) async {
    final repository = ref.watch(recipeRepositoryProvider);
    return repository.getRecipeById(id);
  },
);

final bookmarkedRecipesProvider = FutureProvider<List<BookmarkedRecipe>>(
  (ref) async {
    final repository = ref.watch(recipeRepositoryProvider);
    return repository.listBookmarkedRecipes();
  },
);

final kitchenSummaryProvider = FutureProvider<Map<String, int>>(
  (ref) async {
    final repository = ref.watch(recipeRepositoryProvider);
    return repository.getKitchenSummary();
  },
);
