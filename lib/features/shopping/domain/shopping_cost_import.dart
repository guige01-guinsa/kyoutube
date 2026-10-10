import '../../chef/domain/chef_recipe.dart';
import 'shopping_assistant.dart';

/// Changes the editor draft only; paid access and revision checks remain in
/// the existing Chef save RPC. A new pack may need a new conversion.
ChefIngredient chefIngredientWithPurchase(
    ChefIngredient original, ShoppingPurchaseRecord record, String currency) {
  if (record.amount == null ||
      record.quantity <= 0 ||
      !record.quantity.isFinite ||
      !record.amount!.isFinite ||
      record.amount! < 0 ||
      record.currency != currency ||
      shoppingNameKey(record.name) != shoppingNameKey(original.name)) {
    throw const FormatException('Purchase record does not match ingredient');
  }
  return ChefIngredient.fromJson({
    ...original.toJson(),
    'purchaseQuantity': record.quantity,
    'purchasePrice': record.amount,
    'purchaseUnit': ChefUnit.parse(record.unit).name,
    'purchaseUnitInUsageUnits': null
  });
}
