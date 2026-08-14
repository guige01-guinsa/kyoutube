import 'package:flutter_test/flutter_test.dart';
import 'package:k_youtube/features/recipes/domain/recipe_identity.dart';
import 'package:k_youtube/features/recipes/domain/unified_recipe.dart';

void main() {
  group('UnifiedRecipe', () {
    test('exposes a stable source reference', () {
      const recipe = UnifiedRecipe(
        identity: RecipeIdentity(
          sourceType: 'public',
          sourceId: 'recipe-1',
        ),
        title: 'Tomato Soup',
        summary: 'Simple soup',
        imageUrl: null,
        ingredients: <String>['tomato', 'salt'],
        steps: <String>['Boil', 'Serve'],
        origin: RecipeOrigin(label: 'Public'),
        access: RecipeAccess.readOnly(),
        provenance: RecipeProvenance(
          type: RecipeProvenanceType.imported,
        ),
      );

      expect(recipe.sourceReference, 'public:recipe-1');
      expect(recipe.access.canSave, isTrue);
      expect(recipe.access.canEdit, isFalse);
      expect(recipe.access.canCreatePersonalVersion, isTrue);
    });

    test('owned access allows editing and disables personal copy action', () {
      const access = RecipeAccess.owned();

      expect(access.canEdit, isTrue);
      expect(access.canDelete, isTrue);
      expect(access.canCreatePersonalVersion, isFalse);
      expect(access.canShop, isTrue);
      expect(access.canCook, isTrue);
    });

    test('unavailable access disables all recipe actions', () {
      const access = RecipeAccess.unavailable();

      expect(access.canSave, isFalse);
      expect(access.canEdit, isFalse);
      expect(access.canDelete, isFalse);
      expect(access.canCreatePersonalVersion, isFalse);
      expect(access.canShop, isFalse);
      expect(access.canCook, isFalse);
      expect(access.canShare, isFalse);
    });
  });
}
