import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../auth/application/auth_providers.dart';
import '../../shopping/domain/shopping_assistant.dart';
import '../../shopping/domain/supplier_request.dart';
import '../domain/procurement_plan.dart';

/// Local to this running app and cleared on every account transition.
final procurementSessionsProvider =
    Provider<Map<String, ProcurementSession>>((ref) {
  ref.watch(activeAccountIdProvider);
  return {};
});

class ProcurementSession {
  ProcurementSession(List<ShoppingPurchaseGroup> groups)
      : fingerprint = sourceFingerprint(groups),
        lines = {
          for (final g in groups) g.key: SupplierRequestLine.fromGroup(g)
        };
  static String sourceFingerprint(List<ShoppingPurchaseGroup> groups) => groups
      .map((g) =>
          '${g.key}:${g.neededQuantity}:${g.sources.map((s) => s.item.id).join(',')}')
      .join('|');
  final String fingerprint;
  final Map<String, SupplierRequestLine> lines;
  final selected = <String>{};
  final choices = <String, List<PurchaseCandidate>>{};
  final drafts = <String, SupplierRequest>{};
  final saved = <String, SupplierRequest>{};
  ProcurementPriority priority = ProcurementPriority.fewestSuppliers;
  ProcurementPlan? plan;
  int step = 0;
}
