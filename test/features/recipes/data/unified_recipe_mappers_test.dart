import 'package:flutter_test/flutter_test.dart';
import 'package:k_youtube/features/recipes/data/unified_recipe_mappers.dart';
import 'package:k_youtube/features/recipes/domain/recipe.dart';
import 'package:k_youtube/features/recipes/domain/recipe_identity.dart';
import 'package:k_youtube/features/recipes/domain/unified_recipe.dart';

void main() {
  group('mapRecipeToUnifiedRecipe', () {
    test('maps a public recipe as read-only and imported', () {
      final recipe = Recipe(
        id: 'public-1',
        title: 'Public Soup',
        ingredients: <String>['tomato'],
        steps: <String>['Boil'],
        summary: 'Simple soup',
      );

      final unified = mapRecipeToUnifiedRecipe(
        recipe: recipe,
        identity: const RecipeIdentity(
          sourceType: 'public',
          sourceId: 'public-1',
        ),
      );

      expect(unified.title, 'Public Soup');
      expect(unified.sourceReference, 'public:public-1');
      expect(unified.access.canEdit, isFalse);
      expect(unified.access.canCreatePersonalVersion, isTrue);
      expect(unified.provenance.type, RecipeProvenanceType.imported);
    });

    test('maps a user recipe as owned', () {
      final recipe = Recipe(
        id: 'user-1',
        title: 'My Recipe',
        ingredients: <String>['tofu'],
        steps: <String>['Cook'],
      );

      final unified = mapRecipeToUnifiedRecipe(
        recipe: recipe,
        identity: const RecipeIdentity(
          sourceType: 'user',
          sourceId: 'user-1',
        ),
      );

      expect(unified.access.canEdit, isTrue);
      expect(unified.access.canDelete, isTrue);
      expect(unified.access.canCreatePersonalVersion, isFalse);
      expect(unified.provenance.type, RecipeProvenanceType.manual);
    });

    test('maps a YouTube recipe with YouTube provenance', () {
      final recipe = Recipe(
        id: 'user-youtube-1',
        title: 'YouTube Recipe',
        ingredients: <String>['egg'],
        steps: <String>['Steam'],
        youtubeUrl: 'https://youtube.com/watch?v=test',
      );

      final unified = mapRecipeToUnifiedRecipe(
        recipe: recipe,
        identity: const RecipeIdentity(
          sourceType: 'user',
          sourceId: 'user-youtube-1',
        ),
      );

      expect(unified.provenance.type, RecipeProvenanceType.youtube);
      expect(
        unified.provenance.sourceUrl,
        'https://youtube.com/watch?v=test',
      );
    });

    test('maps a creator recipe as owned in the current model', () {
      final recipe = Recipe(
        id: 'creator-1',
        title: 'Creator Recipe',
        ingredients: <String>['rice'],
        steps: <String>['Cook'],
      );

      final unified = mapRecipeToUnifiedRecipe(
        recipe: recipe,
        identity: const RecipeIdentity(
          sourceType: 'creator',
          sourceId: 'creator-1',
        ),
      );

      expect(unified.access.canEdit, isTrue);
      expect(unified.access.canDelete, isTrue);
      expect(unified.provenance.type, RecipeProvenanceType.manual);
    });
  });
}
