import '../../../core/localization/localized_text.dart';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'purchase_name_field.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../auth/application/auth_providers.dart';
import '../../kitchen/domain/shopping_units.dart';
import '../data/manual_shopping_repository.dart';
import '../data/shopping_assistant_repository.dart';
import '../domain/manual_shopping.dart';
import '../domain/shopping_assistant.dart';
import 'shopping_affiliate_panel.dart';
import 'coupang_disclosure.dart';
import 'shopping_assistant_dialogs.dart';
import '../application/shopping_market_provider.dart';
import 'shopping_market_widgets.dart';

/// These are planned quantities. Saving never marks a purchase or adds stock.
class ManualShoppingDialog extends ConsumerStatefulWidget {
  const ManualShoppingDialog({super.key, required this.owner});
  final String owner;
  @override
  ConsumerState<ManualShoppingDialog> createState() =>
      _ManualShoppingDialogState();
}

class _ManualShoppingDialogState extends ConsumerState<ManualShoppingDialog> {
  final _name = TextEditingController(),
      _quantity = TextEditingController(),
      _specification = TextEditingController();
  final _items = <ManualShoppingItem>[];
  List<ManualShoppingItem>? _pendingItems;
  String _unit = 'g';
  bool _loading = true, _loadFailed = false, _busy = false;
  String? _error;
  bool get _current =>
      mounted && ref.read(activeAccountIdProvider) == widget.owner;
  bool get _locked => _busy || _pendingItems != null;
  String t(String ko, String en) => shopText(context, ko, en);
  ManualShoppingItem? get _input {
    final quantity = shoppingInput(_quantity.text);
    if (quantity == null) return null;
    final item = ManualShoppingItem(
        name: _name.text,
        quantity: quantity,
        unit: _unit,
        specification: _specification.text);
    return item.valid ? item : null;
  }

