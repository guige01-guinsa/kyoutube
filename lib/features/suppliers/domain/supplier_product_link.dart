import '../../shopping/domain/shopping_assistant.dart';
import '../../shopping/domain/supplier_request.dart';
import 'public_supplier.dart';

/// Only explicit desktop/mobile aliases are equivalent. Never match suffixes,
/// redirect parameters, arbitrary subdomains or the path of a product URL.
String? supplierLinkHost(String input) {
  final uri = shoppingProductUri(input);
  return uri?.host.toLowerCase().replaceFirst(RegExp(r'^(www|m)\.'), '');
}

List<PublicSupplier> suppliersForProductLink(
        String link, Iterable<PublicSupplier> suppliers) =>
    supplierLinkHost(link) == null
        ? []
        : suppliers
            .where((s) =>
                s.status == 'published' &&
                s.id.isNotEmpty &&
                supplierLinkHost(s.website) == supplierLinkHost(link))
            .toList();

List<ShoppingSupplier> savedSuppliersForProductLink(
        String link, Iterable<ShoppingSupplier> suppliers) =>
    supplierLinkHost(link) == null
        ? []
        : suppliers
            .where((s) => supplierLinkHost(s.website) == supplierLinkHost(link))
            .toList();

class SupplierProductLinkSelection {
  const SupplierProductLinkSelection(
      {required this.url, this.reference, this.supplier});
  final String url;
  final PublicSupplier? reference;
  final ShoppingSupplier? supplier;
}
