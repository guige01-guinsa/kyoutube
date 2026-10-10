import '../../shopping/domain/supplier_request.dart';
import '../../suppliers/domain/procurement_plan.dart';
import '../../suppliers/domain/supplier_catalog.dart';

/// Entirely synthetic and memory-only. Uses the production comparison algorithm.
class GuidePurchaseExample {
  final quantities = <String, double>{'carrot': 1, 'onion': 1, 'tofu': 1};
  final selected = <String>{'carrot', 'onion', 'tofu'};
  final candidates = <String, Set<String>>{
    'carrot': {'A', 'B', 'D'},
    'onion': {'A', 'B', 'D'},
    'tofu': {'A', 'C', 'D'},
  };
  final favorites = <String>{};
  ProcurementPriority priority = ProcurementPriority.fewestSuppliers;
  static final asOf = DateTime.utc(2026, 1, 1);
  static const prices = <String, Map<String, double>>{
    'A': {'carrot': 5000, 'onion': 4000, 'tofu': 6000},
    'B': {'carrot': 2000, 'onion': 2000},
    'C': {'carrot': 4000, 'tofu': 3000},
    'D': {'carrot': 8000, 'onion': 7000, 'tofu': 9000},
  };
  bool toggleCandidate(String item, String supplier, bool checked) {
    final choices = candidates[item]!;
    if (!prices[supplier]!.containsKey(item)) return false;
    if (checked && !choices.contains(supplier) && choices.length >= 3) {
      return false;
    }
    checked ? choices.add(supplier) : choices.remove(supplier);
    return true;
  }

  void quantity(String item, double amount) {
    if (!amount.isFinite || amount <= 0 || amount > 100) {
      throw ArgumentError('Invalid training quantity');
    }
    quantities[item] = amount;
  }

  List<String> available(String item) =>
      prices.keys.where((s) => prices[s]!.containsKey(item)).toList();
  ProcurementPlan? compare({ProcurementPriority? criterion}) {
    if (selected.isEmpty || selected.any((item) => candidates[item]!.isEmpty)) {
      return null;
    }
    return createProcurementPlan([
      for (final item in selected)
        IngredientCandidates(
            line: SupplierRequestLine(
                id: item, name: item, quantity: quantities[item], unit: 'kg'),
            choices: [
              for (final s in candidates[item]!)
                PurchaseCandidate(SupplierOffer(
                  CatalogSupplier(
                      id: s,
                      name: 'Training $s',
                      published: true,
                      shippingFee: s == 'B' || s == 'C' ? 500 : 1000,
                      rating: switch (s) {
                        'A' => 4.1,
                        'B' => 4.5,
                        'C' => 4.4,
                        _ => 4.9
                      },
                      reviewCount: 10),
                  CatalogProduct(
                      id: '$s-$item',
                      supplierId: s,
                      name: item,
                      price: prices[s]![item],
                      priceValidUntil: DateTime.utc(2026, 12, 31)),
                )),
            ]),
    ], criterion ?? priority, now: asOf);
  }
}
