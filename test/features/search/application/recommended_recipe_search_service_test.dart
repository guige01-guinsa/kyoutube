import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:k_youtube/features/recipes/domain/recipe.dart';
import 'package:k_youtube/features/search/application/recommended_recipe_search_service.dart';
import 'package:youtube_recipe_search/youtube_recipe_search.dart';

class _FakeYoutubeRepository implements YoutubeSearchRepository {
  _FakeYoutubeRepository({
    this.items = const <YoutubeSearchResult>[],
    this.error,
  });

  final List<YoutubeSearchResult> items;
  final Object? error;
  final List<String> queries = <String>[];

  @override
  Future<YoutubeSearchPage> search(YoutubeSearchRequest request) async {
    queries.add(request.query);
    if (error != null) {
      throw error!;
    }
    return YoutubeSearchPage(items: items, nextPageToken: null);
  }
}

class _BlockingYoutubeRepository implements YoutubeSearchRepository {
  _BlockingYoutubeRepository({
    required this.onStarted,
    required this.release,
  });

  final void Function() onStarted;
  final Future<void> release;

  @override
  Future<YoutubeSearchPage> search(YoutubeSearchRequest request) async {
    onStarted();
    await release;
    return const YoutubeSearchPage(
      items: <YoutubeSearchResult>[],
      nextPageToken: null,
    );
  }
}

YoutubeSearchResult _youtubeResult(int index) {
  return YoutubeSearchResult(
    videoId: 'video-$index',
    title: '영상 레시피 $index',
    channelTitle: '요리 채널',
    publishedAt: null,
    thumbnailUrl: 'https://example.com/video-$index.jpg',
    youtubeUrl: 'https://youtu.be/video-$index',
    durationSec: 120,
  );
}

Recipe _publicRecipe(int index) {
  return Recipe(
    id: 'public-$index',
    title: '공공 레시피 $index',
    ingredients: const <String>['재료'],
    steps: const <String>['조리'],
    imageUrl: 'https://example.com/public-$index.jpg',
  );
}

void main() {
  test('starts YouTube and public searches concurrently', () async {
    final youtubeStarted = Completer<void>();
    final releaseYoutube = Completer<void>();
    var publicStartedBeforeYoutubeFinished = false;
    final service = RecommendedRecipeSearchService(
      youtubeRepository: _BlockingYoutubeRepository(
        onStarted: () => youtubeStarted.complete(),
        release: releaseYoutube.future,
      ),
      publicRecipeSearch: (String query) async {
        publicStartedBeforeYoutubeFinished = !releaseYoutube.isCompleted;
        return const <Recipe>[];
      },
    );

    final search = service.search('파스타');
    await youtubeStarted.future;
    await Future<void>.delayed(Duration.zero);
    expect(publicStartedBeforeYoutubeFinished, isTrue);
    releaseYoutube.complete();
    await search;
  });

  test('YouTube and public recipes are always searched together', () async {
    var publicSearchCalls = 0;
    final service = RecommendedRecipeSearchService(
      youtubeRepository: _FakeYoutubeRepository(
        items: List<YoutubeSearchResult>.generate(6, _youtubeResult),
      ),
      publicRecipeSearch: (String query) async {
        publicSearchCalls += 1;
        return List<Recipe>.generate(10, _publicRecipe);
      },
    );

    final result = await service.search('김치찌개');

    expect(result.youtubeRecipes, hasLength(6));
    expect(result.publicRecipes, hasLength(10));
    expect(result.resultCount, 16);
    expect(publicSearchCalls, 1);
  });

  test('expands a single Korean syllable into cooking searches', () async {
    final youtubeRepository = _FakeYoutubeRepository();
    final publicQueries = <String>[];
    final service = RecommendedRecipeSearchService(
      youtubeRepository: youtubeRepository,
      publicRecipeSearch: (String query) async {
        publicQueries.add(query);
        return const <Recipe>[];
      },
    );

    final result = await service.search(' 면 ');

    expect(result.query, '면');
    expect(youtubeRepository.queries, <String>['면요리', '면 레시피']);
    expect(publicQueries, <String>['면요리', '면 레시피']);
  });

  test('does not expand multi-syllable or non-Korean searches', () async {
    final youtubeRepository = _FakeYoutubeRepository();
    final publicQueries = <String>[];
    final service = RecommendedRecipeSearchService(
      youtubeRepository: youtubeRepository,
      publicRecipeSearch: (String query) async {
        publicQueries.add(query);
        return const <Recipe>[];
      },
    );

    await service.search('죽밥');
    await service.search('a');

    expect(youtubeRepository.queries, <String>['죽밥', 'a']);
    expect(publicQueries, <String>['죽밥', 'a']);
  });

  test('deduplicates results returned by expanded searches', () async {
    final duplicateYoutube = _youtubeResult(1);
    final duplicatePublic = _publicRecipe(1);
    final service = RecommendedRecipeSearchService(
      youtubeRepository: _FakeYoutubeRepository(
        items: <YoutubeSearchResult>[duplicateYoutube],
      ),
      publicRecipeSearch: (String query) async => <Recipe>[duplicatePublic],
    );

    final result = await service.search('죽');

    expect(result.youtubeRecipes, <YoutubeSearchResult>[duplicateYoutube]);
    expect(result.publicRecipes, <Recipe>[duplicatePublic]);
  });

  test('filters sources saved in the search exclusion list', () async {
    final service = RecommendedRecipeSearchService(
      youtubeRepository: _FakeYoutubeRepository(
        items: List<YoutubeSearchResult>.generate(2, _youtubeResult),
      ),
      publicRecipeSearch: (String query) async =>
          List<Recipe>.generate(2, _publicRecipe),
      excludedRecipeKeysLoader: () async => <String>{
        'youtube:video-0',
        'public:public-1',
      },
    );

    final result = await service.search('국수');

    expect(
        result.youtubeRecipes.map((item) => item.videoId), <String>['video-1']);
    expect(result.publicRecipes.map((item) => item.id), <String>['public-0']);
  });

  test('keeps up to ten results from each source', () async {
    final service = RecommendedRecipeSearchService(
      youtubeRepository: _FakeYoutubeRepository(
        items: List<YoutubeSearchResult>.generate(3, _youtubeResult),
      ),
      publicRecipeSearch: (String query) async =>
          List<Recipe>.generate(10, _publicRecipe),
    );

    final result = await service.search('두부');

    expect(result.youtubeRecipes, hasLength(3));
    expect(result.publicRecipes, hasLength(10));
    expect(result.resultCount, 13);
  });

  test('YouTube failure falls back to public recipes', () async {
    final service = RecommendedRecipeSearchService(
      youtubeRepository: _FakeYoutubeRepository(
        error: const YoutubeSearchException('youtube_transport_error'),
      ),
      publicRecipeSearch: (String query) async =>
          List<Recipe>.generate(10, _publicRecipe),
    );

    final result = await service.search('비빔밥');

    expect(result.youtubeRecipes, isEmpty);
    expect(result.publicRecipes, hasLength(10));
    expect(result.youtubeError, isA<YoutubeSearchException>());
  });
}
