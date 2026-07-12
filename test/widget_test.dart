import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:k_youtube/app.dart';
import 'package:k_youtube/features/recipes/application/recipe_providers.dart';
import 'package:k_youtube/features/recipes/data/recipe_repository.dart';
import 'package:k_youtube/features/recipes/domain/recipe.dart';

class _FakeRecipeRepository implements RecipeRepository {
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
      youtubeUrl: youtubeUrl,
    );
  }

  @override
  Future<void> deleteCreatorRecipe(String id) async {}

  @override
  Future<Recipe?> getCreatorRecipeById(String id) async {
    return Recipe(
      id: id,
      title: '내 레시피 테스트',
      ingredients: <String>['재료'],
      steps: <String>['순서'],
    );
  }

  @override
  Future<Recipe?> getRecipeById(String id) async => null;

  @override
  Future<List<Recipe>> listCreatorRecipes() async {
    return <Recipe>[
      Recipe(
        id: 'creator-test-id',
        title: '내 레시피 테스트',
        ingredients: <String>['재료'],
        steps: <String>['순서'],
      ),
    ];
  }

  @override
  Future<List<Recipe>> listPublicRecipes() async {
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
      youtubeUrl: youtubeUrl,
    );
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
    expect(find.text('테스트 레시피'), findsOneWidget);
  });
}
