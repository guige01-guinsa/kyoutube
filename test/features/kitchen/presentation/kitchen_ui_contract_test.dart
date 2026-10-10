import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  late String kitchenPage;

  setUpAll(() {
    kitchenPage = File(
      'lib/features/kitchen/presentation/kitchen_page.dart',
    ).readAsStringSync();
  });

  test('shopping completion history opens the existing history tab', () {
    expect(kitchenPage, contains('_tabController.animateTo(1);'));
    expect(kitchenPage, isNot(contains('_tabController.animateTo(2);')));
  });

  test('purchase unit category selector stays in one four-part row', () {
    expect(kitchenPage, contains('children: shoppingUnitCategories.map'));
    expect(kitchenPage, contains(r"'$selectedUnitCategory:$unit'"));
    expect(kitchenPage, isNot(contains('ChoiceChip(')));
  });

  test('kitchen cleanup can include cooking completion history', () {
    expect(kitchenPage, contains('조리 완료 기록 정리'));
    expect(kitchenPage, contains('clearCookHistory'));
  });
}
