part of 'business_pages.dart';

/// Filtering changes presentation only; callers validate the complete plan.
class BusinessIngredientReview<T> extends StatefulWidget {
  const BusinessIngredientReview(
      {super.key,
      required this.items,
      required this.name,
      required this.needsReview,
      required this.builder});
  final List<T> items;
  final String Function(T) name;
  final bool Function(T) needsReview;
  final Widget Function(T) builder;
  @override
  State<BusinessIngredientReview<T>> createState() =>
      _BusinessIngredientReviewState<T>();
}

class _BusinessIngredientReviewState<T>
    extends State<BusinessIngredientReview<T>> {
  ShoppingCategory? _category;
  bool _reviewOnly = false;
  String _query = '';
  @override
  Widget build(BuildContext context) {
    final all = widget.items;
    final pending = all.where(widget.needsReview).length;
    final english = AppLocalizations.of(context).isEnglish;
    final visible = all
        .where((a) =>
            (!_reviewOnly || widget.needsReview(a)) &&
            productSearchMatches(widget.name(a), _query) &&
            (_category == null ||
                shoppingCategory(widget.name(a)) == _category))
        .toList();
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Card(
          child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                        bt(context, '재료 ${all.length}개 · 확인 필요 $pending개',
                            '${all.length} ingredients · $pending need review'),
                        key: const Key('business-ingredient-summary'),
                        style: Theme.of(context).textTheme.titleMedium),
                    Text(bt(
                        context,
                        '필요량 → 사용 가능 재고 → 부족량 → 포장 단위 구매량 순서로 확인하세요.',
                        'Check required quantity → available stock → shortfall → packs to buy.')),
                    Text(bt(
                        context,
                        '분류는 목록 정리용입니다. 같은 분류라도 재료·규격이 다르면 합치지 않습니다.',
                        'Categories organize the list. Different ingredients or specifications are kept separate.')),
                  ]))),
      TextField(
          key: const Key('business-ingredient-search'),
          decoration: InputDecoration(
              labelText: bt(context, '재료 찾기', 'Find an ingredient'),
              prefixIcon: const Icon(Icons.search)),
          onChanged: (v) => setState(() => _query = v)),
      const SizedBox(height: 8),
      Wrap(spacing: 6, runSpacing: 6, children: [
        ChoiceChip(
            label: Text(bt(context, '전체 재료', 'All ingredients')),
            selected: _category == null,
            onSelected: (_) => setState(() => _category = null)),
        for (final c in ShoppingCategory.values)
          if (all.any((a) => shoppingCategory(widget.name(a)) == c))
            ChoiceChip(
                label: LocalizedText(
                    '${english ? c.en : c.ko} ${all.where((a) => shoppingCategory(widget.name(a)) == c).length}'),
                selected: _category == c,
                onSelected: (_) => setState(() => _category = c)),
        FilterChip(
            key: const Key('business-ingredients-pending'),
            label: Text(bt(context, '확인 필요만', 'Needs review only')),
            selected: _reviewOnly,
            onSelected: (v) => setState(() => _reviewOnly = v)),
      ]),
      const SizedBox(height: 12),
      if (visible.isEmpty)
        Padding(
            padding: const EdgeInsets.all(12),
            child: Text(bt(context, '조건에 맞는 재료가 없습니다. 전체 재료를 선택하거나 필터를 해제하세요.',
                'No matching ingredients. Select all categories or clear the filters.'))),
      for (final c in ShoppingCategory.values)
        if (visible.any((a) => shoppingCategory(widget.name(a)) == c)) ...[
          Padding(
              padding: const EdgeInsets.only(top: 12, bottom: 4),
              child: Text(english ? c.en : c.ko,
                  style: Theme.of(context).textTheme.titleMedium)),
          for (final a
              in visible.where((a) => shoppingCategory(widget.name(a)) == c))
            widget.builder(a),
        ],
    ]);
  }
}

/// Input can use a compatible physical unit; callbacks always use the recipe's
/// original unit. There is deliberately no mass/volume or package inference.
class BusinessQuantityField extends StatefulWidget {
  const BusinessQuantityField(
      {super.key,
      required this.label,
      required this.unit,
      required this.value,
      required this.enabled,
      required this.onChanged});
  final String label, unit;
  final double? value;
  final bool enabled;
  final ValueChanged<double?> onChanged;
  @override
  State<BusinessQuantityField> createState() => _BusinessQuantityFieldState();
}

class _BusinessQuantityFieldState extends State<BusinessQuantityField> {
  late final _text = TextEditingController(
      text: widget.value == null ? '' : menuNumber(widget.value!));
  late String _unit = widget.unit;
  double? _reported;
  @override
  void initState() {
    super.initState();
    _reported = widget.value;
  }

  @override
  void didUpdateWidget(covariant BusinessQuantityField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.unit != oldWidget.unit || widget.value != _reported) {
      _unit = widget.unit;
      _text.text = widget.value == null ? '' : menuNumber(widget.value!);
      _reported = widget.value;
    }
  }

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  void _change() {
    final n = parseUserNumber(_text.text.trim());
    _reported =
        n == null ? null : businessConvertQuantity(n, _unit, widget.unit);
    widget.onChanged(_reported);
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final standard = businessStandardUnit(widget.unit);
    final alternatives = businessStandardUnits
        .where(
            (u) => u.dimension == standard?.dimension && u.code != widget.unit)
        .toList();
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      TextField(
          controller: _text,
          enabled: widget.enabled,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: InputDecoration(
              labelText: '${widget.label} ($_unit)',
              errorText: _text.text.isNotEmpty && _reported == null
                  ? bt(context, '수량·환산 범위를 확인하세요.',
                      'Check the quantity / conversion range.')
                  : null),
          onChanged: (_) => _change()),
      if (alternatives.isNotEmpty)
        DropdownButton<String>(
            isExpanded: true,
            value: _unit,
            items: [
              DropdownMenuItem(value: widget.unit, child: Text(widget.unit)),
              for (final u in alternatives)
                DropdownMenuItem(
                    value: u.code,
                    child: Text(
                        AppLocalizations.of(context).isEnglish ? u.en : u.ko))
            ],
            onChanged: !widget.enabled
                ? null
                : (v) {
                    if (v == null || v == _unit) return;
                    final n = parseUserNumber(_text.text.trim());
                    final converted =
                        n == null ? null : businessConvertQuantity(n, _unit, v);
                    // Keep unrepresentable amounts in their original unit for correction.
                    if (n != null && converted == null) return;
                    _unit = v;
                    _text.text = converted == null ? '' : menuNumber(converted);
                    _change();
                  }),
      if (_unit != widget.unit && _reported != null)
        LocalizedText(
            '${bt(context, '환산', 'Converted')}: ${menuNumber(_reported!)} ${widget.unit}'),
    ]);
  }
}
