import '../../../core/localization/localized_text.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../auth/application/auth_providers.dart';
import '../data/shopping_affiliate_repository.dart';
import '../data/shopping_assistant_repository.dart';
import '../domain/shopping_affiliate.dart';
import '../domain/shopping_assistant.dart';
import '../domain/coupang_purchase_plan.dart';
import 'shopping_assistant_dialogs.dart';
import 'coupang_general_search.dart';

/// Planning never writes an order, changes stock or bypasses business approval.
class CoupangPurchasePlanner extends ConsumerStatefulWidget {
  const CoupangPurchasePlanner(
      {super.key,
      required this.ingredient,
      required this.unit,
      required this.needed,
      required this.value,
      required this.onChanged,
      this.enabled = true,
      this.allowOpen = true,
      this.emphasizeCheckout = false});
  final String ingredient, unit;
  final double? needed;
  final CoupangPurchasePlan? value;
  final ValueChanged<CoupangPurchasePlan?> onChanged;
  final bool enabled, allowOpen;

  /// Personal shopping surfaces make the store handoff the primary action.
  final bool emphasizeCheckout;
  @override
  ConsumerState<CoupangPurchasePlanner> createState() => _PlannerState();
}

class _PlannerState extends ConsumerState<CoupangPurchasePlanner> {
  bool _busy = false;
  String? _error;
  String? _previewId;
  String t(String ko, String en) => shopText(context, ko, en);
  Future<void> _open(ShoppingAffiliate offer) async {
    final account = ref.read(activeAccountIdProvider);
    if (account == null || !widget.allowOpen || _busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final fresh = await ref
          .read(shoppingAffiliateRepositoryProvider)
          .find(widget.ingredient);
      if (!mounted ||
          ref.read(activeAccountIdProvider) != account ||
          !widget.allowOpen) {
        return;
      }
      if (!fresh.any((o) =>
          o.id == offer.id &&
          CoupangPurchasePlan.offerFingerprint(o) ==
              CoupangPurchasePlan.offerFingerprint(offer))) {
        ref.invalidate(shoppingAffiliatesProvider(widget.ingredient));
        throw StateError('changed');
      }
      if (!await ref.read(shoppingLinkLauncherProvider)(offer.uri!)) {
        throw StateError('open');
      }
    } catch (_) {
      if (mounted) {
        setState(() => _error = t('최신 상품을 확인하지 못했습니다. 상품을 다시 불러온 뒤 확인해 주세요.',
            'Could not verify the current product. Reload and check it again.'));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _choose(List<ShoppingAffiliate> offers) async {
    final selected = await showDialog<ShoppingAffiliate>(
        context: context,
        builder: (ctx) => ShoppingAccountGuard(
                child: SimpleDialog(
                    title: Text(t('쿠팡 상품 선택', 'Choose a Coupang product')),
                    children: [
                  for (final o in offers)
                    SimpleDialogOption(
                        onPressed: () => Navigator.pop(ctx, o),
                        child: LocalizedText(
                            '${o.title}\n${o.specification.isEmpty ? t('판매 규격 확인 필요', 'Check package details') : o.specification}')),
                ])));
    if (!mounted || selected == null || !widget.enabled) return;
    _select(selected);
  }

  void _select(ShoppingAffiliate offer) {
    setState(() => _previewId = offer.id);
    final count = CoupangPack.parse(offer.data['purchase_pack'])
        ?.suggest(widget.needed, widget.unit);
    if (count == null) {
      widget.onChanged(null);
      return;
    }
    widget.onChanged(CoupangPurchasePlan(
        offer: offer, count: count, needed: widget.needed!, unit: widget.unit));
  }

  @override
  Widget build(BuildContext context) {
    if (widget.ingredient.trim().isEmpty) return const SizedBox.shrink();
    final result = ref.watch(shoppingAffiliatesProvider(widget.ingredient));
    return result.when(
        skipLoadingOnRefresh: false,
        loading: () => const Padding(
            padding: EdgeInsets.all(8), child: LinearProgressIndicator()),
        error: (_, __) => TextButton(
            onPressed: () =>
                ref.invalidate(shoppingAffiliatesProvider(widget.ingredient)),
            child: Text(t('쿠팡 상품 다시 불러오기', 'Reload Coupang products'))),
        data: (rows) {
          final offers = rows
              .where((o) => o.program == 'coupang' && o.uri != null)
              .toList();
          final value = widget.value;
          final fresh = value == null || offers.any(value.matches);
          final selectedOffer =
              offers.where((o) => o.id == _previewId).firstOrNull;
          // A single catalog offer keeps the short shopping flow. Several
          // offers always require an explicit purchaser choice.
          final offer = value?.offer ??
              selectedOffer ??
              (offers.length == 1 ? offers.single : null);
          if (offer == null) {
            if (offers.isEmpty) {
              return widget.allowOpen
                  ? CoupangGeneralSearch(
                      ingredient: widget.ingredient, enabled: widget.enabled)
                  : Text(t(
                      '제휴 상품이 없습니다. 품명·수량·단위를 직접 입력하고, 요청서 승인 후 쿠팡에서 다른 상품을 찾을 수 있습니다.',
                      'No affiliate product. Enter the name, quantity and unit. After approval, you can search other Coupang products.'));
            }
            return _offerSelectionPrompt(offers, multiple: true);
          }
          final pack = CoupangPack.parse(offer.data['purchase_pack']);
          final suggested = pack?.suggest(widget.needed, widget.unit);
          final enabled = widget.enabled && !_busy;
          return Container(
              margin: const EdgeInsets.only(top: 8),
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                  border: Border.all(
                      color: Theme.of(context).colorScheme.outlineVariant),
                  borderRadius: BorderRadius.circular(12)),
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(children: [
                      if (offer.imageUrl != null) ...[
                        _PlannerProductImage(imageUrl: offer.imageUrl),
                        const SizedBox(width: 8),
                      ],
                      Expanded(
                          child: Text(offer.title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: Theme.of(context).textTheme.titleSmall)),
                      if (offer.isSuggestedMatch)
                        Tooltip(
                            message: t(
                                '유사 상품입니다. 재료의 종류·부위와 판매 규격을 확인한 뒤 구매해 주세요.',
                                'This is a similar product. Check the ingredient type, cut, and package size before buying.'),
                            child: const Padding(
                                padding: EdgeInsets.only(left: 4),
                                child: Icon(Icons.info_outline, size: 18))),
                    ]),
                    if (offer.specification.isNotEmpty)
                      Text(offer.specification,
                          maxLines: 1, overflow: TextOverflow.ellipsis),
                    if (pack != null)
                      LocalizedText(
                          '${pack.option} · ${shoppingNumber(pack.amount)} ${shopUnit(context, pack.unit)} × ${pack.unitsPerOrder} / ${pack.label}'),
                    if (!fresh)
                      Text(t('상품이 변경되었거나 공개가 중단되었습니다. 다시 선택해 주세요.',
                          'This product changed or is unavailable. Select it again.')),
                    if (value == null && suggested != null)
                      Text(t('권장 구매 수량: $suggested ${pack!.label}',
                          'Suggested quantity: $suggested ${pack.label}')),
                    if (value == null && suggested == null)
                      Text(t('판매 규격 또는 필요량·단위 확인 후 자동 계산할 수 있습니다.',
                          'Automatic calculation requires verified packaging and a compatible required quantity.')),
                    if (value != null) ...[
                      Wrap(
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: [
                            IconButton(
                                tooltip: t('구매 수량 줄이기', 'Decrease quantity'),
                                onPressed: enabled && fresh && value.count > 1
                                    ? () => widget.onChanged(
                                        value.withCount(value.count - 1))
                                    : null,
                                icon: const Icon(Icons.remove_circle_outline)),
                            LocalizedText('${value.count} ${value.pack.label}'),
                            IconButton(
                                tooltip: t('구매 수량 늘리기', 'Increase quantity'),
                                onPressed: enabled &&
                                        fresh &&
                                        value.count < 1000000 &&
                                        value.total +
                                                value.pack
                                                    .quantityIn(value.unit)! <=
                                            1e9
                                    ? () => widget.onChanged(
                                        value.withCount(value.count + 1))
                                    : null,
                                icon: const Icon(Icons.add_circle_outline)),
                          ]),
                      Text(t(
                          '구매 총량: ${shoppingNumber(value.total)} ${shopUnit(context, value.unit)}',
                          'Purchase total: ${shoppingNumber(value.total)} ${shopUnit(context, value.unit)}')),
                      LocalizedText(
                          '${value.difference < 0 ? t('부족량', 'Shortfall') : t('여유량', 'Surplus')}: ${shoppingNumber(value.difference.abs())} ${shopUnit(context, value.unit)}'),
                    ],
                    Wrap(spacing: 6, runSpacing: 4, children: [
                      if (value == null)
                        OutlinedButton(
                            onPressed: enabled && suggested != null
                                ? () => _select(offer)
                                : null,
                            child: Text(t(
                                '이 상품으로 구매량 적용', 'Use this product quantity'))),
                      TextButton(
                          onPressed: enabled && offers.isNotEmpty
                              ? () => _choose(offers)
                              : null,
                          child: Text(t('상품 변경', 'Change product'))),
                      if (value != null)
                        TextButton(
                            onPressed:
                                enabled ? () => widget.onChanged(null) : null,
                            child: Text(t(
                                '기존 구매량으로 돌아가기', 'Use the original quantity'))),
                      if (widget.allowOpen)
                        widget.emphasizeCheckout
                            ? FilledButton.icon(
                                style: _compactButtonStyle,
                                onPressed: enabled && fresh
                                    ? () => _open(offer)
                                    : null,
                                icon: const Icon(Icons.open_in_new),
                                label: Text(t('구매', 'Buy')))
                            : OutlinedButton.icon(
                                style: _compactButtonStyle,
                                onPressed: enabled && fresh
                                    ? () => _open(offer)
                                    : null,
                                icon: const Icon(Icons.open_in_new),
                                label: Text(t('구매', 'Buy'))),
                    ]),
                    if (widget.allowOpen)
                      Align(
                          alignment: Alignment.centerRight,
                          child: Tooltip(
                              message: t(
                                  '쿠팡에서 최종 옵션·수량·가격을 확인하세요. 수령 후 실제 구매량을 기록합니다.',
                                  'Confirm the final option, quantity and price at Coupang. Record the actual quantity after delivery.'),
                              child: const Icon(Icons.help_outline, size: 16)))
                    else
                      Text(t('상품·수량을 저장하고 요청서를 승인한 뒤 구매할 수 있습니다.',
                          'Save the product and quantity, then approve the request before purchasing.')),
                    if (_error != null) Text(_error!),
                  ]));
        });
  }