  Map<String, dynamic> get _draft => {
        'items': _items.map((e) => e.toJson()).toList(),
        'name': _name.text,
        'quantity': _quantity.text,
        'unit': _unit,
        'specification': _specification.text,
        if (_pendingItems != null)
          'pending': _pendingItems!.map((e) => e.toJson()).toList(),
      };
  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _name.dispose();
    _quantity.dispose();
    _specification.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _loadFailed = false;
      _error = null;
    });
    try {
      final data =
          await ref.read(manualShoppingDraftStoreProvider).read(widget.owner);
      if (!_current) return;
      if (data != null) {
        final items = (data['items'] as List)
            .map((e) => ManualShoppingItem.fromJson(
                Map<String, dynamic>.from(e as Map)))
            .toList();
        final pending = (data['pending'] as List?)
            ?.map((e) => ManualShoppingItem.fromJson(
                Map<String, dynamic>.from(e as Map)))
            .toList();
        final unit = data['unit'] as String;
        if (!isPurchaseUnit(unit) ||
            items.length > 100 ||
            items.any((e) => !e.valid) ||
            (pending != null &&
                (pending.isEmpty ||
                    pending.length > 100 ||
                    pending.any((e) => !e.valid)))) {
          throw const FormatException('Invalid manual draft');
        }
        _items.clear();
        _items.addAll(items);
        _pendingItems = pending;
        _name.text = data['name'] as String;
        _quantity.text = data['quantity'] as String;
        _specification.text = data['specification'] as String;
        _unit = unit;
      }
    } catch (_) {
      if (_current) {
        _loadFailed = true;
        _error = t('추가 중인 재료를 불러오지 못했습니다. 다시 시도해 주세요.',
            'Could not load your ingredient draft. Retry.');
      }
    } finally {
      if (_current) setState(() => _loading = false);
    }
  }

  Future<bool> _persist() async {
    if (!_current || _loadFailed) return false;
    try {
      await ref
          .read(manualShoppingDraftStoreProvider)
          .write(widget.owner, _draft);
      return _current;
    } catch (_) {
      if (_current) {
        setState(() => _error = t('임시 저장하지 못했습니다. 연결을 확인하고 다시 시도해 주세요.',
            'Could not save your draft. Check and retry.'));
      }
      return false;
    }
  }

  void _changed() {
    setState(() => _error = null);
    _persist();
  }

  Future<void> _queue() async {
    final item = _input;
    if (item == null || _items.length >= 100 || _locked) return;
    setState(() {
      _items.add(item);
      _name.clear();
      _quantity.clear();
      _specification.clear();
      _error = null;
    });
    await _persist();
  }

  Future<void> _findProducts() async {
    final name = _name.text.trim(), specification = _specification.text.trim();
    if (name.isEmpty ||
        name.length > 200 ||
        specification.length > 120 ||
        !await _persist() ||
        !_current ||
        !mounted) {
      return;
    }
    await showDialog<void>(
        context: context,
        builder: (_) => ShoppingAccountGuard(
            child: ManualShoppingProductsDialog(
                ingredient: name, specification: specification)));
  }

  Future<void> _submit() async {
    if (_busy || !_current) return;
    if (_pendingItems == null) {
      final input = _input;
      if ((_name.text.trim().isNotEmpty ||
              _quantity.text.trim().isNotEmpty ||
              _specification.text.trim().isNotEmpty) &&
          input == null) {
        setState(() => _error = t('재료명과 0보다 큰 수량·단위를 확인해 주세요.',
            'Enter an ingredient and a positive quantity with its unit.'));
        return;
      }
      final items = [..._items, if (input != null) input];
      if (items.isEmpty || items.length > 100) return;
      if (utf8
              .encode(jsonEncode(items.map((e) => e.toJson()).toList()))
              .length >
          60000) {
        setState(() => _error =
            t('한 번에 추가할 재료 수를 줄여 주세요.', 'Add fewer ingredients at a time.'));
        return;
      }
      _pendingItems = items;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      if (!await _persist() || !_current) return;
      final controller =
          await ref.read(manualShoppingControllerProvider.future);
      if (!_current) return;
      final id = await controller.create(widget.owner, _pendingItems!);
      if (!_current) return;
      await ref
          .read(manualShoppingDraftStoreProvider)
          .write(widget.owner, null);
      // Clearing the draft precedes key acknowledgement. Any ambiguity retains
      // the request key, so retry cannot create a second list.
      try {
        await controller.acknowledge(widget.owner, _pendingItems!);
      } catch (_) {/* replay remains safe */}
      if (mounted && _current) Navigator.pop(context, id);
    } catch (_) {
      if (_current) {
        setState(() => _error = t(
            '저장 결과를 확인하지 못했습니다. 같은 내용으로 다시 확인하면 중복으로 추가되지 않습니다.',
            'Could not confirm saving. Retry the same submission safely without duplicates.'));
      }
    } finally {
      if (_current) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final input = _input;
    return PopScope(
        canPop: !_busy,
        child: AlertDialog(
          title: Text(t('재료 직접 추가', 'Add ingredients')),
          content: SizedBox(
              width: 560,
              child: _loading
                  ? const Center(child: CircularProgressIndicator())
                  : SingleChildScrollView(
                      child: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                          if (_loadFailed)
                            TextButton(
                                onPressed: _load,
                                child: Text(t('다시 불러오기', 'Reload')))
                          else ...[
                            Text(t(
                                '레시피에 없는 재료도 추가할 수 있습니다. 필요한 수량을 입력한 뒤 구매 리스트에서 함께 확인하세요.',
                                'Add ingredients beyond your recipes. Enter required quantities and review them together in your purchase list.')),
                            const SizedBox(height: 12),
                            PurchaseNameField(
                                key: const ValueKey('manual-name'),
                                controller: _name,
                                enabled: !_locked,
                                maxLength: 200,
                                decoration: InputDecoration(
                                    labelText: t('재료명', 'Ingredient')),
                                onChanged: (_) => _changed()),
                            Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Expanded(
                                      child: TextField(
                                          key:
                                              const ValueKey('manual-quantity'),
                                          controller: _quantity,
                                          enabled: !_locked,
                                          keyboardType: const TextInputType
                                              .numberWithOptions(decimal: true),
                                          decoration: InputDecoration(
                                              labelText: t('필요 수량',
                                                  'Required quantity')),
                                          onChanged: (_) => _changed())),
                                  const SizedBox(width: 12),
                                  Expanded(
                                      child: DropdownButtonFormField<String>(
                                          key: ValueKey('manual-unit-$_unit'),
                                          initialValue: _unit,
                                          isExpanded: true,
                                          decoration: InputDecoration(
                                              labelText: t('단위', 'Unit')),
                                          items: [
                                            for (final u in purchaseUnits)
                                              DropdownMenuItem(
                                                  value: u.code,
                                                  child: Text(shopUnit(
                                                      context, u.code)))
                                          ],
                                          onChanged: _locked
                                              ? null
                                              : (v) {
                                                  if (v != null) {
                                                    _unit = v;
                                                    _changed();
                                                  }
                                                })),
                                ]),
                            const SizedBox(height: 12),
                            TextField(
                                key: const ValueKey('manual-specification'),
                                controller: _specification,
                                enabled: !_locked,
                                maxLength: 120,
                                decoration: InputDecoration(
                                    labelText: t('규격·브랜드 (선택)',
                                        'Size or brand (optional)')),
                                onChanged: (_) => _changed()),
                            Text(t(
                                '봉지·병·팩을 g 또는 ml로 자동 환산하지 않습니다. 실제 포장 규격을 확인해 주세요.',
                                'Bags, bottles and packs are not automatically converted to g or ml. Check the actual package size.')),
                            OutlinedButton.icon(
                                onPressed: _busy || _name.text.trim().isEmpty
                                    ? null
                                    : _findProducts,
                                icon: const Icon(Icons.search),
                                label: Text(
                                    ref.watch(shoppingMarketProvider).isKorea
                                        ? t('쿠팡 상품 찾기', 'Find Coupang products')
                                        : context.tr('구매처 찾기'))),
                            OutlinedButton.icon(
                                onPressed: _locked ||
                                        input == null ||
                                        _items.length >= 100
                                    ? null
                                    : _queue,
                                icon: const Icon(Icons.add),
                                label: Text(t(
                                    '담고 다음 재료 입력', 'Add another ingredient'))),
                            for (var i = 0; i < _items.length; i++)
                              ListTile(
                                  contentPadding: EdgeInsets.zero,
                                  title: Text(_items[i].name),
                                  subtitle: LocalizedText(
                                      '${shoppingNumber(_items[i].quantity)} ${shopUnit(context, _items[i].unit)} ${_items[i].specification}'),
                                  trailing: IconButton(
                                      tooltip:
                                          t('추가 목록에서 빼기', 'Remove from draft'),
                                      icon: const Icon(Icons.close),
                                      onPressed: _locked
                                          ? null
                                          : () {
                                              setState(
                                                  () => _items.removeAt(i));
                                              _persist();
                                            })),
                            if (_pendingItems != null && !_busy)
                              Text(t('저장 결과를 확인하는 동안에는 재료를 수정할 수 없습니다.',
                                  'Ingredients stay locked while confirming this submission.')),
                          ],
                          if (_error != null)
                            Text(_error!,
                                style: TextStyle(
                                    color:
                                        Theme.of(context).colorScheme.error)),
                        ]))),
          actions: [
            TextButton(
                onPressed: _busy
                    ? null
                    : () async {
                        if (_loadFailed || await _persist()) {
                          if (context.mounted && _current) {
                            Navigator.pop(context);
                          }
                        }
                      },
                child: Text(t('닫기', 'Close'))),
            FilledButton(
                onPressed: _loading ||
                        _loadFailed ||
                        _busy ||
                        (_pendingItems == null &&
                            _items.isEmpty &&
                            input == null)
                    ? null
                    : _submit,
                child: Text(_busy
                    ? t('저장 중', 'Saving')
                    : _pendingItems != null
                        ? t('저장 결과 다시 확인', 'Retry saving')
                        : t('장보기 목록에 추가', 'Add to shopping list'))),
          ],
        ));
  }
}

