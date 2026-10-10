import 'package:flutter/material.dart';
import 'purchase_name_field.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../auth/application/auth_providers.dart';
import '../domain/shopping_assistant.dart';
import 'shopping_assistant_dialogs.dart';
import 'shopping_affiliate_panel.dart';
import 'coupang_disclosure.dart';
import '../application/shopping_market_provider.dart';
import 'shopping_market_widgets.dart';

/// Search and checkout belong to the store. Opening a link never records a
/// purchase, changes a quantity or exposes account/workspace identifiers.
class ShoppingStoreSearchDialog extends ConsumerStatefulWidget {
  const ShoppingStoreSearchDialog(
      {super.key, required this.group, this.purchaseQuantity});
  final ShoppingPurchaseGroup group;
  final double? purchaseQuantity;

  @override
  ConsumerState<ShoppingStoreSearchDialog> createState() =>
      _ShoppingStoreSearchDialogState();
}

class _ShoppingStoreSearchDialogState
    extends ConsumerState<ShoppingStoreSearchDialog> {
  final _form = GlobalKey<FormState>();
  late final _query = TextEditingController(text: widget.group.name);
  late final _specification =
      TextEditingController(text: widget.group.specification);
  late final String? _account;
  String? _message;
  String t(String ko, String en) => shopText(context, ko, en);

  bool get _current => mounted && ref.read(activeAccountIdProvider) == _account;

  @override
  void initState() {
    super.initState();
    _account = ref.read(activeAccountIdProvider);
  }

  void _termsChanged(String _) => setState(() {
        _message = null;
      });

  @override
  void dispose() {
    _query.dispose();
    _specification.dispose();
    super.dispose();
  }

  Future<void> _copy() async {
    if (!_current || !_form.currentState!.validate()) return;
    final value =
        shoppingSearchQuery(_query.text, specification: _specification.text);
    try {
      await Clipboard.setData(ClipboardData(text: value));
      if (!_current) return;
      setState(() => _message = t('검색어를 복사했습니다. 다른 브라우저나 쇼핑 앱에서도 검색할 수 있어요.',
          'Search terms copied. You can search in another browser or shopping app.'));
    } catch (_) {
      if (_current) {
        setState(() => _message =
            t('복사하지 못했습니다. 다시 시도해 주세요.', 'Could not copy. Please try again.'));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final quantity = widget.purchaseQuantity ?? widget.group.neededQuantity;
    final market = ref.watch(shoppingMarketProvider);
    return AlertDialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      scrollable: true,
      title: Text(t('구매처 찾기', 'Find a store')),
      content: SizedBox(
        width: 480,
        child: Form(
          key: _form,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const ShoppingMarketSelector(),
              if (quantity != null) ...[
                Text(t(
                    '구매 필요량 ${shoppingNumber(quantity)} ${shopUnit(context, widget.group.unit)}',
                    'Quantity needed: ${shoppingNumber(quantity)} ${shopUnit(context, widget.group.unit)}')),
                const SizedBox(height: 12),
              ],
              if (market.isKorea) ...[
                PurchaseNameField(
                  key: const ValueKey('store-search-query'),
                  controller: _query,
                  onChanged: _termsChanged,
                  maxLength: 250,
                  decoration: InputDecoration(
                      labelText: t('재료·상품명', 'Product name'), counterText: ''),
                  validator: (value) => (value ?? '').trim().isEmpty
                      ? t('검색할 재료나 상품명을 입력해 주세요.', 'Enter a product name.')
                      : null,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  key: const ValueKey('store-search-specification'),
                  controller: _specification,
                  onChanged: _termsChanged,
                  maxLength: 120,
                  minLines: 1,
                  maxLines: 2,
                  decoration: InputDecoration(
                      labelText: t('규격·브랜드', 'Size / brand'),
                      hintText:
                          t('선택 · 예: 500g, 업소용', 'Optional · e.g. 500g, bulk'),
                      counterText: ''),
                ),
                const SizedBox(height: 8),
                Text(
                    t('구매 필요량은 참고용입니다. 원하는 포장 규격이 있을 때만 검색에 추가하세요.',
                        'The quantity is for reference. Add a package size only if you want to search for it.'),
                    style: Theme.of(context).textTheme.bodySmall),
                const SizedBox(height: 16),
                if (_query.text.trim().isNotEmpty)
                  ShoppingAffiliatePanel(
                      ingredient: _query.text.trim(),
                      showEmptyCoupang: true,
                      showCoupangDisclosure: false),
              ] else
                OverseasIngredientSearch(
                    ingredient: widget.group.name,
                    specification: widget.group.specification),
              if (_message != null) ...[
                Text(_message!, semanticsLabel: _message),
                const SizedBox(height: 8),
              ],
              if (market.isKorea)
                TextButton.icon(
                    onPressed: _copy,
                    icon: const Icon(Icons.copy_outlined, size: 18),
                    label: Text(t('검색어 복사', 'Copy search terms'))),
              ExpansionTile(
                tilePadding: EdgeInsets.zero,
                title: Text(
                    t('쇼핑 화면이 겹쳐 보이나요?', 'Shopping page looks too large?'),
                    style: Theme.of(context).textTheme.labelLarge),
                children: [
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Text(t(
                        '쇼핑 화면은 휴대폰 브라우저에서 열립니다. 브라우저 메뉴에서 데스크톱 보기를 끄고, 글자 크기·페이지 확대 설정을 확인해 주세요. 계속 겹치면 검색어를 복사해 다른 브라우저나 쇼핑 앱에서 검색해 보세요.',
                        'Shopping opens in your browser. Turn off desktop view and check its text size and page zoom settings. If the layout still overlaps, copy the search terms into another browser or shopping app.')),
                  )
                ],
              ),
              Text(
                  t('상품·배송비를 확인하고 구매처에서 결제하세요. 돌아온 뒤 구매 기록을 남길 수 있어요.',
                      'Check the product and shipping charges, then pay at the store. Return here to record your purchase.'),
                  style: Theme.of(context).textTheme.bodySmall),
            ],
          ),
        ),
      ),
      actions: [
        CoupangDisclosureFooter(
            ingredients: [_query.text.trim()], respectShoppingMarket: true),
        TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text(t('닫기', 'Close')))
      ],
    );
  }
}
