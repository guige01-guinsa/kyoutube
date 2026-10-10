import '../../../core/localization/localized_text.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/localization/app_localizations.dart';

import '../../auth/application/auth_providers.dart';
import '../../kitchen/domain/shopping_units.dart';
import '../application/shopping_purchase_controller.dart';
import '../data/shopping_assistant_repository.dart';
import '../domain/shopping_assistant.dart';

String shopText(BuildContext context, String ko, String en) =>
    AppLocalizations(Localizations.localeOf(context)).bilingual(ko, en);
String shopUnit(BuildContext context, String unit) =>
    Localizations.localeOf(context).languageCode != 'ko'
        ? (unit == 'ea' ? 'ea' : unit.replaceAll('_', ' '))
        : shoppingUnitLabel(unit);

/// Remove private dialogs when their account changes, including during a save.
class ShoppingAccountGuard extends ConsumerStatefulWidget {
  const ShoppingAccountGuard({super.key, required this.child});
  final Widget child;
  @override
  ConsumerState<ShoppingAccountGuard> createState() =>
      _ShoppingAccountGuardState();
}

class _ShoppingAccountGuardState extends ConsumerState<ShoppingAccountGuard> {
  String? _owner;
  bool _closing = false;
  @override
  void initState() {
    super.initState();
    _owner = ref.read(activeAccountIdProvider);
  }

  @override
  Widget build(BuildContext context) {
    if (_owner == null || ref.watch(activeAccountIdProvider) != _owner) {
      if (!_closing) {
        _closing = true;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          final route = ModalRoute.of(context);
          if (route != null && route.isActive) {
            Navigator.of(context).removeRoute(route);
          }
        });
      }
      return const SizedBox.shrink();
    }
    return widget.child;
  }
}

class ShoppingFavoriteDialog extends ConsumerStatefulWidget {
  const ShoppingFavoriteDialog(
      {super.key, required this.name, required this.unit, this.favorite});
  final String name, unit;
  final ShoppingFavorite? favorite;
  @override
  ConsumerState<ShoppingFavoriteDialog> createState() =>
      _ShoppingFavoriteDialogState();
}

