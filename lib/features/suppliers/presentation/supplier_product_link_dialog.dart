import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../auth/application/auth_providers.dart';
import '../../shopping/domain/shopping_assistant.dart';
import '../../shopping/domain/supplier_request.dart';
import '../../shopping/presentation/shopping_assistant_dialogs.dart';
import '../data/supplier_catalog_repository.dart';
import '../domain/public_supplier.dart';
import '../domain/supplier_product_link.dart';

class SupplierProductLinkDialog extends ConsumerStatefulWidget {
  const SupplierProductLinkDialog(
      {super.key, required this.suppliers, required this.createSupplier});
  final List<ShoppingSupplier> suppliers;
  final Future<ShoppingSupplier?> Function() createSupplier;
  @override
  ConsumerState<SupplierProductLinkDialog> createState() =>
      _SupplierProductLinkDialogState();
}

class _SupplierProductLinkDialogState
    extends ConsumerState<SupplierProductLinkDialog> {
  final _link = TextEditingController();
  late final _suppliers = [...widget.suppliers];
  List<PublicSupplier> _matches = [];
  List<ShoppingSupplier> _savedMatches = [];
  PublicSupplier? _reference;
  ShoppingSupplier? _supplier;
  String? _error;
  bool _busy = false, _searched = false;
  int _generation = 0;
  bool get _marketplace => _reference?.businessKind == 'marketplace';
  String t(String ko, String en) => shopText(context, ko, en);

  @override
  void dispose() {
    _link.dispose();
    super.dispose();
  }

  void _changed(String _) => setState(() {
        _generation++;
        _searched = false;
        _busy = false;
        _reference = null;
        _supplier = null;
        _matches = [];
        _savedMatches = [];
        _error = null;
      });

  Future<void> _find() async {
    final host = supplierLinkHost(_link.text);
    if (host == null) {
      setState(() => _error = t('https://로 시작하는 상품 링크를 입력해 주세요.',
          'Enter a valid https:// product link.'));
      return;
    }
    final generation = ++_generation;
    final owner = ref.read(activeAccountIdProvider);
    setState(() {
      _busy = true;
      _searched = false;
      _error = null;
    });
    try {
      final repo = ref.read(supplierCatalogRepositoryProvider);
      final rows = <PublicSupplier>[];
      // The existing public directory is paginated. Do not silently stop at 30.
      for (var offset = 0; offset <= 10000; offset += 30) {
        final page = await repo.publicReferences(query: host, offset: offset);
        if (!mounted ||
            generation != _generation ||
            owner != ref.read(activeAccountIdProvider)) {
          return;
        }
        rows.addAll(page);
        if (page.length < 30) break;
      }
      setState(() {
        _matches = suppliersForProductLink(_link.text, rows);
        _savedMatches = savedSuppliersForProductLink(_link.text, _suppliers);
        _reference = _matches.length == 1 ? _matches.single : null;
        if (!_marketplace && _savedMatches.length == 1) {
          _supplier = _savedMatches.single;
        }
        _searched = true;
      });
    } catch (_) {
      if (mounted && generation == _generation) {
        setState(() => _error = t('업체를 조회하지 못했습니다. 다시 시도해 주세요.',
            'Could not look up suppliers. Please retry.'));
      }
    } finally {
      if (mounted && generation == _generation) {
        setState(() => _busy = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final candidates = _marketplace || _matches.isEmpty && _savedMatches.isEmpty
        ? _suppliers
            .where((s) => (!_marketplace ||
                (s.publicListingId != _reference!.id &&
                    supplierLinkHost(s.website) !=
                        supplierLinkHost(_link.text))))
            .toList()
        : _savedMatches;
    return AlertDialog(
      scrollable: true,
      title: Text(t('상품 링크로 공급업체 찾기', 'Find supplier from product link')),
      content: SizedBox(
          width: 460,
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(t('상품 페이지 주소를 붙여 넣으세요. 상품명·규격·수량은 다음 화면에서 확인합니다.',
                'Paste a product page link. Confirm its name, specification and quantity next.')),
            const SizedBox(height: 16),
            TextField(
                controller: _link,
                onChanged: _changed,
                maxLength: 2048,
                keyboardType: TextInputType.url,
                autocorrect: false,
                decoration: InputDecoration(
                    labelText: t('상품 링크', 'Product link'),
                    hintText: 'https://')),
            OutlinedButton(
                onPressed: _busy ? null : _find,
                child: Text(_busy
                    ? t('찾는 중…', 'Searching…')
                    : t('공급업체 찾기', 'Find supplier'))),
            if (_searched) ...[
              if (_matches.length > 1)
                DropdownButtonFormField<String>(
                    decoration: InputDecoration(
                        labelText: t('홈페이지 업체', 'Website business')),
                    items: _matches
                        .map((s) =>
                            DropdownMenuItem(value: s.id, child: Text(s.name)))
                        .toList(),
                    onChanged: (id) => setState(() {
                          _reference = _matches.firstWhere((s) => s.id == id);
                          _supplier = null;
                        })),
              if (_reference != null) ...[
                const SizedBox(height: 12),
                Text(_reference!.name,
                    style: Theme.of(context).textTheme.titleMedium),
                Text(_reference!.website),
                if (_reference!.shippingNote.isNotEmpty)
                  Text(_reference!.shippingNote),
              ],
              if (_marketplace)
                Padding(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    child: Text(t(
                        '이곳은 여러 판매자가 입점한 구매 사이트입니다. 상품 페이지에서 실제 판매자를 확인하고 아래에서 선택하거나 등록해 주세요.',
                        'This is a marketplace. Check the actual seller on the product page, then select or register that seller below.'))),
              if (_matches.isEmpty && _savedMatches.isEmpty)
                Text(t('등록된 홈페이지와 일치하지 않습니다. 실제 공급업체를 직접 선택하거나 등록해 주세요.',
                    'No registered website matches. Select or register the actual supplier.')),
              if (candidates.isNotEmpty)
                DropdownButtonFormField<String>(
                    key: ValueKey('${_reference?.id}-${_supplier?.id}'),
                    initialValue: _supplier?.id,
                    isExpanded: true,
                    decoration: InputDecoration(
                        labelText: t('내 거래처 선택', 'Choose my supplier')),
                    items: candidates
                        .map((s) =>
                            DropdownMenuItem(value: s.id, child: Text(s.name)))
                        .toList(),
                    onChanged: (id) => setState(() =>
                        _supplier = candidates.firstWhere((s) => s.id == id))),
              if (_marketplace || _matches.isEmpty && _savedMatches.isEmpty)
                TextButton(
                    onPressed: _busy
                        ? null
                        : () async {
                            final owner = ref.read(activeAccountIdProvider);
                            final result = await widget.createSupplier();
                            if (!mounted ||
                                owner != ref.read(activeAccountIdProvider) ||
                                result == null) {
                              return;
                            }
                            setState(() {
                              if (_marketplace &&
                                  (result.publicListingId == _reference!.id ||
                                      supplierLinkHost(result.website) ==
                                          supplierLinkHost(_link.text))) {
                                _error = t('상품의 실제 판매자를 선택해 주세요.',
                                    'Choose the actual product seller.');
                                return;
                              }
                              _suppliers.removeWhere((s) => s.id == result.id);
                              _suppliers.add(result);
                              _supplier = result;
                            });
                          },
                    child:
                        Text(t('실제 공급업체 새로 등록', 'Register actual supplier'))),
            ],
            if (_error != null)
              Text(_error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error)),
          ])),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(t('취소', 'Cancel'))),
        FilledButton(
            onPressed: !_searched ||
                    _busy ||
                    shoppingProductUri(_link.text) == null ||
                    (_supplier == null && (_reference == null || _marketplace))
                ? null
                : () => Navigator.pop(
                    context,
                    SupplierProductLinkSelection(
                        url: _link.text.trim(),
                        reference: _reference,
                        supplier: _supplier)),
            child: Text(t('이 업체로 품목 작성', 'Add item for this supplier'))),
      ],
    );
  }
}
