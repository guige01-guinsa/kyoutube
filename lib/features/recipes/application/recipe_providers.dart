import '../../auth/application/auth_providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'recipe_image_service.dart';
import '../data/recipe_repository.dart';
import '../data/supabase_recipe_repository.dart';
import '../domain/recipe.dart';
import '../domain/recipe_search_exclusion.dart';

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
  (ref) {
    final repository = SupabaseRecipeRepository();
    ref.onDispose(repository.close);
    return repository;
  },
);

final recipeImageServiceProvider = Provider<RecipeImageService>(
  (ref) => RecipeImageService(),
);

final publicRecipesProvider =
    FutureProvider.autoDispose.family<List<Recipe>, PublicRecipeQuery>(
  (ref, PublicRecipeQuery query) async {
    final repository = ref.watch(recipeRepositoryProvider);
    final recipes = await repository.listPublicRecipes(
      search: query.search.trim().isEmpty ? null : query.search.trim(),
      useAiSearch: query.useAiSearch,
    );

    return recipes;
  },
);

final creatorRecipesProvider =
    FutureProvider.autoDispose.family<List<Recipe>, String>(
  (ref, String search) async {
    ref.watch(activeAccountIdProvider);
    final repository = ref.watch(recipeRepositoryProvider);
    return repository.listCreatorRecipes(
      search: search.trim().isEmpty ? null : search.trim(),
    );
  },
);

final creatorRecipeByIdProvider = FutureProvider.family<Recipe?, String>(
  (ref, String id) async {
    ref.watch(activeAccountIdProvider);
    final repository = ref.watch(recipeRepositoryProvider);
    return repository.getCreatorRecipeById(id);
  },
);

final subscriberRecipesProvider = FutureProvider<List<Recipe>>(
  (ref) async {
    ref.watch(activeAccountIdProvider);
    final repository = ref.watch(recipeRepositoryProvider);
    return repository.listSubscriberRecipes();
  },
);

final subscriberRecipeByIdProvider = FutureProvider.family<Recipe?, String>(
  (ref, String id) async {
    ref.watch(activeAccountIdProvider);
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

final recipeSearchExclusionsProvider =
    FutureProvider<List<RecipeSearchExclusion>>(
  (ref) async {
    ref.watch(activeAccountIdProvider);
    final repository = ref.watch(recipeRepositoryProvider);
    return repository.listRecipeSearchExclusions();
  },
);

final kitchenSummaryProvider = FutureProvider<Map<String, int>>(
  (ref) async {
    ref.watch(activeAccountIdProvider);
    final repository = ref.watch(recipeRepositoryProvider);
    return repository.getKitchenSummary();
  },
);
