import 'package:flutter_test/flutter_test.dart';
import 'package:k_youtube/features/ingredient_search/domain/ingredient_matcher.dart';

void main() {
  test('normalizes Korean ingredient quantity and unit text', () {
    expect(IngredientMatcher.normalize('감자 2개'), '감자');
    expect(IngredientMatcher.normalize('돼지고기 300g'), '돼지고기');
    expect(IngredientMatcher.normalize('양파 1/2개'), '양파');
    expect(IngredientMatcher.normalize('다진 마늘 1큰술'), '다진 마늘');
  });

  test('matches fridge ingredients against recipe ingredient text', () {
    final result = IngredientMatcher.match(
      recipeIngredients: <String>[
        '감자 2개',
        '돼지고기 300g',
        '양파 1개',
        '고추장 1큰술',
      ],
      availableIngredients: <String>[
        '감자',
        '돼지고기',
        '양파',
      ],
    );

    expect(result.totalCount, 4);
    expect(result.availableCount, 3);
    expect(result.missingCount, 1);
    expect(result.needsOnlyOneIngredient, isTrue);
    expect(result.missing.single.normalizedName, '고추장');
  });

  test('canCookNow is true only when every ingredient is available', () {
    final result = IngredientMatcher.match(
      recipeIngredients: <String>['감자 2개', '양파 1개'],
      availableIngredients: <String>['감자', '양파'],
    );

    expect(result.canCookNow, isTrue);
    expect(result.missing, isEmpty);
  });

  test('does not match empty ingredient names', () {
    final result = IngredientMatcher.match(
      recipeIngredients: <String>['', '감자 2개'],
      availableIngredients: <String>['감자'],
    );

    expect(result.totalCount, 1);
    expect(result.availableCount, 1);
  });
}
