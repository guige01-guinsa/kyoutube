import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:youtube_recipe_search/youtube_recipe_search.dart';

import '../../recipes/application/recipe_providers.dart';
import '../../recipes/domain/recipe.dart';
import '../../youtube/data/supabase_youtube_search_transport.dart';

typedef PublicRecipeSearch = Future<List<Recipe>> Function(String query);
typedef ExcludedRecipeKeysLoader = Future<Set<String>> Function();
typedef _YoutubeSearchOutcome = ({
  List<YoutubeSearchResult> recipes,
  Object? error,
});
typedef _PublicSearchOutcome = ({
  List<Recipe> recipes,
  Object? error,
});

class RecommendedRecipeSearchResult {
  const RecommendedRecipeSearchResult({
    required this.query,
    required this.youtubeRecipes,
    required this.publicRecipes,
    this.youtubeError,
    this.publicRecipeError,
  });

  final String query;
  final List<YoutubeSearchResult> youtubeRecipes;
  final List<Recipe> publicRecipes;
  final Object? youtubeError;
  final Object? publicRecipeError;

  int get resultCount => youtubeRecipes.length + publicRecipes.length;
}

class RecommendedRecipeSearchService {
  RecommendedRecipeSearchService({
    required YoutubeSearchRepository youtubeRepository,
    required PublicRecipeSearch publicRecipeSearch,
    ExcludedRecipeKeysLoader? excludedRecipeKeysLoader,
  })  : _youtubeRepository = youtubeRepository,
        _publicRecipeSearch = publicRecipeSearch,
        _excludedRecipeKeysLoader =
            excludedRecipeKeysLoader ?? _emptyExcludedRecipeKeys;

  static const int maximumResultsPerSource = 10;
  static final RegExp _singleKoreanSyllable = RegExp(r'^[가-힣]$');

  final YoutubeSearchRepository _youtubeRepository;
  final PublicRecipeSearch _publicRecipeSearch;
  final ExcludedRecipeKeysLoader _excludedRecipeKeysLoader;

  static Future<Set<String>> _emptyExcludedRecipeKeys() async => <String>{};

  Future<RecommendedRecipeSearchResult> search(String rawQuery) async {
    final query = rawQuery.trim();
    if (query.isEmpty) {
      throw ArgumentError.value(rawQuery, 'rawQuery', '검색어가 필요합니다.');
    }

    final searchQueries = _expandSearchQueries(query);
    final youtubeFuture = _searchYoutube(searchQueries);
    final publicFuture = _searchPublicRecipes(searchQueries);
    final excludedKeysFuture = _loadExcludedRecipeKeys();
    final youtubeOutcome = await youtubeFuture;
    final publicOutcome = await publicFuture;
    final excludedKeys = await excludedKeysFuture;

    return RecommendedRecipeSearchResult(
      query: query,
      youtubeRecipes: youtubeOutcome.recipes
          .where(
              (recipe) => !excludedKeys.contains('youtube:${recipe.videoId}'))
          .toList(growable: false),
      publicRecipes: publicOutcome.recipes
          .where((recipe) => !excludedKeys.contains('public:${recipe.id}'))
          .toList(growable: false),
      youtubeError: youtubeOutcome.error,
      publicRecipeError: publicOutcome.error,
    );
  }

  Future<Set<String>> _loadExcludedRecipeKeys() async {
    try {
      return await _excludedRecipeKeysLoader();
    } catch (_) {
      return <String>{};
    }
  }

  List<String> _expandSearchQueries(String query) {
    if (_singleKoreanSyllable.hasMatch(query)) {
      return <String>['$query요리', '$query 레시피'];
    }
    return <String>[query];
  }

  Future<_YoutubeSearchOutcome> _searchYoutube(List<String> queries) async {
    final outcomes = await Future.wait(
      queries.map(_searchYoutubeQuery),
    );
    final recipes = <YoutubeSearchResult>[];
    final seenVideoIds = <String>{};
    Object? firstError;

    for (final outcome in outcomes) {
      firstError ??= outcome.error;
      for (final recipe in outcome.recipes) {
        if (seenVideoIds.add(recipe.videoId)) {
          recipes.add(recipe);
        }
      }
    }

    return (
      recipes: recipes.take(maximumResultsPerSource).toList(growable: false),
      error: firstError,
    );
  }

  Future<_YoutubeSearchOutcome> _searchYoutubeQuery(String query) async {
    try {
      final page = await _youtubeRepository.search(
        YoutubeSearchRequest(query: query, limit: maximumResultsPerSource),
      );
      return (
        recipes: page.items.take(maximumResultsPerSource).toList(),
        error: null,
      );
    } catch (error) {
      return (recipes: const <YoutubeSearchResult>[], error: error);
    }
  }

  Future<_PublicSearchOutcome> _searchPublicRecipes(
    List<String> queries,
  ) async {
    final outcomes = await Future.wait(
      queries.map(_searchPublicRecipesQuery),
    );
    final recipes = <Recipe>[];
    final seenRecipeIds = <String>{};
    Object? firstError;

    for (final outcome in outcomes) {
      firstError ??= outcome.error;
      for (final recipe in outcome.recipes) {
        if (seenRecipeIds.add(recipe.id)) {
          recipes.add(recipe);
        }
      }
    }

    return (
      recipes: recipes.take(maximumResultsPerSource).toList(growable: false),
      error: firstError,
    );
  }

  Future<_PublicSearchOutcome> _searchPublicRecipesQuery(String query) async {
    try {
      return (
        recipes: (await _publicRecipeSearch(query))
            .take(maximumResultsPerSource)
            .toList(growable: false),
        error: null,
      );
    } catch (error) {
      return (recipes: const <Recipe>[], error: error);
    }
  }
}

final recommendedRecipeSearchServiceProvider =
    Provider<RecommendedRecipeSearchService>((ref) {
  final recipeRepository = ref.watch(recipeRepositoryProvider);
  final youtubeTransport = SupabaseYoutubeSearchTransport();
  ref.onDispose(youtubeTransport.close);

  return RecommendedRecipeSearchService(
    youtubeRepository: YoutubeSearchClient(
      youtubeTransport,
    ),
    publicRecipeSearch: (String query) => recipeRepository.listPublicRecipes(
      search: query,
      useAiSearch: true,
    ),
    excludedRecipeKeysLoader: recipeRepository.listExcludedRecipeSourceKeys,
  );
});
