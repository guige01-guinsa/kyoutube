import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:k_youtube/features/shopping/domain/supplier_request.dart';
import 'package:k_youtube/features/suppliers/domain/supplier_catalog.dart';
import 'package:k_youtube/features/suppliers/domain/procurement_plan.dart';
import 'package:k_youtube/features/suppliers/data/supplier_catalog_repository.dart';

final day = DateTime(2026, 9, 15);
PurchaseCandidate offer(String vendor, String product,
        {double? price = 10,
        double? shipping = 0,
        double? rating = 4,
        double content = 1,
        String unit = 'kg',
        int minimum = 1,
        double orderMinimum = 0,
        double? freeFrom,
        String currency = 'KRW',
        DateTime? valid,
        bool expired = false}) =>
    PurchaseCandidate(SupplierOffer(
        CatalogSupplier(
            id: vendor,
            name: vendor,
            published: true,
            shippingFee: shipping,
            rating: rating,
            reviewCount: rating == null ? 0 : 3,
            minimumOrder: orderMinimum,
            freeShippingFrom: freeFrom,
            currency: currency),
        CatalogProduct(
            id: product,
            supplierId: vendor,
            name: product,
            contentQuantity: content,
            contentUnit: unit,
            price: price,
            minimumPacks: minimum,
            priceValidUntil: expired ? DateTime(2026, 9, 14) : valid ?? day)));
IngredientCandidates item(String id, List<PurchaseCandidate> choices,
        {double quantity = 1, String unit = 'kg'}) =>
    IngredientCandidates(
        line: SupplierRequestLine(
            id: id,
            name: id,
            quantity: quantity,
            unit: unit,
            sourceIds: ['source-$id']),
        choices: choices);
