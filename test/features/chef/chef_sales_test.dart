import 'package:flutter_test/flutter_test.dart';
import 'package:k_youtube/features/chef/domain/chef_recipe.dart';
import 'package:k_youtube/features/chef/domain/chef_sales.dart';
import 'chef_recipe_test.dart' as fixture;

void main() {
  test('markup includes both endpoints and applies currency rounding', () {
    for (final entry in {0: 2250, 50: 3375, 100: 4500}.entries) {
      final doc = ChefRecipe.fromJson(
          {...fixture.formula.toJson(), 'markupPercent': entry.key});
      expect(doc.sellingPrice, entry.value);
      expect(ChefRecipe.fromJson(doc.toJson()).markupPercent, entry.key);
    }
    final incomplete = ChefRecipe.fromJson(
        {...fixture.formula.toJson(), 'baseServings': null});
    expect(incomplete.sellingPrice, isNull);
  });
  test(
      'calendar ranges cover midnight, Monday weeks, leap months and year boundaries',
      () {
    final day = ChefSalesRange.forDate(
        DateTime(2026, 12, 31, 23, 59), ChefSalesPeriod.day);
    expect(chefDate(day.until), '2027-01-01');
    final week =
        ChefSalesRange.forDate(DateTime(2027, 1, 3), ChefSalesPeriod.week);
    expect(chefDate(week.from), '2026-12-28');
    expect(chefDate(week.until), '2027-01-04');
    final month =
        ChefSalesRange.forDate(DateTime(2028, 2, 29), ChefSalesPeriod.month);
    expect(chefDate(month.from), '2028-02-01');
    expect(chefDate(month.until), '2028-03-01');
  });
  test('revenue and estimated profit use recorded prices and costs', () {
    final sale = ChefSale.fromJson({
      'id': 1,
      'sale_date': '2026-09-12',
      'recipe_title': 'Carrots',
      'quantity': 10,
      'unit_price': 3375,
      'unit_cost': 2250,
      'currency': 'KRW'
    });
    expect(sale.revenue, 33750);
    expect(sale.profit, 11250);
    expect(
        ChefSalesTotals.fromJson(
            {'quantity': 10, 'revenue': 33750, 'cost': 22500}).profit,
        11250);
  });
}