class _ShoppingFavoriteDialogState
    extends ConsumerState<ShoppingFavoriteDialog> {
  final _form = GlobalKey<FormState>();
  late final _product =
      TextEditingController(text: widget.favorite?.productName ?? widget.name);
  late final _url = TextEditingController(text: widget.favorite?.url ?? '');
  late final _pack = TextEditingController(
      text: widget.favorite?.packQuantity == null
          ? ''
          : shoppingNumber(widget.favorite!.packQuantity));
  bool _saving = false;
  String? _error;
  String t(String ko, String en) => shopText(context, ko, en);
  @override
  void dispose() {
    _product.dispose();
    _url.dispose();
    _pack.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    final account = ref.read(activeAccountIdProvider);
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      if (account == null) throw StateError('Sign in required');
      await ref.read(shoppingAssistantRepositoryProvider).saveFavorite(
          ShoppingFavorite(
              id: widget.favorite?.id ?? '',
              ingredientName: widget.name,
              unit: widget.unit,
              productName: _product.text.trim(),
              url: _url.text.trim(),
              packQuantity: shoppingInput(_pack.text)));
      ref.invalidate(shoppingFavoritesProvider);
      if (mounted && ref.read(activeAccountIdProvider) == account) {
        Navigator.pop(context, true);
      }
    } catch (_) {
      if (mounted) {
        setState(() => _error = t('저장하지 못했습니다. 연결을 확인하고 다시 시도해 주세요.',
            'Could not save. Check your connection and try again.'));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
      canPop: !_saving,
      child: AlertDialog(
          scrollable: true,
          title: Text(t('자주 사는 상품', 'Favorite product')),
          content: SizedBox(
              width: 420,
              child: Form(
                  key: _form,
                  child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text(widget.name,
                            style: Theme.of(context).textTheme.titleMedium),
                        const SizedBox(height: 12),
                        TextFormField(
                            controller: _product,
                            enabled: !_saving,
                            maxLength: 250,
                            decoration: InputDecoration(
                                labelText: t('상품명', 'Product name')),
                            validator: (s) => s == null || s.trim().isEmpty
                                ? t('상품명을 입력해 주세요.', 'Enter a product name.')
                                : null),
                        TextFormField(
                            controller: _url,
                            enabled: !_saving,
                            maxLength: 2048,
                            keyboardType: TextInputType.url,
                            autocorrect: false,
                            decoration: InputDecoration(
                                labelText:
                                    t('상품 또는 구매처 링크', 'Product or store link'),
                                hintText: 'https://…'),
                            validator: (s) => shoppingProductUri(s ?? '') ==
                                    null
                                ? t('https://로 시작하는 공개 구매처 링크를 입력해 주세요.',
                                    'Enter a public store link starting with https://.')
                                : null),
                        if (widget.unit.isNotEmpty)
                          TextFormField(
                              controller: _pack,
                              enabled: !_saving,
                              keyboardType:
                                  const TextInputType.numberWithOptions(
                                      decimal: true),
                              decoration: InputDecoration(
                                  labelText: t('한 포장에 든 수량 (선택)',
                                      'Quantity per pack (optional)'),
                                  suffixText: shopUnit(context, widget.unit)),
                              validator: (s) => (s ?? '').trim().isEmpty ||
                                      (shoppingInput(s!) != null &&
                                          shoppingInput(s)! > 0 &&
                                          shoppingInput(s)! <= 1e9)
                                  ? null
                                  : t('0보다 큰 수량을 입력해 주세요.',
                                      'Enter a positive quantity.')),
                        const SizedBox(height: 10),
                        Text(
                            t('예: 두부 1팩에 300g이면 300을 입력하세요. 다음 장보기에서 포장 수를 계산합니다.',
                                'Example: for a 300 g pack, enter 300. This helps calculate packs next time.'),
                            style: Theme.of(context).textTheme.bodySmall),
                        if (_error != null)
                          Text(_error!,
                              style: TextStyle(
                                  color: Theme.of(context).colorScheme.error)),
                      ]))),
          actions: [
            TextButton(
                onPressed: _saving ? null : () => Navigator.pop(context),
                child: Text(t('취소', 'Cancel'))),
            FilledButton(
                onPressed: _saving ? null : _save,
                child: Text(
                    t(_saving ? '저장 중…' : '저장', _saving ? 'Saving…' : 'Save')))
          ]));
}

class ShoppingPurchaseDialog extends ConsumerStatefulWidget {
  const ShoppingPurchaseDialog(
      {super.key,
      required this.group,
      this.favorite,
      this.knownStock,
      this.confirmedStock,
      this.suggestedQuantity,
      this.purchaseLabel});
  final ShoppingPurchaseGroup group;
  final ShoppingFavorite? favorite;
  final double? knownStock;
  final double? confirmedStock;
  final double? suggestedQuantity;
  final String? purchaseLabel;
  @override
  ConsumerState<ShoppingPurchaseDialog> createState() =>
      _ShoppingPurchaseDialogState();
}

