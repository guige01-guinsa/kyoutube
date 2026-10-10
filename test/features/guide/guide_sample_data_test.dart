import 'package:k_youtube/features/guide/domain/guide_sample_tasks.dart';
import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:k_youtube/features/guide/domain/guide_sample_data.dart';
import 'package:k_youtube/features/guide/domain/guide_curriculum.dart';
import 'package:k_youtube/features/guide/application/guide_sample_store.dart';
import 'package:k_youtube/features/chef/domain/chef_recipe.dart';
import 'package:k_youtube/features/chef/domain/chef_sales.dart';
import 'package:k_youtube/features/suppliers/domain/procurement_plan.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues(
      {'production-record-sentinel': 'unchanged'}));
  test(
      'both languages have ready records, complete costing and distinct connected workflows',
      () {
    for (final en in [false, true]) {
      final d = GuideSampleData.seed(english: en, now: DateTime(2026, 9, 17));
      expect(
          guideSampleTasks.keys.toSet(), guideLessons.map((l) => l.id).toSet());
      expect(
          guideSampleTasks.values
              .every((t) => t.ko.isNotEmpty && t.en.isNotEmpty),
          isTrue);
      expect(d.recipes.length, 5);
      expect(d.products.length, 6);
      expect(d.requests.length, 3);
      expect(d.sales.length, 8);
      expect(d.requests.map((r) => r.status),
          containsAll(['draft', 'accepted', 'received']));
      expect(
          d.recipes.values
              .every((r) => r.portionCost != null && r.steps.contains('\n')),
          isTrue);
      expect(
          d.products.every((p) => p.region.isNotEmpty && p.origin.isNotEmpty),
          isTrue);
      expect(
          d.purchase
              .compare(criterion: ProcurementPriority.fewestSuppliers)!
              .total,
          16000);
      expect(
          d.purchase.compare(criterion: ProcurementPriority.lowestPrice)!.total,
          8000);
      expect(
          d.purchase
              .compare(criterion: ProcurementPriority.highestRating)!
              .total,
          25000);
      expect(
          GuideSampleData.fromJson(jsonDecode(jsonEncode(d.toJson()))).toJson(),
          d.toJson());
    }
  });
  test(
      'costing, servings and yield never change purchase quantities or history',
      () {
    final d = GuideSampleData.seed(english: false),
        before =
            Map.of(GuideSampleData.seed(english: false).purchase.quantities);
    final cost = d.recipe.portionCost!;
    d.changeRecipe({'targetServings': 20});
    expect(d.recipe.portionCost, closeTo(cost, .0001));
    final first = d.recipe.ingredients.first;
    d.changeIngredient(
        0, ChefIngredient.fromJson({...first.toJson(), 'yieldPercent': 50}));
    expect(d.recipe.portionCost!, greaterThan(cost));
    expect(d.purchase.quantities, before);
    expect(d.bought, isEmpty);
    d.bought.add('tofu');
    expect(d.recipe.ingredients.first.quantity, first.quantity);
  });
  test(
      'candidates, price comparison, per-supplier drafts and repeat retain the right data',
      () {
    final d = GuideSampleData.seed(english: true);
    d.purchase.quantity('carrot', 2);
    d.purchase.priority = ProcurementPriority.lowestPrice;
    d.createRequests();
    final newRequests = d.requests.take(2).toList();
    expect(newRequests.length, 2);
    expect(newRequests.expand((r) => r.lines).length, 3);
    final carrot = newRequests
        .expand((r) => r.lines)
        .firstWhere((l) => l.name == 'Carrot');
    expect(carrot.quantity, 2);
    expect(carrot.price, 2000);
    d.updateRequest(d.request,
        fields: {'buyer': 'Sample changed buyer'}, status: 'sent');
    final source = d.request;
    d.repeatRequest(source);
    expect(d.request.id, isNot(source.id));
    expect(d.request.buyer, 'Sample changed buyer');
    expect(d.request.status, 'draft');
    expect(d.request.deliveryDate, isEmpty);
    expect(d.request.lines.every((l) => l.price == null), isTrue);
  });
  test('sales preserve historical cost and saved versions remain independent',
      () {
    final d = GuideSampleData.seed(english: true, now: DateTime(2026, 9, 17));
    final old = d.versions['bowl']!.first.portionCost;
    final before = d.totals(ChefSalesPeriod.day);
    final price = d.recipe.sellingPrice!, cost = d.recipe.portionCost!;
    d.recordSale(7);
    expect(d.totals(ChefSalesPeriod.day).revenue - before.revenue, price * 7);
    expect(d.totals(ChefSalesPeriod.day).cost - before.cost,
        closeTo(cost * 7, .0001));
    d.changeRecipe({'markupPercent': 99});
    d.snapshot();
    expect(d.sales.last.unitPrice, price);
    expect(d.versions['bowl']![1].portionCost, old);
    expect(d.versions['bowl']!.first.markupPercent, 99);
  });
  test('save resume and reset affect only this language practice records',
      () async {
    final ko = GuideSampleStore(false), en = GuideSampleStore(true);
    final d = await ko.load();
    d.changeRecipe({'title': '연습 수정'});
    d.purchase.quantity('tofu', 3);
    d.practiced.add('buy-quantity');
    await ko.save(d);
    expect((await ko.load()).recipe.title, '연습 수정');
    expect((await ko.load()).purchase.quantities['tofu'], 3);
    final e = await en.load();
    e.businessName = 'Sample edited business';
    await en.save(e);
    await ko.reset();
    expect((await ko.load()).recipe.title, isNot('연습 수정'));
    expect((await en.load()).businessName, 'Sample edited business');
    expect(
        (await SharedPreferences.getInstance())
            .getString('production-record-sentinel'),
        'unchanged');
    expect(guideLessons.length, 24);
  });
  test('corrupt storage recovers without deleting unrelated data', () async {
    final store = GuideSampleStore(false),
        prefs = await SharedPreferences.getInstance();
    await prefs.setString(store.key, '{broken');
    final d = await store.load();
    expect(store.recovered, isTrue);
    expect(d.requests, isNotEmpty);
    expect(prefs.getString('production-record-sentinel'), 'unchanged');
  });
  test('invalid comparison data is rejected before saving over a good snapshot',
      () async {
    final store = GuideSampleStore(true), d = await store.load();
    d.purchase.candidates['tofu']!.add('B');
    await expectLater(store.save(d), throwsFormatException);
    expect((await store.load()).purchase.candidates['tofu'], {'A', 'C', 'D'});
  });
}
