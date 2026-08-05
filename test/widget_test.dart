import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:k_youtube/app.dart';
import 'package:k_youtube/features/recipes/domain/bookmarked_recipe.dart';
import 'package:k_youtube/features/recipes/application/recipe_providers.dart';
import 'package:k_youtube/features/recipes/data/recipe_repository.dart';
import 'package:k_youtube/features/recipes/domain/recipe.dart';
import 'package:k_youtube/features/recipes/presentation/creator_recipe_detail_page.dart';
import 'package:k_youtube/features/recipes/presentation/bookmarked_recipes_page.dart';
import 'package:k_youtube/features/recipes/presentation/recipe_detail_page.dart';
import 'package:k_youtube/features/home/presentation/home_page.dart';

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
  }) async {
    return Recipe(
      id: 'created-test-id',
      title: title,
      summary: summary,
      ingredients: ingredients,
      steps: steps,
      tips: tips,
      youtubeUrl: youtubeUrl,
    );
  }

  @override
  Future<void> deleteCreatorRecipe(String id) async {}

  @override
  Future<void> deleteSubscriberRecipe(String id) async {}

  @override
  Future<void> addBookmark({
    required String recipeType,
    required String recipeId,
  }) async {}

  @override
  Future<int> createKitchenShoppingFromRecipe({
    required String recipeType,
    required Recipe recipe,
  }) async {
    return 0;
  }

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
  Future<List<BookmarkedRecipe>> listBookmarkedRecipes() async {
    return <BookmarkedRecipe>[
      BookmarkedRecipe(
        recipeType: 'public',
        recipe: Recipe(
          id: 'bookmark-test-id',
          title: '북마크 테스트 레시피',
          ingredients: <String>['재료'],
          steps: <String>['순서'],
        ),
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
  }) async {
    return Recipe(
      id: id,
      title: title,
      summary: summary,
      ingredients: ingredients,
      steps: steps,
      tips: tips,
      youtubeUrl: youtubeUrl,
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
  Future<bool> isBookmarked({
    required String recipeType,
    required String recipeId,
  }) async =>
      false;

  @override
  Future<void> removeBookmark({
    required String recipeType,
    required String recipeId,
  }) async {}
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

void main() {
  testWidgets('home screen renders', (WidgetTester tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: <Override>[
          recipeRepositoryProvider.overrideWithValue(_FakeRecipeRepository()),
        ],
        child: const KYoutubeApp(),
      ),
    );

    await tester.pumpAndSettle();

    expect(find.text('AI Cooking Platform'), findsOneWidget);
    expect(find.text('공개 레시피 검색'), findsOneWidget);
    expect(find.text('테스트 레시피'), findsOneWidget);
  });

  testWidgets('home search submits immediately and keeps the result visible',
      (WidgetTester tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: <Override>[
          recipeRepositoryProvider.overrideWithValue(_FakeRecipeRepository()),
        ],
        child: const KYoutubeApp(),
      ),
    );
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), '감자');
    await tester.testTextInput.receiveAction(TextInputAction.search);
    await tester.pumpAndSettle();

    expect(find.text('검색 결과: 감자'), findsOneWidget);
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
    await tester.pumpWidget(
      ProviderScope(
        overrides: <Override>[
          recipeRepositoryProvider.overrideWithValue(_FakeRecipeRepository()),
        ],
        child: const KYoutubeApp(),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('테스트 레시피'));
    await tester.pumpAndSettle();

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

    expect(find.text('팁'), findsOneWidget);
    expect(find.text('테스트 팁'), findsOneWidget);
  });

  testWidgets('bookmarks page renders saved recipe',
      (WidgetTester tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: <Override>[
          recipeRepositoryProvider.overrideWithValue(_FakeRecipeRepository()),
        ],
        child: const MaterialApp(
          home: BookmarkedRecipesPage(),
        ),
      ),
    );

    await tester.pumpAndSettle();

    expect(find.text('북마크 테스트 레시피'), findsOneWidget);
  });
}
