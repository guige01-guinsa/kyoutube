import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:k_youtube/app.dart';
import 'package:k_youtube/features/recipes/domain/bookmarked_recipe.dart';
import 'package:k_youtube/features/recipes/application/recipe_providers.dart';
import 'package:k_youtube/features/recipes/data/recipe_repository.dart';
import 'package:k_youtube/features/recipes/domain/recipe.dart';
import 'package:k_youtube/features/recipes/domain/youtube_metadata.dart';
import 'package:k_youtube/features/recipes/presentation/creator_recipe_detail_page.dart';
import 'package:k_youtube/features/recipes/presentation/bookmarked_recipes_page.dart';

class _FakeRecipeRepository implements RecipeRepository {
  @override
  Future<Recipe> createSubscriberRecipe({
    required String title,
    required List<String> ingredients,
    required List<String> steps,
    String? summary,
    String? notes,
    String? imageUrl,
    String? youtubeUrl,
    String? sourceType,
  }) async {
    return Recipe(
      id: 'subscriber-manual-created-id',
      title: title,
      summary: summary,
      ingredients: ingredients,
      steps: steps,
      notes: notes,
      imageUrl: imageUrl,
      youtubeUrl: youtubeUrl,
      visibility: 'private',
      sourceType: sourceType,
    );
  }

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
  Future<KitchenShoppingCreateResult> createKitchenShoppingFromRecipe({
    required String recipeType,
    required Recipe recipe,
  }) async {
    return const KitchenShoppingCreateResult(missingCount: 0);
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
  Future<RecipeYoutubeMetadata?> getCreatorRecipeYoutubeMetadata(String id) async {
    return null;
  }

  @override
  Future<Recipe?> getRecipeById(String id) async => null;

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
        title: '테스트 레시피',
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
  Future<Recipe> updateSubscriberRecipe({
    required String id,
    required String title,
    required List<String> ingredients,
    required List<String> steps,
    String? summary,
    String? notes,
    String? imageUrl,
    String? youtubeUrl,
  }) async {
    return Recipe(
      id: id,
      title: title,
      summary: summary,
      ingredients: ingredients,
      steps: steps,
      notes: notes,
      imageUrl: imageUrl,
      youtubeUrl: youtubeUrl,
      visibility: 'private',
    );
  }

  @override
  Future<Recipe> promoteSubscriberRecipeToCreator({
    required String id,
    bool deleteSource = false,
    bool includeSummary = true,
    bool includeYoutubeUrl = true,
    bool includeImageUrl = true,
    bool includeNotesAsTips = true,
  }) async {
    return Recipe(
      id: 'creator-from-$id',
      title: '승격된 레시피',
      summary: includeSummary ? '요약' : null,
      ingredients: <String>['재료'],
      steps: <String>['순서'],
      tips: includeNotesAsTips ? '메모 기반 팁' : null,
      imageUrl: includeImageUrl ? 'https://example.com/image.jpg' : null,
      youtubeUrl: includeYoutubeUrl ? 'https://youtu.be/test' : null,
    );
  }

  @override
  Future<bool> isBookmarked({
    required String recipeType,
    required String recipeId,
  }) async => false;

  @override
  Future<void> removeBookmark({
    required String recipeType,
    required String recipeId,
  }) async {}
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues(
      <String, Object>{
        'app.onboarding_completed_v1': true,
      },
    );
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

    await tester.pumpAndSettle();

    expect(find.text('AI Cooking Platform'), findsOneWidget);
    expect(find.text('레시피 검색'), findsOneWidget);
  });

  testWidgets('creator recipe detail shows tips', (WidgetTester tester) async {
    final creatorRecipe = Recipe(
      id: 'creator-test-id',
      title: '내 레시피 테스트',
      ingredients: <String>['재료'],
      steps: <String>['순서'],
      tips: '테스트 팁',
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: <Override>[
          recipeRepositoryProvider.overrideWithValue(_FakeRecipeRepository()),
          creatorRecipeByIdProvider.overrideWith(
            (ref, String id) async => creatorRecipe,
          ),
          creatorRecipeYoutubeMetadataProvider.overrideWith(
            (ref, String id) async => null,
          ),
          creatorYoutubeMetadataOverrideProvider.overrideWith(
            (ref, String id) async => null,
          ),
        ],
        child: const MaterialApp(
          home: CreatorRecipeDetailPage(recipeId: 'creator-test-id'),
        ),
      ),
    );

    await tester.pumpAndSettle();

    await tester.drag(find.byType(ListView), const Offset(0, -800));
    await tester.pumpAndSettle();

    expect(find.text('팁'), findsOneWidget);
    expect(find.text('테스트 팁'), findsOneWidget);
  });

  testWidgets('bookmarks page renders saved recipe', (WidgetTester tester) async {
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