void main() {
  test('three candidates are per ingredient, not per order', () {
    final rows = [
      for (var i = 0; i < 4; i++) item('ingredient$i', [offer('v$i', 'p$i')])
    ];
    final plan = createProcurementPlan(
        rows, ProcurementPriority.fewestSuppliers,
        now: day);
    expect(plan.supplierIds.length, 4);
    expect(plan.purchases.length, 4);
  });
  test(
      'consolidation chooses common supplier instead of independent first choices',
      () {
    final plan = createProcurementPlan([
      item('onion', [offer('A', 'a'), offer('B', 'b', price: 50)]),
      item('egg', [offer('C', 'c'), offer('B', 'b2', price: 50)])
    ], ProcurementPriority.fewestSuppliers, now: day);
    expect(plan.supplierIds, {'B'});
    expect(plan.total, 100);
    expect(plan.exhaustive, true);
  });
  test('price selection includes shipping per supplier, not per ingredient',
      () {
    final plan = createProcurementPlan([
      item('onion', [
        offer('A', 'a', price: 8, shipping: 20),
        offer('B', 'b', price: 10, shipping: 3)
      ]),
      item('egg', [
        offer('C', 'c', price: 8, shipping: 20),
        offer('B', 'b2', price: 10, shipping: 3)
      ])
    ], ProcurementPriority.lowestPrice, now: day);
    expect(plan.supplierIds, {'B'});
    expect(plan.total, 23);
  });
  test('pack rounding and purchase unit conversion affect price', () {
    final plan = createProcurementPlan([
      item(
          'onion',
          [
            offer('A', 'a', content: 2, price: 5),
            offer('B', 'b', content: 3, price: 9)
          ],
          quantity: 2500,
          unit: 'g')
    ], ProcurementPriority.lowestPrice, now: day);
    expect(plan.supplierIds, {'B'});
    expect(plan.purchases.single.packs, 1);
    expect(plan.total, 9);
  });
  test('unknown and expired prices or delivery never become zero', () {
    for (final bad in [
      offer('A', 'a', price: null),
      offer('A', 'a', shipping: null),
      offer('A', 'a', expired: true)
    ]) {
      final plan = createProcurementPlan([
        item('onion', [bad, offer('B', 'b', price: 20)])
      ], ProcurementPriority.lowestPrice, now: day);
      expect(plan.supplierIds, {'B'});
      final unknown = createProcurementPlan([
        item('onion', [bad])
      ], ProcurementPriority.lowestPrice, now: day);
      expect(unknown.total, isNull);
      expect(unknown.quotesNeeded, 1);
    }
  });
  test('ratings are primary when requested, unrated suppliers remain distinct',
      () {
    final plan = createProcurementPlan([
      item('x', [
        offer('A', 'a', price: 1, rating: null),
        offer('B', 'b', price: 3, rating: 3),
        offer('C', 'c', price: 100, rating: 4.8)
      ])
    ], ProcurementPriority.highestRating, now: day);
    expect(plan.supplierIds, {'C'});
  });
  test('minimum order is flagged and unrequested ingredients are not added',
      () {
    final plan = createProcurementPlan([
      item('x', [offer('A', 'a', orderMinimum: 100)])
    ], ProcurementPriority.lowestPrice, now: day);
    expect(plan.minimumOrderFailures, 1);
    expect(plan.purchases.single.packs, 1);
  });
  test('free shipping threshold and minimum packs are included', () {
    final plan = createProcurementPlan([
      item('x',
          [offer('A', 'a', price: 10, shipping: 20, freeFrom: 30, minimum: 3)])
    ], ProcurementPriority.lowestPrice, now: day);
    expect(plan.purchases.single.packs, 3);
    expect(plan.total, 30);
  });
  test(
      'missing candidates, duplicate vendor, fourth candidate and mixed currencies fail',
      () {
    final invalid = [
      item('x', []),
      item('x', [offer('A', 'a'), offer('A', 'b')]),
      item('x', [for (var i = 0; i < 4; i++) offer('$i', 'p$i')]),
      item('x', [offer('A', 'a'), offer('B', 'b', currency: 'USD')])
    ];
    for (final row in invalid) {
      expect(
          () => createProcurementPlan(
              [row], ProcurementPriority.fewestSuppliers,
              now: day),
          throwsFormatException);
    }
  });
  test(
      'unknown purchase conversion requires explicit value and never guesses cooking amounts',
      () {
    final c = offer('A', 'a', unit: 'kg');
    final line = item('x', [c], unit: 'head').line;
    expect(c.packs(line), isNull);
    expect(
        PurchaseCandidate(c.offer, contentUnitsPerPurchaseUnit: 1.5)
            .packs(line),
        2);
  });
  test(
      'bounded search explicitly reports that global optimum is not guaranteed',
      () {
    final plan = createProcurementPlan([
      item('x', [offer('A', 'a'), offer('B', 'b')]),
      item('y', [offer('A', 'a2'), offer('C', 'c')])
    ], ProcurementPriority.lowestPrice, now: day, beamWidth: 1);
    expect(plan.exhaustive, false);
  });
  test(
      'draft groups each ingredient once, retains source links and stays unsaved',
      () {
    final plan = createProcurementPlan([
      item('onion', [offer('A', 'a')]),
      item('egg', [offer('A', 'b')])
    ], ProcurementPriority.fewestSuppliers, now: day);
    final draft = plan.draftFor(
        'A', const ShoppingSupplier(id: 'personal-a', name: 'A'),
        english: false);
    expect(draft.lines.map((l) => l.name), ['onion', 'egg']);
    expect(draft.lines.first.sourceIds, ['source-onion']);
    expect(draft.supplier.id, 'personal-a');
    expect(draft.revision, 0);
    expect(draft.status, 'draft');
  });
  test('image upload rejects SVG, fake MIME and oversized files', () {
    expect(
        supplierImageType(Uint8List.fromList('<svg>alert(1)</svg>'.codeUnits)),
        isNull);
    expect(supplierImageType(Uint8List(5 * 1024 * 1024 + 1)), isNull);
    expect(
        supplierImageType(
            Uint8List.fromList([137, 80, 78, 71, 13, 10, 26, 10, 0, 0, 0, 0])),
        'png');
  });
  test('large orders retain every ingredient and disclose bounded search', () {
    final plan = createProcurementPlan([
      for (var i = 0; i < 100; i++)
        item('ingredient-$i', [
          for (var j = 0; j < 3; j++)
            offer('vendor-$j', 'product-$i-$j', price: 10.0 + j),
        ])
    ], ProcurementPriority.lowestPrice, now: day);
    expect(plan.purchases.length, 100);
    expect(plan.purchases.map((p) => p.line.id).toSet().length, 100);
    expect(plan.supplierIds, {'vendor-0'});
    expect(plan.total, 1000);
    expect(plan.exhaustive, isFalse);
  });
}