class _ShoppingPurchaseDialogState
    extends ConsumerState<ShoppingPurchaseDialog> {
  final _form = GlobalKey<FormState>();
  final _stock = TextEditingController(text: '0');
  final _amount = TextEditingController();
  late final _pack = TextEditingController(
      text: widget.favorite?.packQuantity == null
          ? ''
          : shoppingNumber(widget.favorite!.packQuantity));
  late final _quantity = TextEditingController(
      text: widget.group.neededQuantity == null
          ? ''
          : shoppingNumber(widget.group.neededQuantity));
  late String _unit =
      isPurchaseUnit(widget.group.unit) ? widget.group.unit : 'g';
  String _currency = 'KRW';
  bool _saving = false,
      _manualQuantity = false,
      _confirmed = false,
      _acceptShortfall = false,
      _stale = false;
  String? _error;
  Map<String, dynamic>? _submitted;
  String t(String ko, String en) => shopText(context, ko, en);
  bool get _shortfall {
    final actual = shoppingInput(_quantity.text);
    final required = widget.group.toBuy(shoppingInput(_stock.text) ?? 0);
    return actual != null && required != null && actual < required - 0.00001;
  }

  @override
  void initState() {
    super.initState();
    if (widget.confirmedStock != null) {
      _stock.text = shoppingNumber(widget.confirmedStock);
    }
    if (widget.suggestedQuantity != null) {
      _manualQuantity = true;
      _quantity.text = shoppingNumber(widget.suggestedQuantity);
    } else {
      _recalculate();
    }
  }

  @override
  void dispose() {
    _stock.dispose();
    _amount.dispose();
    _pack.dispose();
    _quantity.dispose();
    super.dispose();
  }

  void _recalculate() {
    if (_manualQuantity) return;
    final stock = shoppingInput(_stock.text) ?? 0;
    final need = widget.group.toBuy(stock);
    if (need == null) return;
    final pack = shoppingInput(_pack.text);
    final packs = widget.group.packs(stock, pack);
    _quantity.text = shoppingNumber(packs == null ? need : packs * pack!);
  }

  String? _valid(String? text,
      {bool optional = false, double max = 1e9, bool positive = false}) {
    if (optional && (text ?? '').trim().isEmpty) return null;
    final n = shoppingInput(text ?? '');
    return n == null || n < (positive ? 0.000001 : 0) || n > max
        ? t('수량 또는 금액을 확인해 주세요.', 'Check the quantity or amount.')
        : null;
  }

  Future<void> _save() async {
    if (_stale ||
        (!_form.currentState!.validate()) ||
        !_confirmed ||
        (_shortfall && !_acceptShortfall)) {
      return;
    }
    final account = ref.read(activeAccountIdProvider);
    final received =
        double.parse((shoppingInput(_quantity.text) ?? 0).toStringAsFixed(6));
    _submitted ??= {
      'name': widget.group.name,
      'unit': _unit,
      'quantity': received,
      'paid_amount': received == 0 ? null : shoppingInput(_amount.text),
      'currency': _currency,
      'product_name':
          widget.purchaseLabel ?? widget.favorite?.productName ?? '',
      'items':
          widget.group.allocations(received, shoppingInput(_stock.text) ?? 0)
    };
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final controller =
          await ref.read(shoppingPurchaseControllerProvider.future);
      if (account == null || ref.read(activeAccountIdProvider) != account) {
        throw StateError('Account changed');
      }
      await controller.record(_submitted!);
      if (mounted && ref.read(activeAccountIdProvider) == account) {
        Navigator.pop(context, true);
      }
    } catch (error) {
      if (mounted) {
        setState(() {
          _stale = error is PostgrestException &&
              const ['SHOPPING_STALE', 'SHOPPING_NOT_FOUND']
                  .contains(error.message);
          _error = _stale
              ? t('목록이 변경되었습니다. 닫고 목록을 새로고침해 주세요.',
                  'The list changed. Close this dialog and refresh.')
              : t('저장 결과를 확인하지 못했습니다. 같은 내용으로 다시 시도하면 중복 기록을 방지합니다.',
                  'Could not confirm the save. Retry these same details to avoid a duplicate record.');
        });
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final frozen = _saving || _submitted != null;
    final unit = shopUnit(context, _unit);
    final need = widget.group.toBuy(shoppingInput(_stock.text) ?? 0);
    final pack = shoppingInput(_pack.text);
    final count = widget.group.packs(shoppingInput(_stock.text) ?? 0, pack);
    final actual = shoppingInput(_quantity.text);
    final stock = shoppingInput(_stock.text);
    final preview = actual != null &&
            actual >= 0 &&
            actual <= 1e9 &&
            stock != null &&
            stock >= 0 &&
            stock <= 1e9
        ? widget.group.allocations(actual, stock)
        : null;
    return PopScope(
        canPop: !_saving,
        child: AlertDialog(
            scrollable: true,
            title: Text(t('구매 확인 · ${widget.group.name}',
                'Confirm · ${widget.group.name}')),
            content: SizedBox(
                width: 440,
                child: Form(
                    key: _form,
                    child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Text(t('실제로 구매한 수량을 확인하세요. 배송 상품은 수령 후 기록하는 것을 권합니다.',
                              'Confirm what you actually bought. For delivery orders, record after receiving.')),
                          const SizedBox(height: 12),
                          if (widget.group.neededQuantity != null) ...[
                            Text(t(
                                '목록 합계 ${shoppingNumber(widget.group.neededQuantity)} $unit',
                                'List total ${shoppingNumber(widget.group.neededQuantity)} $unit')),
                            if (widget.knownStock != null)
                              Text(t(
                                  '재고 기록: ${shoppingNumber(widget.knownStock)} $unit · 실제 보유량을 확인하세요.',
                                  'Inventory record: ${shoppingNumber(widget.knownStock)} $unit. Check what is available.')),
                            const SizedBox(height: 10),
                            TextFormField(
                                controller: _stock,
                                enabled: !frozen,
                                decoration: InputDecoration(
                                    labelText: t('이번 장보기에 사용할 보유량',
                                        'Stock available for this purchase'),
                                    suffixText: unit),
                                keyboardType:
                                    const TextInputType.numberWithOptions(
                                        decimal: true),
                                validator: _valid,
                                onChanged: (_) => setState(_recalculate)),
                            const SizedBox(height: 10),
                            TextFormField(
                                controller: _pack,
                                enabled: !frozen,
                                decoration: InputDecoration(
                                    labelText: t('한 포장에 든 수량 (선택)',
                                        'Quantity per pack (optional)'),
                                    suffixText: unit),
                                keyboardType:
                                    const TextInputType.numberWithOptions(
                                        decimal: true),
                                validator: (s) =>
                                    _valid(s, optional: true, positive: true),
                                onChanged: (_) => setState(_recalculate)),
                            const SizedBox(height: 8),
                            Text(count == null
                                ? t('추가 필요 ${shoppingNumber(need)} $unit',
                                    'Still needed ${shoppingNumber(need)} $unit')
                                : t('추가 필요 ${shoppingNumber(need)} $unit · $count포장',
                                    'Still needed ${shoppingNumber(need)} $unit · $count packs')),
                          ] else ...[
                            Text(t('수량 또는 단위가 미확인 상태입니다. 상품을 확인한 뒤 직접 입력해 주세요.',
                                'Quantity or unit needs review. Check the product and enter the actual amount.')),
                            DropdownButtonFormField<String>(
                                initialValue: _unit,
                                isExpanded: true,
                                decoration: InputDecoration(
                                    labelText: t('구매 단위', 'Purchase unit')),
                                items: purchaseUnits
                                    .map((u) => DropdownMenuItem(
                                        value: u.code,
                                        child: Text(shopUnit(context, u.code))))
                                    .toList(),
                                onChanged: frozen
                                    ? null
                                    : (u) => setState(() {
                                          if (u == null || u == _unit) return;
                                          final quantity =
                                              shoppingInput(_quantity.text);
                                          final converted = quantity == null
                                              ? null
                                              : convertPurchaseQuantity(
                                                  quantity, _unit, u);
                                          _quantity.text =
                                              converted?.toString() ?? '';
                                          _unit = u;
                                          _manualQuantity = true;
                                        })),
                          ],
                          const SizedBox(height: 14),
                          TextFormField(
                              controller: _quantity,
                              enabled: !frozen,
                              decoration: InputDecoration(
                                  labelText: t(
                                      '실제 구매 수량', 'Actual purchased quantity'),
                                  suffixText: unit),
                              keyboardType:
                                  const TextInputType.numberWithOptions(
                                      decimal: true),
                              validator: (s) {
                                final error = _valid(s);
                                if (error != null) return error;
                                final n = shoppingInput(s!)!;
                                return (n * 1000000 - (n * 1000000).round())
                                            .abs() >
                                        0.00001
                                    ? t('구매 수량은 소수점 여섯째 자리까지 입력해 주세요.',
                                        'Use up to six decimal places for the purchased quantity.')
                                    : null;
                              },
                              onChanged: (_) =>
                                  setState(() => _manualQuantity = true)),
                          const SizedBox(height: 10),
                          TextFormField(
                              controller: _amount,
                              enabled:
                                  !frozen && shoppingInput(_quantity.text) != 0,
                              decoration: InputDecoration(
                                  labelText: t('이 재료의 실제 결제 금액 (선택)',
                                      'Amount paid for this ingredient (optional)')),
                              keyboardType:
                                  const TextInputType.numberWithOptions(
                                      decimal: true),
                              validator: (s) =>
                                  shoppingInput(_quantity.text) == 0
                                      ? null
                                      : _valid(s, optional: true, max: 1e12)),
                          DropdownButtonFormField<String>(
                              initialValue: _currency,
                              decoration: InputDecoration(
                                  labelText: t('결제 통화', 'Payment currency')),
                              items: ['KRW', 'USD']
                                  .map((c) => DropdownMenuItem(
                                      value: c, child: Text(c)))
                                  .toList(),
                              onChanged: frozen
                                  ? null
                                  : (c) => setState(() => _currency = c!)),
                          const SizedBox(height: 10),
                          Text(
                              t('금액에는 다른 상품 가격을 포함하지 마세요. 배송비를 포함하려면 이 재료에 배분한 금액만 입력하세요.',
                                  'Exclude other products. Include only this ingredient’s share of delivery charges.'),
                              style: Theme.of(context).textTheme.bodySmall),
                          const SizedBox(height: 12),
                          for (var i = 0; i < widget.group.sources.length; i++)
                            LocalizedText('• ${widget.group.sources[i].listTitle}'
                                '${preview == null ? '' : ' · ${shoppingNumber(preview[i]['quantity'] as double)} $unit'}'),
                          if (_shortfall)
                            CheckboxListTile(
                                contentPadding: EdgeInsets.zero,
                                value: _acceptShortfall,
                                onChanged: frozen
                                    ? null
                                    : (v) => setState(
                                        () => _acceptShortfall = v == true),
                                title: Text(t('부족한 수량은 이번 목록에서 제외합니다.',
                                    'Exclude the shortfall from these lists.')),
                                subtitle: Text(t(
                                    '구매량이 필요량보다 적습니다. 계속하면 부족분이 별도 구매 항목으로 남지 않습니다.',
                                    'You bought less than needed. If you continue, the shortfall will not remain as another item to buy.'))),
                          CheckboxListTile(
                              contentPadding: EdgeInsets.zero,
                              value: _confirmed,
                              onChanged: frozen
                                  ? null
                                  : (v) =>
                                      setState(() => _confirmed = v == true),
                              title: Text(t('수량과 단위를 확인했습니다.',
                                  'I checked the quantity and unit.')),
                              subtitle: Text(t(
                                  '구매량은 위 목록에 나누어 기록됩니다. 0이면 건너뜀으로 처리됩니다. 재고는 각 목록에서 ‘장보기 완료’를 누를 때 반영됩니다.',
                                  'The quantity is split across these lists. Zero marks items skipped. Inventory updates when you complete each shopping list.'))),
                          if (_error != null)
                            Text(_error!,
                                style: TextStyle(
                                    color:
                                        Theme.of(context).colorScheme.error)),
                        ]))),
            actions: [
              TextButton(
                  onPressed:
                      _saving ? null : () => Navigator.pop(context, false),
                  child: Text(t('닫기', 'Close'))),
              FilledButton(
                  onPressed: _saving ||
                          !_confirmed ||
                          _stale ||
                          (_shortfall && !_acceptShortfall)
                      ? null
                      : _save,
                  child: Text(_saving
                      ? t('저장 중…', 'Saving…')
                      : _submitted != null
                          ? t('같은 내용으로 재시도', 'Retry same details')
                          : t('확인 후 기록', 'Confirm and record')))
            ]));
  }
}
