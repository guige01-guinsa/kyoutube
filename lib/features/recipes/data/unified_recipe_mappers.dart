import '../domain/recipe.dart';
import '../domain/recipe_identity.dart';
import '../domain/unified_recipe.dart';

UnifiedRecipe mapRecipeToUnifiedRecipe({
  required Recipe recipe,
  required RecipeIdentity identity,
}) {
  final provenance = _provenanceFor(recipe, identity);
  final access = _accessFor(identity);
  final origin = _originFor(identity);

  return UnifiedRecipe(
    identity: identity,
    title: recipe.title,
    summary: recipe.summary,
    imageUrl: recipe.imageUrl,
    ingredients: List<String>.unmodifiable(recipe.ingredients),
    steps: List<String>.unmodifiable(recipe.steps),
    origin: origin,
    access: access,
    provenance: provenance,
  );
}

RecipeOrigin _originFor(RecipeIdentity identity) {
  return switch (identity.sourceType) {
    'public' => const RecipeOrigin(label: '공개 레시피'),
    'creator' => const RecipeOrigin(label: '내가 만든 레시피'),
    'user' => const RecipeOrigin(label: '내 레시피'),
    _ => const RecipeOrigin(label: '레시피'),
  };
}

RecipeAccess _accessFor(RecipeIdentity identity) {
  return switch (identity.sourceType) {
    'public' => const RecipeAccess.readOnly(),
    'creator' || 'user' => const RecipeAccess.owned(),
    _ => const RecipeAccess.unavailable(),
  };
}

RecipeProvenance _provenanceFor(
  Recipe recipe,
  RecipeIdentity identity,
) {
  final youtubeUrl = recipe.youtubeUrl?.trim();

  if (youtubeUrl != null && youtubeUrl.isNotEmpty) {
    return RecipeProvenance(
      type: RecipeProvenanceType.youtube,
      sourceUrl: youtubeUrl,
    );
  }

  return switch (identity.sourceType) {
    'public' => const RecipeProvenance(
        type: RecipeProvenanceType.imported,
      ),
    'creator' || 'user' => const RecipeProvenance(
        type: RecipeProvenanceType.manual,
      ),
    _ => const RecipeProvenance(
        type: RecipeProvenanceType.unknown,
      ),
  };
}
