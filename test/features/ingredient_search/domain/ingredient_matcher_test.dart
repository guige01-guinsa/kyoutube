import 'package:flutter_test/flutter_test.dart';
import 'package:k_youtube/features/ingredient_search/domain/ingredient_matcher.dart';

void main() {
  test('normalizes Korean ingredient quantity and unit text', () {
    expect(IngredientMatcher.normalize('감자 2개'), '감자');
    expect(IngredientMatcher.normalize('돼지고기 300g'), '돼지고기');
    expect(IngredientMatcher.normalize('양파 1/2개'), '양파');
    expect(IngredientMatcher.normalize('다진 마늘 1큰술'), '다진 마늘');
    expect(IngredientMatcher.normalize('다진마늘 2 스푼'), '다진마늘');
    expect(IngredientMatcher.normalize('두부 1모'), '두부');
    expect(IngredientMatcher.normalize('대파 1줄기'), '대파');
    expect(IngredientMatcher.normalize('후추 약간'), '후추');
    expect(IngredientMatcher.normalize('3분 카레 1봉'), '3분 카레');
    expect(IngredientMatcher.normalize('azúcar 2 cucharadas'), 'azúcar');
    expect(IngredientMatcher.normalize('harina 100 gramos'), 'harina');
    expect(IngredientMatcher.normalize('agua 1 litro'), 'agua');
    expect(IngredientMatcher.normalize('간장 1T'), '간장');
    expect(IngredientMatcher.normalize('양파 반 개'), '양파');
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

  test('never treats an unverified AI ingredient as available', () {
    final result = IngredientMatcher.match(
      recipeIngredients: <String>['[확인 필요] 우유 250ml'],
      availableIngredients: <String>['우유'],
    );

    expect(result.available, isEmpty);
    expect(result.missing.single.normalizedName, '우유');
    expect(result.missing.single.requiresReview, isTrue);
  });
}
