import 'package:flutter_test/flutter_test.dart';
import 'package:k_youtube/features/recipes/domain/recipe.dart';
import 'package:k_youtube/features/recipes/domain/recipe_enrichment_suggestion.dart';

void main() {
  test('English editor draft retains review markers and English warnings', () {
    final suggestion = RecipeEnrichmentSuggestion.fromJson(<String, dynamic>{
      'title': 'Soup',
      'ingredients': <String>['[Check video] salt'],
      'steps': <String>['[Check video] simmer'],
      'warnings': <String>['Confirm the salt quantity.'],
    });
    final source = Recipe(
      id: 'source',
      title: 'Soup video',
      ingredients: const <String>[],
      steps: const <String>[],
      youtubeUrl: 'https://www.youtube.com/watch?v=abcdefghijk',
    );
    final draft =
        suggestion.toDraftRecipe(sourceRecipe: source, isEnglish: true);
    expect(draft.tips, 'Review notes: Confirm the salt quantity.');
    expect(draft.ingredients, <String>['[Check video] salt']);
    expect(draft.steps, <String>['[Check video] simmer']);
    expect(draft.youtubeUrl, source.youtubeUrl);
    expect(suggestion.toDraftRecipe(sourceRecipe: source).tips,
        '확인사항: Confirm the salt quantity.');
  });

  test('parses structured recipe timing and evidence metadata', () {
    final suggestion = RecipeEnrichmentSuggestion.fromJson(
      <String, dynamic>{
        'title': '크림수프',
        'summary': '영상 기반 초안',
        'servings': 2,
        'prepTimeMinutes': 5,
        'cookTimeMinutes': 15,
        'ingredients': <String>['우유 300 ml', '[확인 필요] 소금'],
        'ingredientDetails': <Map<String, dynamic>>[
          <String, dynamic>{
            'name': '우유',
            'quantity': 300,
            'unit': 'ml',
            'status': 'confirmed',
          },
          <String, dynamic>{
            'name': '소금',
            'quantity': null,
            'unit': null,
            'status': 'unverified',
          },
        ],
        'steps': <String>['우유를 넣고 5분간 끓인다'],
        'stepDetails': <Map<String, dynamic>>[
          <String, dynamic>{
            'instruction': '우유를 넣고 끓인다',
            'durationMinutes': 5,
            'ingredientNames': <String>['우유'],
            'status': 'confirmed',
          },
        ],
        'warnings': <String>['소금 양을 확인하세요.'],
        'references': <Map<String, dynamic>>[],
      },
    );

    expect(suggestion.servings, 2);
    expect(suggestion.prepTimeMinutes, 5);
    expect(suggestion.cookTimeMinutes, 15);
    expect(suggestion.ingredientDetails.first.quantity, '300');
    expect(suggestion.stepDetails.first.ingredientNames, <String>['우유']);
    expect(suggestion.hasItemsRequiringReview, isTrue);
  });

  test('keeps legacy flat recipe responses compatible', () {
    final suggestion = RecipeEnrichmentSuggestion.fromJson(
      <String, dynamic>{
        'title': '김치찌개',
        'summary': '기존 응답',
        'ingredients': <String>['김치 300g'],
        'steps': <String>['끓인다'],
        'warnings': <String>[],
        'references': <Map<String, dynamic>>[],
      },
    );

    expect(suggestion.ingredients, <String>['김치 300g']);
    expect(suggestion.ingredientDetails, isEmpty);
    expect(suggestion.stepDetails, isEmpty);
    expect(suggestion.hasItemsRequiringReview, isFalse);
  });
}
