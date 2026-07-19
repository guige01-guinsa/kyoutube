import 'recipe.dart';

class BookmarkedRecipe {
  const BookmarkedRecipe({
    required this.recipeType,
    required this.recipe,
  });

  final String recipeType;
  final Recipe recipe;
}