class ManualShoppingProductsDialog extends ConsumerWidget {
  const ManualShoppingProductsDialog(
      {super.key, required this.ingredient, required this.specification});
  final String ingredient, specification;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    String t(String ko, String en) => shopText(context, ko, en);
    final owner = ref.watch(activeAccountIdProvider);
    final market = ref.watch(shoppingMarketProvider);
    return AlertDialog(
        title: LocalizedText(market.isKorea ? '쿠팡 상품 찾기' : '구매처 찾기'),
        content: SizedBox(
            width: 560,
            child: SingleChildScrollView(
                child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                  const ShoppingMarketSelector(),
                  if (!market.isKorea)
                    OverseasIngredientSearch(
                        ingredient: ingredient, specification: specification)
                  else ...[
                    LocalizedText('$ingredient $specification'),
                    ShoppingAffiliatePanel(
                        ingredient: ingredient,
                        coupangOnly: true,
                        showCoupangDisclosure: false),
                    const SizedBox(height: 12),
                    Text(t(
                        '다른 상품의 규격을 확인하려면 쿠팡 일반 검색을 이용하세요. 일반 검색은 수익용 제휴 링크가 아니며 상품이 자동 등록되지 않습니다.',
                        'Use Coupang search to check other product sizes. General search is not an affiliate link and does not import products automatically.')),
                    OutlinedButton.icon(
                        onPressed: () async {
                          if (owner == null ||
                              ref.read(activeAccountIdProvider) != owner) {
                            return;
                          }
                          final uri = shoppingSearchUri(
                              ShoppingSearchStore.coupang, ingredient,
                              specification: specification);
                          try {
                            if (await ref
                                .read(shoppingLinkLauncherProvider)(uri)) {
                              return;
                            }
                          } catch (_) {/* recoverable */}
                          if (context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                                content: Text(t('상품 페이지를 열지 못했습니다.',
                                    'Could not open the product page.'))));
                          }
                        },
                        icon: const Icon(Icons.open_in_new),
                        label: Text(
                            t('쿠팡 일반 검색으로 규격 확인', 'Check sizes on Coupang'))),
                    Text(t('확인 후 돌아와 필요한 재료명·수량·단위를 입력해 주세요.',
                        'Return here after checking, then enter the ingredient, quantity and unit.')),
                  ],
                ]))),
        actions: [
          CoupangDisclosureFooter(
              ingredients: [ingredient], respectShoppingMarket: true),
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text(t('닫기', 'Close')))
        ]);
  }
}