  static final ButtonStyle _compactButtonStyle = FilledButton.styleFrom(
      minimumSize: const Size(0, 36),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      visualDensity: VisualDensity.compact);

  Widget _offerSelectionPrompt(List<ShoppingAffiliate> offers,
      {bool multiple = false}) {
    final enabled = widget.enabled && !_busy;
    return Container(
      margin: const EdgeInsets.only(top: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text(multiple
            ? t('${offers.length}개의 쿠팡 제휴 상품이 있습니다. 판매 규격을 비교해 선택해 주세요.',
                '${offers.length} Coupang products are available. Compare package details and choose one.')
            : t('쿠팡 제휴 상품이 있습니다. 판매 규격을 확인해 선택해 주세요.',
                'A Coupang product is available. Check the package details and choose it.')),
        const SizedBox(height: 8),
        OutlinedButton.icon(
          onPressed: enabled ? () => _choose(offers) : null,
          icon: const Icon(Icons.list_alt),
          label: Text(multiple
              ? t('상품 ${offers.length}개 중 선택',
                  'Choose from ${offers.length} products')
              : t('상품 확인·선택', 'Review and choose product')),
        ),
      ]),
    );
  }
}

class _PlannerProductImage extends StatelessWidget {
  const _PlannerProductImage({this.imageUrl});
  final String? imageUrl;

  @override
  Widget build(BuildContext context) => Semantics(
      label: '쿠팡 상품 사진',
      image: true,
      child: ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: SizedBox(
              width: 52,
              height: 52,
              child: imageUrl == null
                  ? const ColoredBox(
                      color: Color(0xfff5f2f4),
                      child: Icon(Icons.shopping_bag_outlined))
                  : Image.network(imageUrl!,
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => const ColoredBox(
                          color: Color(0xfff5f2f4),
                          child: Icon(Icons.shopping_bag_outlined))))));
}
