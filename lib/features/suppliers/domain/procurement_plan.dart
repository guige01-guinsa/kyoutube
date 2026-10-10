import 'dart:math' as math;
import '../../kitchen/domain/shopping_units.dart';
import '../../shopping/domain/supplier_request.dart';
import '../../shopping/domain/shopping_assistant.dart';
import 'supplier_catalog.dart';

enum ProcurementPriority { fewestSuppliers, lowestPrice, highestRating }

class IngredientCandidates {
  const IngredientCandidates({required this.line, required this.choices});
  final SupplierRequestLine line;
  final List<PurchaseCandidate> choices;
}

class PurchaseCandidate {
  const PurchaseCandidate(this.offer, {this.contentUnitsPerPurchaseUnit});
  final SupplierOffer offer;
  // Explicit buyer conversion, e.g. 1 purchased head = 1.5 kg of this product.
  final double? contentUnitsPerPurchaseUnit;
  int? packs(SupplierRequestLine line) {
    final q = line.quantity, p = offer.product;
    if (q == null ||
        !q.isFinite ||
        q <= 0 ||
        !p.contentQuantity.isFinite ||
        p.contentQuantity <= 0) {
      return null;
    }
    final converted = line.unit == p.contentUnit
        ? q
        : convertPurchaseQuantity(q, line.unit, p.contentUnit) ??
            (contentUnitsPerPurchaseUnit != null &&
                    contentUnitsPerPurchaseUnit!.isFinite &&
                    contentUnitsPerPurchaseUnit! > 0
                ? q * contentUnitsPerPurchaseUnit!
                : null);
    if (converted == null || !converted.isFinite || converted <= 0) return null;
    final count = math.max(
        p.minimumPacks, (converted / p.contentQuantity - 1e-10).ceil());
    return count > 0 && count <= 1e9 ? count : null;
  }
}

class PlannedPurchase {
  const PlannedPurchase(this.line, this.candidate, this.packs);
  final SupplierRequestLine line;
  final PurchaseCandidate candidate;
  final int packs;
}

class ProcurementPlan {
  ProcurementPlan(this.purchases,
      {required this.exhaustive, required this.priority, required this.asOf});
  final List<PlannedPurchase> purchases;
  final bool exhaustive;
  final ProcurementPriority priority;
  final DateTime asOf;
  Set<String> get supplierIds =>
      purchases.map((p) => p.candidate.offer.supplier.id).toSet();
  List<PlannedPurchase> forSupplier(String id) =>
      purchases.where((p) => p.candidate.offer.supplier.id == id).toList();
  double? subtotal(String id) {
    final rows = forSupplier(id);
    if (rows.any((r) =>
        !r.candidate.offer.product.priceCurrent(asOf) ||
        r.candidate.offer.product.tax == 'unknown')) {
      return null;
    }
    return rows.fold<double>(
        0, (sum, r) => sum + r.packs * r.candidate.offer.product.price!);
  }

  double? delivery(String id) {
    final s = forSupplier(id).first.candidate.offer.supplier;
    final amount = subtotal(id);
    if (amount != null &&
        s.freeShippingFrom != null &&
        amount >= s.freeShippingFrom!) {
      return 0;
    }
    return s.shippingFee;
  }

  int get quotesNeeded => supplierIds
      .where((id) => subtotal(id) == null || delivery(id) == null)
      .length;
  int get minimumOrderFailures => supplierIds.where((id) {
        final minimum =
            forSupplier(id).first.candidate.offer.supplier.minimumOrder;
        return subtotal(id) != null && subtotal(id)! < minimum;
      }).length;
  double? get total => quotesNeeded > 0
      ? null
      : supplierIds.fold<double>(
          0, (sum, id) => sum + subtotal(id)! + delivery(id)!);
  double get knownTotal => supplierIds.fold<double>(
      0, (sum, id) => sum + (subtotal(id) ?? 0) + (delivery(id) ?? 0));
  List<num> get score {
    // Score each partial combination in one pass, including shipping once per supplier.
    final suppliers = <String, CatalogSupplier>{};
    final amounts = <String, double?>{};
    var unrated = 0, quotes = 0, minimumFailures = 0;
    var stars = 0.0, known = 0.0;
    for (final row in purchases) {
      final supplier = row.candidate.offer.supplier;
      final product = row.candidate.offer.product;
      suppliers[supplier.id] = supplier;
      amounts.putIfAbsent(supplier.id, () => 0);
      if (!product.priceCurrent(asOf) || product.tax == 'unknown') {
        amounts[supplier.id] = null;
      } else if (amounts[supplier.id] != null) {
        amounts[supplier.id] =
            amounts[supplier.id]! + row.packs * product.price!;
      }
      if (supplier.rating == null) unrated++;
      stars += supplier.rating ?? 0;
    }
    for (final supplier in suppliers.values) {
      final amount = amounts[supplier.id];
      final shipping = amount != null &&
              supplier.freeShippingFrom != null &&
              amount >= supplier.freeShippingFrom!
          ? 0.0
          : supplier.shippingFee;
      if (amount == null || shipping == null) quotes++;
      if (amount != null && amount < supplier.minimumOrder) minimumFailures++;
      known += (amount ?? 0) + (shipping ?? 0);
    }
    return switch (priority) {
      ProcurementPriority.fewestSuppliers => [
          minimumFailures,
          suppliers.length,
          quotes,
          known,
          unrated,
          -stars
        ],
      ProcurementPriority.lowestPrice => [
          minimumFailures,
          quotes,
          known,
          suppliers.length,
          unrated,
          -stars
        ],
      ProcurementPriority.highestRating => [
          minimumFailures,
          unrated,
          -stars,
          quotes,
          known,
          suppliers.length
        ],
    };
  }

