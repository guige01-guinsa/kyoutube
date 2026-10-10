import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:k_youtube/app.dart';
import 'package:k_youtube/core/router/app_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:k_youtube/core/ops/ops_monitor_service.dart';
import 'package:k_youtube/features/recipes/application/recipe_providers.dart';
import 'package:k_youtube/features/recipes/data/recipe_repository.dart';
import 'package:k_youtube/features/recipes/domain/recipe.dart';
import 'package:k_youtube/features/recipes/domain/recipe_search_exclusion.dart';
import 'package:k_youtube/features/recipes/presentation/creator_recipe_detail_page.dart';
import 'package:k_youtube/features/recipes/presentation/recipe_detail_page.dart';
import 'package:k_youtube/features/recipes/presentation/recipe_search_exclusions_page.dart';
import 'package:k_youtube/features/home/presentation/home_page.dart';
import 'package:k_youtube/features/search/application/recommended_recipe_search_service.dart';
import 'package:k_youtube/features/search/presentation/recommended_recipe_search_page.dart';
import 'package:youtube_recipe_search/youtube_recipe_search.dart';

class _EmptyYoutubeRepository implements YoutubeSearchRepository {
  @override
  Future<YoutubeSearchPage> search(YoutubeSearchRequest request) async {
    return const YoutubeSearchPage(
      items: <YoutubeSearchResult>[],
      nextPageToken: null,
    );
  }
}

class _AuthRequiredYoutubeRepository implements YoutubeSearchRepository {
  @override
  Future<YoutubeSearchPage> search(YoutubeSearchRequest request) {
    throw const YoutubeSearchException('youtube_auth_required',
        httpStatus: 401);
  }
}

class _FakeRecipeRepository implements RecipeRepository {
  @override
  Future<Recipe> createSubscriberRecipeFromPublic({
    required Recipe source,
    String? notes,
  }) async {
    return Recipe(
      id: 'subscriber-created-id',
      title: source.title,
      ingredients: source.ingredients,
      steps: source.steps,
      notes: notes,
      visibility: 'private',
    );
  }

  @override
  Future<Recipe> createCreatorRecipe({
    required String title,
    String? summary,
    required List<String> ingredients,
    required List<String> steps,
    String? tips,
    String? imagePath,
    String? youtubeUrl,
    Map<String, dynamic> contentStyles = const <String, dynamic>{},
  }) async {
    return Recipe(
      id: 'created-test-id',
      title: title,
      summary: summary,
      ingredients: ingredients,
      steps: steps,
      tips: tips,
      youtubeUrl: youtubeUrl,
      contentStyles: contentStyles,
    );
  }

  @override
  Future<void> deleteCreatorRecipe(String id) async {}

  @override
  Future<Recipe> promoteSubscriberRecipeToCreator({
    required String id,
  }) async {
    return Recipe(
      id: 'promoted-$id',
      title: '승격된 테스트 레시피',
      summary: '테스트용 편집 가능한 내 레시피',
      ingredients: const <String>['테스트 재료'],
      steps: const <String>['테스트 조리 단계'],
      tips: '테스트 팁',
    );
  }

  @override
  Future<void> deleteSubscriberRecipe(String id) async {}

  @override
  Future<void> deleteRecipeSearchExclusion(String id) async {}

  @override
  Future<void> excludeRecipeFromSearch({
    required String sourceType,
    required String sourceId,
    required String title,
    String? summary,
    List<String> ingredients = const <String>[],
    List<String> steps = const <String>[],
    String? imageUrl,
    String? youtubeUrl,
    List<String> reasonCodes = const <String>['user_hidden'],
    String status = 'hidden',
  }) async {}

  @override
  Future<Recipe?> getCreatorRecipeById(String id) async {
    return Recipe(
      id: id,
      title: '내 레시피 테스트',
      ingredients: <String>['재료'],
      steps: <String>['순서'],
      tips: '테스트 팁',
    );
  }

  @override
  Future<Recipe?> getRecipeById(String id) async {
    return Recipe(
      id: id,
      title: '상세 레시피',
      ingredients: <String>['재료'],
      steps: <String>['순서'],
    );
  }

  @override
  Future<Recipe?> getSubscriberRecipeById(String id) async {
    return Recipe(
      id: id,
      title: '내 요리 노트',
      ingredients: <String>['재료'],
      steps: <String>['순서'],
      notes: '메모',
      visibility: 'private',
    );
  }

  @override
  Future<List<Recipe>> listCreatorRecipes({String? search}) async {
    return <Recipe>[
      Recipe(
        id: 'creator-test-id',
        title: '내 레시피 테스트',
        ingredients: <String>['재료'],
        steps: <String>['순서'],
        tips: '테스트 팁',
      ),
    ];
  }

