import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/search/product_search.dart';
import '../../auth/application/auth_providers.dart';
import '../domain/supplier_request.dart';

/// Incomplete forms remain only in this app session, scoped to the active account.
/// Completed drafts are explicitly saved through the existing server repository.
class RequestEditCheckpoint {
  const RequestEditCheckpoint(
      {required this.request,
      required this.suppliers,
      this.submitted,
      this.uploadedPaths = const {}});
  final SupplierRequest request;
  final List<ShoppingSupplier> suppliers;
  final SupplierRequest? submitted;
  final Set<String> uploadedPaths;
}

final requestEditCheckpointsProvider =
    StateProvider<Map<String, RequestEditCheckpoint>>((ref) {
  ref.watch(activeAccountIdProvider);
  return {};
});

enum PurchaseStage { preparing, active, completed }

PurchaseStage purchaseStage(String status) => switch (status) {
      'sent' || 'accepted' => PurchaseStage.active,
      'received' || 'cancelled' => PurchaseStage.completed,
      _ => PurchaseStage.preparing,
    };

List<SupplierRequest> purchaseRequestsForStage(
    Iterable<SupplierRequest> requests, PurchaseStage stage,
    {String query = ''}) {
  final key = query.trim().toLowerCase();
  return requests
      .where((r) =>
          purchaseStage(r.status) == stage &&
          (key.isEmpty ||
              [
                r.reference,
                r.supplier.name,
                r.buyer,
                ...r.lines.map((l) => l.name)
              ].any((v) => productSearchMatches(v, key))))
      .toList();
}

String purchaseRequestPath(String id) =>
    Uri(path: '/purchases', queryParameters: {'request': id}).toString();

PurchaseStage purchaseStageFromName(String? name) =>
    PurchaseStage.values.where((s) => s.name == name).firstOrNull ??
    PurchaseStage.preparing;
