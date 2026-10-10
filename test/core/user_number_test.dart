import 'package:flutter_test/flutter_test.dart';
import 'package:k_youtube/core/format/user_number.dart';
import 'package:k_youtube/features/chef/domain/chef_recipe.dart';
import 'package:k_youtube/features/shopping/domain/shopping_assistant.dart';

void main() {
  test('all forms share finite decimal and grouping rules', () {
    for (final parse in [parseUserNumber, shoppingInput, chefInputNumber]) {
      for (final item in {
        '1,5': 1.5,
        '1,500': 1500.0,
        '1.234,5': 1234.5,
        '1,234.5': 1234.5,
        ' 0.75 ': 0.75,
        '-2,5': -2.5,
        '0': 0.0
      }.entries) {
        expect(parse(item.key), item.value, reason: item.key);
      }
      for (final value in ['', 'NaN', 'Infinity', '1e999', '1,2,3', '1 kg']) {
        expect(parse(value), isNull, reason: value);
      }
    }
  });
  test('ambiguous dimensions require an explicit factor', () {
    expect(shoppingConvert(1.5, 'kg', 'g'), 1500);
    expect(shoppingConvert(2, 'l', 'ml'), 2000);
    expect(shoppingConvert(2, 'g', 'ml'), isNull);
    expect(shoppingConvert(2, 'pack', 'g'), isNull);
  });
}