  @override
  Future<List<Recipe>> listPublicRecipes({
    String? search,
    bool useAiSearch = false,
  }) async {
    return <Recipe>[
      Recipe(
        id: 'test-id',
        title: search == null || search.isEmpty ? '테스트 레시피' : '검색 결과: $search',
        ingredients: <String>['재료'],
        steps: <String>['순서'],
      ),
    ];
  }

  @override
  Future<List<Recipe>> listSubscriberRecipes() async {
    return <Recipe>[
      Recipe(
        id: 'subscriber-test-id',
        title: '내 요리 노트',
        ingredients: <String>['재료'],
        steps: <String>['순서'],
        notes: '메모',
        visibility: 'private',
      ),
    ];
  }

  @override
  Future<Set<String>> listExcludedRecipeSourceKeys() async => <String>{};

  @override
  Future<List<RecipeSearchExclusion>> listRecipeSearchExclusions() async {
    return <RecipeSearchExclusion>[
      RecipeSearchExclusion(
        id: 'excluded-test-id',
        sourceType: 'youtube',
        sourceId: 'video-test-id',
        title: '검색 제외 테스트 레시피',
        ingredients: const <String>['김치'],
        steps: const <String>[],
        reasonCodes: const <String>['missing_steps'],
        status: 'needs_edit',
        createdAt: DateTime.utc(2026, 9, 10),
      ),
    ];
  }

  @override
  Future<Map<String, int>> getKitchenSummary() async {
    return <String, int>{
      'ingredient_count': 0,
      'expiring_soon_count': 0,
      'active_shopping_list_count': 0,
      'open_shopping_item_count': 0,
    };
  }

  @override
  Future<Recipe> updateCreatorRecipe({
    required String id,
    required String title,
    String? summary,
    required List<String> ingredients,
    required List<String> steps,
    String? tips,
    String? imagePath,
    String? youtubeUrl,
    Map<String, dynamic> contentStyles = const <String, dynamic>{},
  }) async {
    return Recipe(
      id: id,
      title: title,
      summary: summary,
      ingredients: ingredients,
      steps: steps,
      tips: tips,
      youtubeUrl: youtubeUrl,
      contentStyles: contentStyles,
    );
  }

  @override
  Future<Recipe> updateSubscriberRecipeNotes({
    required String id,
    required String notes,
  }) async {
    return Recipe(
      id: id,
      title: '내 요리 노트',
      ingredients: <String>['재료'],
      steps: <String>['순서'],
      notes: notes,
      visibility: 'private',
    );
  }

  @override
  Future<void> resolveRecipeSearchExclusion(String id) async {}
}

class _DelayedRecipeRepository extends _FakeRecipeRepository {
  _DelayedRecipeRepository(this.completer);

  final Completer<List<Recipe>> completer;

  @override
  Future<List<Recipe>> listPublicRecipes({
    String? search,
    bool useAiSearch = false,
  }) {
    return completer.future;
  }
}

class _YoutubeCreatorRecipeRepository extends _FakeRecipeRepository {
  int publicSearchCalls = 0;

  @override
  Future<Recipe?> getCreatorRecipeById(String id) async {
    return Recipe(
      id: id,
      title: '김치찌개',
      ingredients: const <String>[],
      steps: const <String>['영상을 확인해 주세요.'],
      youtubeUrl: 'https://youtu.be/abc123XYZ00',
      sourceType: 'youtube_import',
    );
  }

  @override
  Future<List<Recipe>> listPublicRecipes({
    String? search,
    bool useAiSearch = false,
  }) async {
    publicSearchCalls += 1;
    return super.listPublicRecipes(search: search, useAiSearch: useAiSearch);
  }
}

