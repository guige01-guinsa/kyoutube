import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:k_youtube/features/chef/domain/chef_recipe.dart';
import 'package:k_youtube/features/chef/domain/chef_sales.dart';
import 'chef_workbench_test.dart' as workspace;
import 'chef_sales_page_test.dart' as sales;
import 'chef_cost_items_test.dart' show reveal;

const capture = bool.fromEnvironment('CHEF_BUSINESS_CAPTURE');
void main() {
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
  for (final lang in ['ko', 'en']) {
    testWidgets('business preview costs $lang', (tester) async {
      tester.view.physicalSize = const Size(420, 960);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final doc = ChefRecipe.fromJson({
        ...workspace.example(lang).toJson(),
        'markupPercent': 50,
        'costItems': [
          ChefCostItem(
                  id: 'pack',
                  name: lang == 'ko' ? '포장비' : 'Packaging',
                  amount: 500)
              .toJson(),
        ]
      });
      await workspace.showChef(
          tester, lang, workspace.MemoryChefRepository(doc));
      final title =
          find.text(lang == 'ko' ? '추가 비용 관리' : 'Manage additional costs');
      await reveal(tester, title);
      await tester.ensureVisible(title);
      await tester.pumpAndSettle();
      final vertical = find
          .byWidgetPredicate(
              (w) => w is Scrollable && w.axisDirection == AxisDirection.down)
          .first;
      await tester.drag(vertical, const Offset(0, 35));
      await tester.pumpAndSettle();
      await expectLater(find.byType(Scaffold),
          matchesGoldenFile('../../../.artifacts/chef-costs-$lang.png'));
      final pricing = find.text(lang == 'ko' ? '판매가 설정' : 'Set selling price');
      await reveal(tester, pricing);
      await tester.ensureVisible(pricing);
      await tester.pumpAndSettle();
      await tester.drag(vertical, const Offset(0, 35));
      await tester.pumpAndSettle();
      await expectLater(find.byType(Scaffold),
          matchesGoldenFile('../../../.artifacts/chef-pricing-$lang.png'));
    }, skip: !capture);
    testWidgets('business preview sales $lang', (tester) async {
      tester.view.physicalSize = const Size(420, 960);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final repo = sales.MemorySales();
      repo.rows.add(ChefSale(
          id: 1,
          date: DateTime.now(),
          title: lang == 'ko' ? '당근구이' : 'Roasted carrots',
          quantity: 10,
          unitPrice: 3375,
          unitCost: 2250,
          currency: 'KRW'));
      await sales.showSales(tester, lang, repo);
      await expectLater(find.byType(Scaffold),
          matchesGoldenFile('../../../.artifacts/chef-sales-$lang.png'));
    }, skip: !capture);
  }
}