  SupplierRequest draftFor(String id, ShoppingSupplier supplier,
      {required bool english}) {
    final rows = forSupplier(id);
    final currency = rows.first.candidate.offer.supplier.currency;
    final sum = subtotal(id), shipping = delivery(id);
    final notes = english
        ? 'Candidate-based draft. Estimate as of ${asOf.toIso8601String().substring(0, 10)}. Items: ${shoppingNumber(sum)} $currency; shipping: ${shoppingNumber(shipping)} $currency. Confirm availability, taxes, delivery and minimum order before sending.'
        : '선택 후보 기준 초안 · ${asOf.toIso8601String().substring(0, 10)} 비교. 상품액 ${shoppingNumber(sum)} $currency · 배송비 ${shoppingNumber(shipping)} $currency. 미표시 금액은 견적 필요. 발송 전 납품 가능 여부·세금·배송비·최소 주문 조건을 확인해 주세요.';
    return SupplierRequest(
        id: newShoppingId(),
        supplier: supplier,
        currency: currency,
        notes: notes,
        lines: rows.map((r) {
          final p = r.candidate.offer.product;
          final spec =
              '${p.name} · ${p.brand} · ${shoppingNumber(p.contentQuantity)} ${p.contentUnit}/${p.saleUnit} · ${english ? 'Need' : '구매 필요'} ${shoppingNumber(r.line.quantity)} ${r.line.unit}';
          return SupplierRequestLine(
              id: newShoppingId(),
              name: r.line.name,
              quantity: r.packs.toDouble(),
              unit: p.saleUnit,
              price:
                  p.priceCurrent(asOf) && p.tax != 'unknown' ? p.price : null,
              spec: spec.length > 300 ? spec.substring(0, 300) : spec,
              sourceIds: r.line.sourceIds);
        }).toList());
  }
}

/// Exact for small candidate spaces; a bounded beam prevents UI freezes on
/// large orders. The result explicitly discloses when combinations were pruned.
ProcurementPlan createProcurementPlan(
    List<IngredientCandidates> items, ProcurementPriority priority,
    {DateTime? now, int beamWidth = 4096}) {
  if (items.isEmpty || items.length > 100 || beamWidth < 1) {
    throw const FormatException('Choose 1–100 ingredients');
  }
  final lineIds = <String>{}, currencies = <String>{};
  for (final item in items) {
    if (!lineIds.add(item.line.id) ||
        item.choices.isEmpty ||
        item.choices.length > 3 ||
        item.choices.map((c) => c.offer.supplier.id).toSet().length !=
            item.choices.length) {
      throw const FormatException(
          'Choose 1–3 distinct suppliers per ingredient');
    }
    for (final c in item.choices) {
      if (c.packs(item.line) == null) {
        throw const FormatException('Purchase conversion required');
      }
      if (!c.offer.product.active ||
          !c.offer.supplier.published ||
          c.offer.product.supplierId != c.offer.supplier.id) {
        throw const FormatException('Product unavailable');
      }
      currencies.add(c.offer.supplier.currency);
    }
  }
  if (currencies.length != 1) {
    throw const FormatException('Use one currency per plan');
  }
  final asOf = now ?? DateTime.now();
  final searchWidth = items.length <= 12
      ? beamWidth
      : math.min(beamWidth, math.max(64, 8192 ~/ items.length));
  var states = <List<PlannedPurchase>>[[]];
  var exhaustive = true;
  for (final item in items) {
    final expanded =
        <({List<PlannedPurchase> rows, List<num> score, String tie})>[];
    for (final state in states) {
      for (final c in item.choices) {
        final rows = [
          ...state,
          PlannedPurchase(item.line, c, c.packs(item.line)!)
        ];
        expanded.add((
          rows: rows,
          score: ProcurementPlan(rows,
                  exhaustive: true, priority: priority, asOf: asOf)
              .score,
          tie: rows.map((r) => r.candidate.offer.product.id).join('|')
        ));
      }
    }
    expanded.sort((a, b) {
      for (var i = 0; i < a.score.length; i++) {
        final order = a.score[i].compareTo(b.score[i]);
        if (order != 0) return order;
      }
      return a.tie.compareTo(b.tie);
    });
    if (expanded.length > searchWidth) exhaustive = false;
    states = expanded.take(searchWidth).map((s) => s.rows).toList();
  }
  return ProcurementPlan(List.unmodifiable(states.first),
      exhaustive: exhaustive, priority: priority, asOf: asOf);
}