Future<void> _pumpUntilFound(
  WidgetTester tester,
  Finder finder, {
  int maxPumps = 30,
}) async {
  for (var index = 0; index < maxPumps; index += 1) {
    await tester.pump(const Duration(milliseconds: 100));
    if (finder.evaluate().isNotEmpty) {
      return;
    }
  }

  fail('Timed out waiting for ${finder.describeMatch(Plurality.many)}.');
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    final dispatcher =
        TestWidgetsFlutterBinding.ensureInitialized().platformDispatcher;
    dispatcher.localesTestValue = const <Locale>[Locale('ko', 'KR')];
    addTearDown(dispatcher.clearLocalesTestValue);
    // KYoutubeApp is mounted after successful bootstrap in normal use.
    final previous = OpsMonitorService.state.value;
    OpsMonitorService.state.value = const OpsMonitorState(
        appEnv: 'local',
        phase: '준비 완료',
        isReady: true,
        recentErrors: <OpsErrorEvent>[]);
    addTearDown(() => OpsMonitorService.state.value = previous);
  });
  testWidgets('English device gets English home and navigation',
      (WidgetTester tester) async {
    tester.platformDispatcher.localesTestValue = const <Locale>[
      Locale('en', 'US')
    ];
    await tester.pumpWidget(
      ProviderScope(
        overrides: <Override>[
          recipeRepositoryProvider.overrideWithValue(_FakeRecipeRepository()),
        ],
        child: const KYoutubeApp(),
      ),
    );
    await tester.pump();
    AppRouter.router.go(AppRoutes.home);
    await _pumpUntilFound(tester, find.byType(TextField));
    await tester.pumpAndSettle();
    expect(find.text('Recipe Scout'), findsOneWidget);
    expect(find.text('Your table,\nyour way.'), findsOneWidget);
    expect(find.text('Import recipe'), findsOneWidget);
    expect(find.text('Chef'), findsNothing);
    expect(find.text('More'), findsOneWidget);
    expect(find.byTooltip('Recipe library'), findsOneWidget);
    expect(find.text('Shopping'), findsOneWidget);
    expect(find.byTooltip('More'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('unsupported device language falls back to Korean',
      (WidgetTester tester) async {
    tester.platformDispatcher.localesTestValue = const <Locale>[
      Locale('fr', 'FR')
    ];
    await tester.pumpWidget(
      ProviderScope(
        overrides: <Override>[
          recipeRepositoryProvider.overrideWithValue(_FakeRecipeRepository()),
        ],
        child: const KYoutubeApp(),
      ),
    );
    await tester.pump();
    AppRouter.router.go(AppRoutes.home);
    await _pumpUntilFound(tester, find.byType(TextField));
    await tester.pumpAndSettle();
    expect(find.text('레시피 스카우트'), findsOneWidget);
    expect(find.text('장보기'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('home screen renders', (WidgetTester tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: <Override>[
          recipeRepositoryProvider.overrideWithValue(_FakeRecipeRepository()),
        ],
        child: const KYoutubeApp(),
      ),
    );

    await tester.pump();
    AppRouter.router.go(AppRoutes.home);
    await _pumpUntilFound(tester, find.byType(TextField));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
        find.byKey(const Key('classic-card-bibimbap')), 250,
        scrollable: find.byType(Scrollable).first);

    expect(
      find.text('레시피 스카우트'),
      findsOneWidget,
    );
    expect(find.text('무엇을 만들어 볼까요?'), findsOneWidget);
    expect(find.byKey(const Key('classic-card-bibimbap')), findsOneWidget);
    expect(find.text('한국어 영상 · 하루한끼'), findsWidgets);
    expect(find.byTooltip('북마크'), findsNothing);
    expect(find.byTooltip('더보기'), findsOneWidget);
  });

  testWidgets('home search submits immediately and keeps the result visible',
      (WidgetTester tester) async {
    final repository = _FakeRecipeRepository();
    await tester.pumpWidget(
      ProviderScope(
        overrides: <Override>[
          recipeRepositoryProvider.overrideWithValue(repository),
          recommendedRecipeSearchServiceProvider.overrideWithValue(
            RecommendedRecipeSearchService(
              youtubeRepository: _EmptyYoutubeRepository(),
              publicRecipeSearch: (String query) =>
                  repository.listPublicRecipes(
                search: query,
                useAiSearch: true,
              ),
            ),
          ),
        ],
        child: const KYoutubeApp(),
      ),
    );
    await tester.pump();
    AppRouter.router.go(AppRoutes.home);
    await _pumpUntilFound(tester, find.byType(TextField));

    await tester.enterText(find.byType(TextField), '감자');
    await tester.testTextInput.receiveAction(TextInputAction.search);
    await _pumpUntilFound(tester, find.text('검색 결과: 감자'));

    expect(find.text('검색 결과: 감자'), findsOneWidget);
    expect(find.text('공공 레시피'), findsOneWidget);

    // The tooltip is localized; select the actual back control.
    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();
  });

  testWidgets('recommended search explains login when video search needs auth',
      (WidgetTester tester) async {
    final service = RecommendedRecipeSearchService(
      youtubeRepository: _AuthRequiredYoutubeRepository(),
      publicRecipeSearch: (_) async => <Recipe>[],
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: <Override>[
          recommendedRecipeSearchServiceProvider.overrideWithValue(service),
        ],
        child: const MaterialApp(
          home: RecommendedRecipeSearchPage(initialQuery: '국수'),
        ),
      ),
    );

    await _pumpUntilFound(tester, find.text('영상 검색은 로그인이 필요합니다'));

    expect(find.text('로그인하기'), findsOneWidget);
    expect(find.text('검색 결과가 없습니다'), findsNothing);
  });

  testWidgets('disposing home during a pending search does not access ref',
      (WidgetTester tester) async {
    final completer = Completer<List<Recipe>>();
    await tester.pumpWidget(
      ProviderScope(
        overrides: <Override>[
          recipeRepositoryProvider.overrideWithValue(
            _DelayedRecipeRepository(completer),
          ),
        ],
        child: const MaterialApp(home: HomePage()),
      ),
    );
    await tester.pump();

    await tester.enterText(find.byType(TextField), '감자');
    await tester.pumpWidget(const MaterialApp(home: SizedBox()));
    await tester.pump(const Duration(milliseconds: 300));
    completer.complete(<Recipe>[]);
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
  });

  testWidgets('selecting a public search result opens its detail page',
      (WidgetTester tester) async {
    final repository = _FakeRecipeRepository();
    await tester.pumpWidget(ProviderScope(
      overrides: [
        recipeRepositoryProvider.overrideWithValue(repository),
        recommendedRecipeSearchServiceProvider.overrideWithValue(
          RecommendedRecipeSearchService(
            youtubeRepository: _EmptyYoutubeRepository(),
            publicRecipeSearch: (query) =>
                repository.listPublicRecipes(search: query),
          ),
        ),
      ],
      child: const KYoutubeApp(),
    ));
    await tester.pump();
    AppRouter.router.go(AppRoutes.home);
    await _pumpUntilFound(tester, find.byType(TextField));
    await tester.enterText(find.byType(TextField), '감자');
    await tester.testTextInput.receiveAction(TextInputAction.search);
    await _pumpUntilFound(tester, find.text('검색 결과: 감자'));
    await tester.tap(find.text('검색 결과: 감자'));
    await _pumpUntilFound(tester, find.text('상세 레시피'));
    expect(find.text('상세 레시피'), findsOneWidget);
  });

  testWidgets('disposing a recipe detail page does not access ref',
      (WidgetTester tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: <Override>[
          recipeRepositoryProvider.overrideWithValue(_FakeRecipeRepository()),
        ],
        child: const MaterialApp(
          home: RecipeDetailPage(recipeId: 'external-source-id'),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.pumpWidget(const MaterialApp(home: SizedBox()));
    await tester.pump();

    expect(tester.takeException(), isNull);
  });

  testWidgets('creator recipe detail shows tips', (WidgetTester tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: <Override>[
          recipeRepositoryProvider.overrideWithValue(_FakeRecipeRepository()),
        ],
        child: const MaterialApp(
          home: CreatorRecipeDetailPage(recipeId: 'creator-test-id'),
        ),
      ),
    );

    await tester.pumpAndSettle();

    await tester.scrollUntilVisible(
      find.text('팁'),
      300,
      scrollable: find.byType(Scrollable).first,
    );

    await tester.pumpAndSettle();

    expect(find.text('팁'), findsOneWidget);
    expect(find.text('테스트 팁'), findsOneWidget);
  });

  testWidgets('youtube_import recipe opens the YouTube-only enrichment page',
      (WidgetTester tester) async {
    final repository = _YoutubeCreatorRecipeRepository();
    await tester.pumpWidget(
      ProviderScope(
        overrides: <Override>[
          recipeRepositoryProvider.overrideWithValue(repository),
        ],
        child: const MaterialApp(
          home: CreatorRecipeDetailPage(recipeId: 'youtube-recipe-id'),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text('AI로 레시피 보강'),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(find.text('AI로 레시피 보강'));
    await tester.pumpAndSettle();

    expect(find.text('AI 레시피 초안 만들기'), findsOneWidget);
    expect(find.text('기존 자동 초안 만들기'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.text('자막 위치 확인'),
      200,
      scrollable: find.byType(Scrollable).last,
    );
    expect(find.text('자막 위치 확인'), findsOneWidget);
    expect(find.text('자막으로 AI 초안 만들기'), findsOneWidget);
    expect(repository.publicSearchCalls, 0);
  });

  testWidgets('non-youtube creator recipe does not offer public enrichment',
      (WidgetTester tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: <Override>[
          recipeRepositoryProvider.overrideWithValue(_FakeRecipeRepository()),
        ],
        child: const MaterialApp(
          home: CreatorRecipeDetailPage(recipeId: 'manual-recipe-id'),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('AI로 레시피 보강'), findsNothing);
  });

  testWidgets('search exclusions page renders an incomplete recipe',
      (WidgetTester tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: <Override>[
          recipeRepositoryProvider.overrideWithValue(_FakeRecipeRepository()),
        ],
        child: const MaterialApp(
          home: RecipeSearchExclusionsPage(),
        ),
      ),
    );

    await tester.pumpAndSettle();

    expect(find.text('검색 제외 테스트 레시피'), findsOneWidget);
    expect(find.text('조리순서가 부족한 초안'), findsOneWidget);
  });
}
