import '../domain/recipe.dart';
import '../domain/recipe_identity.dart';
import '../domain/unified_recipe.dart';
import '../domain/unified_recipe_repository.dart';
import 'recipe_repository.dart';
import 'unified_recipe_mappers.dart';

class DefaultUnifiedRecipeRepository implements UnifiedRecipeRepository {
  const DefaultUnifiedRecipeRepository(this._recipeRepository);

  final RecipeRepository _recipeRepository;

  @override
  Future<UnifiedRecipe?> getRecipe(RecipeIdentity identity) async {
    final recipe = switch (identity.sourceType) {
      'public' => await _recipeRepository.getRecipeById(identity.sourceId),
      'creator' =>
        await _recipeRepository.getCreatorRecipeById(identity.sourceId),
      'user' =>
        await _recipeRepository.getSubscriberRecipeById(identity.sourceId),
      _ => null,
    };

    if (recipe == null) {
      return null;
    }

    return mapRecipeToUnifiedRecipe(
      recipe: recipe,
      identity: identity,
    );
  }

  @override
  Future<List<UnifiedRecipe>> listMyRecipes({
    String? search,
  }) async {
    final normalizedSearch = (search ?? '').trim();

    final results = await Future.wait<List<Recipe>>(
      <Future<List<Recipe>>>[
        _recipeRepository.listSubscriberRecipes(),
        _recipeRepository.listCreatorRecipes(
          search: normalizedSearch.isEmpty ? null : normalizedSearch,
        ),
      ],
    );

    final subscriberRecipes = _filterRecipes(
      results[0],
      normalizedSearch,
    );

    final creatorRecipes = results[1];

    final items = <UnifiedRecipe>[
      ...subscriberRecipes.map(
        (recipe) => mapRecipeToUnifiedRecipe(
          recipe: recipe,
          identity: RecipeIdentity(
            sourceType: 'user',
            sourceId: recipe.id,
          ),
        ),
      ),
      ...creatorRecipes.map(
        (recipe) => mapRecipeToUnifiedRecipe(
          recipe: recipe,
          identity: RecipeIdentity(
            sourceType: 'creator',
            sourceId: recipe.id,
          ),
        ),
      ),
    ];

    items.sort((a, b) {
      return a.title.toLowerCase().compareTo(b.title.toLowerCase());
    });

    return List<UnifiedRecipe>.unmodifiable(items);
  }

  List<Recipe> _filterRecipes(
    List<Recipe> recipes,
    String search,
  ) {
    final query = search.trim().toLowerCase();

    if (query.isEmpty) {
      return recipes;
    }

    return recipes.where((recipe) {
      final text = <String>[
        recipe.title,
        recipe.summary ?? '',
        recipe.tips ?? '',
        recipe.notes ?? '',
        recipe.youtubeUrl ?? '',
        ...recipe.ingredients,
        ...recipe.steps,
      ].join(' ').toLowerCase();

      return text.contains(query);
    }).toList();
  }
}
