import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/localization/localized_text.dart';
import '../../auth/application/auth_providers.dart';
import '../application/shopping_market_provider.dart';
import '../data/shopping_assistant_repository.dart';
import '../domain/shopping_assistant.dart';
import '../domain/shopping_market.dart';
import 'shopping_assistant_dialogs.dart';

class ShoppingMarketSelector extends ConsumerWidget {
  const ShoppingMarketSelector({super.key, this.enabled = true});
  final bool enabled;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final market = ref.watch(shoppingMarketProvider);
    return Align(
      alignment: Alignment.centerLeft,
      child: TextButton.icon(
        icon: const Icon(Icons.public),
        label: Text(
            '${context.tr('구매 국가·검색 언어')}: ${context.tr(shoppingCountries[market.country]!)}'),
        onPressed: !enabled
            ? null
            : () => showDialog<void>(
                  context: context,
                  builder: (_) =>
                      const ShoppingAccountGuard(child: _MarketDialog()),
                ),
      ),
    );
  }
}

class _MarketDialog extends ConsumerStatefulWidget {
  const _MarketDialog();
  @override
  ConsumerState<_MarketDialog> createState() => _MarketDialogState();
}

class _MarketDialogState extends ConsumerState<_MarketDialog> {
  late String _country = ref.read(shoppingMarketProvider).country;
  late String _language = ref.read(shoppingMarketProvider).language;
  bool _busy = false;
  String? _error;
  @override
  Widget build(BuildContext context) => AlertDialog(
        scrollable: true,
        title: const LocalizedText('구매 국가·검색 언어'),
        content: SizedBox(
            width: 420,
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              const LocalizedText('구매할 국가를 직접 선택하세요. 앱 언어와 별개이며 이 기기에 저장됩니다.'),
              const SizedBox(height: 16),
              DropdownButtonFormField<String>(
                key: const ValueKey('shopping-country'),
                initialValue: _country,
                isExpanded: true,
                decoration: InputDecoration(labelText: context.tr('구매 국가')),
                items: [
                  for (final entry in shoppingCountries.entries)
                    DropdownMenuItem(
                        value: entry.key, child: LocalizedText(entry.value))
                ],
                onChanged:
                    _busy ? null : (value) => setState(() => _country = value!),
              ),
              const SizedBox(height: 16),
              DropdownButtonFormField<String>(
                key: const ValueKey('shopping-search-language'),
                initialValue: _language,
                isExpanded: true,
                decoration: InputDecoration(labelText: context.tr('검색 언어')),
                items: const [
                  DropdownMenuItem(value: 'ko', child: Text('한국어')),
                  DropdownMenuItem(value: 'en', child: Text('English')),
                  DropdownMenuItem(value: 'es', child: Text('Español')),
                ],
                onChanged: _busy
                    ? null
                    : (value) => setState(() => _language = value!),
              ),
              if (_error != null) Text(_error!),
            ])),
        actions: [
          TextButton(
              onPressed: _busy ? null : () => Navigator.pop(context),
              child: const LocalizedText('취소')),
          FilledButton(
              onPressed: _busy
                  ? null
                  : () async {
                      final owner = ref.read(activeAccountIdProvider);
                      setState(() => _busy = true);
                      final saved = await ref
                          .read(shoppingMarketProvider.notifier)
                          .save(ShoppingMarket(
                              country: _country, language: _language));
                      if (!mounted ||
                          !context.mounted ||
                          ref.read(activeAccountIdProvider) != owner) {
                        return;
                      }
                      if (saved) {
                        Navigator.pop(context);
                        return;
                      }
                      setState(() {
                        _busy = false;
                        _error = context.tr('설정을 저장하지 못했습니다. 다시 시도해 주세요.');
                      });
                    },
              child: const LocalizedText('저장')),
        ],
      );
}

