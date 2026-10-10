import '../../../core/format/user_number.dart';
import 'package:flutter/material.dart';

import '../../../core/localization/localized_text.dart';
import '../domain/shopping_review_drafts.dart';
import '../domain/shopping_units.dart';

Future<ShoppingReviewDraftItem?> showShoppingPurchaseQuantityDialog(
  BuildContext context,
  ShoppingReviewDraftItem item,
) =>
    showDialog<ShoppingReviewDraftItem>(
      context: context,
      builder: (_) => _PurchaseQuantityDialog(item: item),
    );

class _PurchaseQuantityDialog extends StatefulWidget {
  const _PurchaseQuantityDialog({required this.item});
  final ShoppingReviewDraftItem item;
  @override
  State<_PurchaseQuantityDialog> createState() =>
      _PurchaseQuantityDialogState();
}

class _PurchaseQuantityDialogState extends State<_PurchaseQuantityDialog> {
  late final _name = TextEditingController(text: widget.item.name);
  late final _quantity = TextEditingController(
      text: widget.item.purchaseConfirmed ? widget.item.quantityInput : '');
  late String? _unit =
      widget.item.purchaseConfirmed && isPurchaseUnit(widget.item.unit)
          ? widget.item.unit
          : null;
  late String _category = purchaseUnits
      .firstWhere((u) => u.code == _unit,
          orElse: () => purchaseUnits.firstWhere((u) => u.code == 'pack'))
      .category;
  String? _error;
  final _factor = TextEditingController();
  (double, String)? _conversionFrom;

  @override
  void dispose() {
    _name.dispose();
    _quantity.dispose();
    _factor.dispose();
    super.dispose();
  }

  void _changeUnit(String next) {
    final amount = parseUserNumber(_quantity.text.trim());
    final from =
        amount != null && _unit != null ? (amount, _unit!) : _conversionFrom;
    _unit = next;
    _factor.clear();
    if (from == null) return;
    final converted = convertPurchaseQuantity(from.$1, from.$2, next);
    _conversionFrom = converted == null ? from : null;
    _quantity.text = converted?.toString() ?? '';
  }

  void _save({bool withoutQuantity = false}) {
    final quantity = parseUserNumber(_quantity.text.trim());
    if (_name.text.trim().isEmpty) {
      setState(() => _error = '재료 이름을 입력해 주세요.');
      return;
    }
    if (!withoutQuantity &&
        (quantity == null ||
            !quantity.isFinite ||
            quantity <= 0 ||
            quantity > 1e9 ||
            !isPurchaseUnit(_unit))) {
      setState(() => _error = '구매 수량과 단위를 모두 입력해 주세요.');
      return;
    }
    if (!withoutQuantity &&
        (quantity! * 1000000 - (quantity * 1000000).round()).abs() > 0.0001) {
      setState(() => _error = '구매 수량은 소수점 여섯째 자리까지 입력해 주세요.');
      return;
    }
    Navigator.pop(
        context,
        ShoppingReviewDraftItem(
          localId: widget.item.localId,
          ingredientText: widget.item.ingredientText,
          name: _name.text.trim(),
          quantityInput: withoutQuantity ? '' : _quantity.text.trim(),
          quantity: withoutQuantity ? null : quantity,
          unit: withoutQuantity ? null : _unit,
          selected: widget.item.selected,
          needsReview: widget.item.needsReview,
          purchaseConfirmed: true,
        ));
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: const LocalizedText('구매 수량·단위'),
        content: SizedBox(
            width: 360,
            child: SingleChildScrollView(
                child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const LocalizedText('조리 원문',
                    style: TextStyle(fontWeight: FontWeight.w600)),
                LocalizedText(widget.item.ingredientText),
                const SizedBox(height: 8),
                const LocalizedText('구매 정보만 저장합니다. 레시피의 조리 수량·단위는 바뀌지 않습니다.'),
                const SizedBox(height: 16),
                TextField(
                    controller: _name,
                    maxLength: 200,
                    decoration:
                        InputDecoration(labelText: context.tr('구매 재료명'))),
                TextField(
                    controller: _quantity,
                    key: const ValueKey('purchase-quantity'),
                    maxLength: 32,
                    onChanged: (_) => setState(() => _conversionFrom = null),
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                    decoration: InputDecoration(
                        labelText: context.tr('구매 수량'),
                        helperText: context.tr('예: 두부 2팩, 참기름 1병, 달걀 10개'))),
                const SizedBox(height: 8),
                Wrap(spacing: 6, runSpacing: 4, children: [
                  for (final category in shoppingUnitCategories)
                    ChoiceChip(
                        label: LocalizedText(category),
                        selected: _category == category,
                        onSelected: (_) => setState(() {
                              _category = category;
                              _changeUnit(purchaseUnits
                                  .firstWhere((u) => u.category == category)
                                  .code);
                            })),
                ]),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                    key: ValueKey('purchase-unit-$_category'),
                    initialValue: _unit,
                    isExpanded: true,
                    decoration: InputDecoration(labelText: context.tr('구매 단위')),
                    hint: const LocalizedText('구매 단위를 선택해 주세요.'),
                    items: [
                      for (final unit in purchaseUnits
                          .where((u) => u.category == _category))
                        DropdownMenuItem(
                            value: unit.code, child: LocalizedText(unit.label))
                    ],
                    onChanged: (unit) {
                      if (unit != null) setState(() => _changeUnit(unit));
                    }),
                const SizedBox(height: 8),
                const LocalizedText(
                    '구매 단위끼리만 환산합니다. 포장량이 다르면 환산 기준 또는 최종 구매량을 입력해 주세요.'),
                if (_conversionFrom != null) ...[
                  const SizedBox(height: 8),
                  LocalizedText(
                      '${shoppingUnitLabel(_conversionFrom!.$2)} → ${shoppingUnitLabel(_unit)}'),
                  TextField(
                      controller: _factor,
                      key: const ValueKey('purchase-conversion-factor'),
                      keyboardType:
                          const TextInputType.numberWithOptions(decimal: true),
                      decoration: InputDecoration(
                          labelText: context.tr('환산 기준 (기존 1단위당 새 단위 수량)')),
                      onChanged: (value) {
                        final from = _conversionFrom!;
                        final converted = convertPurchaseQuantity(
                            from.$1, from.$2, _unit!,
                            unitsPerOne: parseUserNumber(value));
                        _quantity.text = converted?.toString() ?? '';
                      }),
                ],
                if (_error != null)
                  Padding(
                      padding: const EdgeInsets.only(top: 12),
                      child: LocalizedText(_error!,
                          style: TextStyle(
                              color: Theme.of(context).colorScheme.error))),
              ],
            ))),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const LocalizedText('취소')),
          TextButton(
              onPressed: () => _save(withoutQuantity: true),
              child: const LocalizedText('수량 없이 저장')),
          FilledButton(onPressed: _save, child: const LocalizedText('저장')),
        ],
      );
}
