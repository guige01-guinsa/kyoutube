import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'recipe_network_fallback.dart';
import 'recipe_image_service.dart';
import '../data/local_first_recipe_repository.dart';
import '../data/local_recipe_backup_service.dart';
import '../data/local_sync_beta_service.dart';
import '../data/local_youtube_metadata_override_service.dart';
import '../data/recipe_repository.dart';
import '../domain/bookmarked_recipe.dart';
import '../domain/recipe.dart';
import '../domain/youtube_metadata.dart';

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
  (ref) => LocalFirstRecipeRepository(),
);

final localRecipeBackupServiceProvider = Provider<LocalRecipeBackupService>(
  (ref) => const LocalRecipeBackupService(),
);

final localSyncBetaServiceProvider = Provider<LocalSyncBetaService>(
  (ref) => const LocalSyncBetaService(),
);

final localSyncBetaStatusProvider = FutureProvider<LocalSyncBetaStatus>(
  (ref) async {
    final service = ref.watch(localSyncBetaServiceProvider);
    return service.getStatus();
  },
);

final localYoutubeMetadataOverrideServiceProvider =
    Provider<LocalYoutubeMetadataOverrideService>(
  (ref) => const LocalYoutubeMetadataOverrideService(),
);

final creatorYoutubeMetadataOverrideProvider =
    FutureProvider.family<CreatorYoutubeMetadataOverride?, String>(
  (ref, String id) async {
    final service = ref.watch(localYoutubeMetadataOverrideServiceProvider);
    return service.getForRecipe(id);
  },
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

final creatorRecipeYoutubeMetadataProvider =
    FutureProvider.family<RecipeYoutubeMetadata?, String>(
  (ref, String id) async {
    final repository = ref.watch(recipeRepositoryProvider);
    try {
      return repository.getCreatorRecipeYoutubeMetadata(id);
    } catch (_) {
      return null;
    }
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

final publicRecipesFallbackProvider =
    FutureProvider.family<RecipeFetchResult<List<Recipe>>, PublicRecipeQuery>(
  (ref, PublicRecipeQuery query) async {
    final repository = ref.watch(recipeRepositoryProvider);
    final result = await RecipeNetworkFallbackService.fetchPublicRecipes(
      repository: repository,
      search: query.search,
      useAiSearch: query.useAiSearch,
    );

    if (result.data.isEmpty) {
      return RecipeFetchResult<List<Recipe>>(
        data: <Recipe>[
          Recipe(
            id: 'sample-1',
            title: '두부 스테이크',
            summary: '담백하고 단백질이 풍부한 한 접시',
            ingredients: <String>['두부 1모', '양파 1/2개', '간장 1큰술'],
            steps: <String>['두부 물기 제거', '재료 혼합 후 굽기', '소스 뿌려 완성'],
          ),
        ],
        fromCache: result.fromCache,
        fetchedAt: result.fetchedAt,
        isStale: result.isStale,
        networkErrorMessage: result.networkErrorMessage,
      );
    }

    return result;
  },
);

final publicRecipeDetailFallbackProvider =
    FutureProvider.family<RecipeFetchResult<Recipe?>, String>(
  (ref, String id) async {
    final repository = ref.watch(recipeRepositoryProvider);
    return RecipeNetworkFallbackService.fetchPublicRecipeDetail(
      repository: repository,
      id: id,
    );
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
