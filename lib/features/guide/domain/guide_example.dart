import '../../chef/domain/chef_recipe.dart';

/// Synthetic training values reuse Chef calculations without any repository.
class GuideExample {
  GuideExample(
      {int servings = 4, double yieldPercent = 80, double markup = 50}) {
    if (servings < 1 ||
        servings > 100 ||
        !yieldPercent.isFinite ||
        yieldPercent <= 0 ||
        yieldPercent > 100 ||
        !markup.isFinite ||
        markup < 0 ||
        markup > 100) {
      throw ArgumentError('Invalid training inputs');
    }
    recipe = ChefRecipe(
        title: 'Training example',
        baseServings: 4,
        targetServings: servings.toDouble(),
        steps: '',
        markupPercent: markup,
        ingredients: [
          ChefIngredient(
              id: 'training-chicken',
              name: 'Chicken',
              quantity: 800,
              unit: ChefUnit.g,
              purchaseQuantity: 1,
              purchaseUnit: ChefUnit.kg,
              purchasePrice: 12000,
              yieldPercent: yieldPercent)
        ]);
  }
  late final ChefRecipe recipe;
  double get usage => recipe.ingredients.first.quantity! * recipe.ratio!;
  double get purchase =>
      recipe.ingredients.first.neededPurchase(recipe.ratio!)!;
  double get price => recipe.sellingPrice!;
  double get revenueForTen => price * 10;
  double get differenceForTen => (price - recipe.portionCost!) * 10;
}