/// Search-only handoff: never changes quantities, stock, or purchase status.
class OverseasIngredientSearch extends ConsumerStatefulWidget {
  const OverseasIngredientSearch(
      {super.key,
      required this.ingredient,
      this.specification = '',
      this.enabled = true});
  final String ingredient, specification;
  final bool enabled;
  @override
  ConsumerState<OverseasIngredientSearch> createState() =>
      _OverseasSearchState();
}

class _OverseasSearchState extends ConsumerState<OverseasIngredientSearch> {
  late final _query = TextEditingController(
      text: ingredientSearchName(
          widget.ingredient, ref.read(shoppingMarketProvider).language));
  late final _spec = TextEditingController(text: widget.specification);
  String? _message;
  bool _edited = false;
  @override
  void dispose() {
    _query.dispose();
    _spec.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(OverseasIngredientSearch oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.ingredient != widget.ingredient && !_edited) {
      _query.text = ingredientSearchName(
          widget.ingredient, ref.read(shoppingMarketProvider).language);
    }
    if (oldWidget.specification != widget.specification) {
      _spec.text = widget.specification;
    }
  }

  Future<void> _act({bool general = false, bool copy = false}) async {
    final owner = ref.read(activeAccountIdProvider);
    if (!widget.enabled || owner == null) return;
    try {
      final terms = shoppingSearchQuery(_query.text, specification: _spec.text);
      if (copy) {
        await Clipboard.setData(ClipboardData(text: terms));
      } else {
        final uri = ref
            .read(shoppingMarketProvider)
            .search(_query.text, specification: _spec.text, general: general);
        if (!await ref.read(shoppingLinkLauncherProvider)(uri)) {
          throw StateError('open');
        }
      }
      if (mounted && ref.read(activeAccountIdProvider) == owner) {
        setState(() => _message = copy ? context.tr('검색어를 복사했습니다.') : null);
      }
    } catch (_) {
      if (mounted && ref.read(activeAccountIdProvider) == owner) {
        setState(() =>
            _message = context.tr('검색어를 확인한 뒤 다시 시도하거나 복사하여 브라우저에서 검색하세요.'));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final market = ref.watch(shoppingMarketProvider);
    ref.listen(shoppingMarketProvider, (previous, next) {
      if (!_edited && previous?.language != next.language) {
        _query.text = ingredientSearchName(widget.ingredient, next.language);
      }
    });
    final enabled =
        widget.enabled && ref.watch(activeAccountIdProvider) != null;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      TextField(
        key: const ValueKey('overseas-search-query'),
        controller: _query,
        enabled: enabled,
        maxLength: 250,
        onChanged: (_) => _edited = true,
        decoration: InputDecoration(
            labelText: context.tr('현지 검색어'),
            helperText: context.tr('제안된 이름을 확인하고 현지에서 쓰는 표현으로 수정할 수 있습니다.'),
            helperMaxLines: 4),
      ),
      TextField(
          controller: _spec,
          enabled: enabled,
          maxLength: 120,
          decoration: InputDecoration(labelText: context.tr('규격·브랜드 (선택)'))),
      FilledButton.icon(
          onPressed: enabled ? () => _act() : null,
          icon: const Icon(Icons.open_in_new),
          label: LocalizedText(market.supportsShoppingTab
              ? 'Google 쇼핑에서 찾기'
              : 'Google에서 재료 찾기')),
      if (!market.supportsShoppingTab)
        const LocalizedText('이 국가에서는 일반 Google 검색으로 연결합니다.'),
      Wrap(spacing: 8, children: [
        if (market.supportsShoppingTab)
          TextButton(
              onPressed: enabled ? () => _act(general: true) : null,
              child: const LocalizedText('결과가 없나요? 일반 검색')),
        TextButton.icon(
            onPressed: enabled ? () => _act(copy: true) : null,
            icon: const Icon(Icons.copy_outlined),
            label: const LocalizedText('검색어 복사')),
      ]),
      if (_message != null) Text(_message!),
      const LocalizedText(
          '필요량은 참고용입니다. 판매처에서 포장·수량·배송 가능 여부를 확인하고 결제하세요. 검색만으로 구매 완료 처리되지 않습니다.'),
    ]);
  }
}
