import 'dart:io';
import 'package:flutter/services.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:k_youtube/features/chef/domain/chef_recipe.dart';
import 'chef_workbench_test.dart' show MemoryChefRepository, showChef;

void main() {
  const capture = bool.fromEnvironment('UNIT_CAPTURE');
  setUpAll(() async {
    if (!capture) return;
    for (final entry in {
      'Ahem': 'C:/Windows/Fonts/malgun.ttf',
      'Roboto': 'C:/Windows/Fonts/malgun.ttf',
      'MaterialIcons':
          '.fvm/flutter_sdk/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf',
    }.entries) {
      final loader = FontLoader(entry.key);
      loader.addFont(Future.value(
          ByteData.sublistView(await File(entry.value).readAsBytes())));
      await loader.load();
    }
  });
  testWidgets(
      'manual conversion saves, reopens and clears after a purchase unit change',
      (tester) async {
    tester.view.physicalSize = const Size(390, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final repo = MemoryChefRepository(ChefRecipe(
        title: 'Tofu',
        steps: 'Cook',
        baseServings: 2,
        targetServings: 4,
        ingredients: [
          ChefIngredient(
              id: 'i',
              name: 'Tofu',
              quantity: 300,
              unit: ChefUnit.g,
              purchaseQuantity: 2,
              purchaseUnit: ChefUnit.parse('pack'),
              purchasePrice: 6000,
              yieldPercent: 75),
        ]));
    await showChef(tester, 'en', repo);
    final vertical = find
        .byWidgetPredicate(
            (w) => w is Scrollable && w.axisDirection == AxisDirection.down)
        .first;
    Future<void> openPrice() async {
      for (var i = 0;
          i < 35 &&
              find.text('Quick price edit').hitTestable().evaluate().isEmpty;
          i++) {
        await tester.drag(vertical, const Offset(0, -180));
        await tester.pumpAndSettle();
      }
      expect(find.text('Quick price edit').hitTestable(), findsOneWidget);
      await tester.tap(find.text('Quick price edit'));
      await tester.pumpAndSettle();
    }

    await openPrice();
    final conversion = find.byKey(const ValueKey('conversion-g-pack'));
    await tester.ensureVisible(conversion);
    await tester.enterText(conversion, '0');
    await tester.tap(find.text('Confirm'));
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsOneWidget);
    await tester.enterText(conversion, '400');
    await tester.pumpAndSettle();

    await tester.tap(find.text('Confirm'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Save work'));
    await tester.pumpAndSettle();
    expect(repo.document.ingredients.single.purchaseUnitInUsageUnits, 400);
    expect(repo.document.portionCost, 1500);
    await openPrice();
    expect(tester.widget<TextFormField>(conversion).initialValue, '400');
    if (capture) {
      await tester.ensureVisible(conversion);
      await tester.pumpAndSettle();
      await expectLater(find.byType(Overlay).first,
          matchesGoldenFile('../../../.artifacts/chef-unit-conversion-en.png'));
    }
    final purchase = find.byKey(const ValueKey('chef-unit-purchaseUnit'));
    final manual = find.descendant(
        of: purchase, matching: find.text('Enter another unit'));
    await tester.ensureVisible(manual);
    await tester.tap(manual);
    await tester.pumpAndSettle();
    final custom =
        find.descendant(of: purchase, matching: find.byType(TextFormField));
    await tester.ensureVisible(custom);
    await tester.enterText(custom, 'ladle');
    await tester.pumpAndSettle();
    final changed = find.byKey(const ValueKey('conversion-g-custom:ladle'));
    expect(tester.widget<TextFormField>(changed).initialValue, '');
    await tester.ensureVisible(changed);
    await tester.enterText(changed, '50');
    await tester.tap(find.text('Confirm'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Save work'));
    await tester.pumpAndSettle();
    expect(repo.document.ingredients.single.purchaseUnit.name, 'custom:ladle');
    expect(repo.document.ingredients.single.purchaseUnitInUsageUnits, 50);
    expect(tester.takeException(), isNull);
    if (capture) {
      final koRepo = MemoryChefRepository(ChefRecipe(
          title: '두부 요리',
          steps: '조리합니다.',
          baseServings: 2,
          targetServings: 4,
          ingredients: [
            ChefIngredient(
                id: 'ko',
                name: '두부',
                quantity: 300,
                unit: ChefUnit.g,
                purchaseUnit: ChefUnit.parse('pack'),
                purchaseQuantity: 2,
                purchasePrice: 6000,
                purchaseUnitInUsageUnits: 400,
                yieldPercent: 75)
          ]));
      await tester.pumpWidget(const SizedBox());
      await showChef(tester, 'ko', koRepo);
      for (var i = 0;
          i < 35 && find.text('단가 바로 수정').hitTestable().evaluate().isEmpty;
          i++) {
        await tester.drag(vertical, const Offset(0, -180));
        await tester.pumpAndSettle();
      }
      await tester.tap(find.text('단가 바로 수정'));
      await tester.pumpAndSettle();
      await tester
          .ensureVisible(find.byKey(const ValueKey('conversion-g-pack')));
      await tester.pumpAndSettle();
      await expectLater(find.byType(Overlay).first,
          matchesGoldenFile('../../../.artifacts/chef-unit-conversion-ko.png'));
    }
  });
}
