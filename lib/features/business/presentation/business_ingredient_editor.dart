part of 'business_pages.dart';

class BusinessIngredientEditor extends StatelessWidget {
  const BusinessIngredientEditor(
      {super.key,
      required this.lines,
      required this.onChanged,
      required this.enabled});
  final List<MenuIngredient> lines;
  final ValueChanged<List<MenuIngredient>> onChanged;
  final bool enabled;
  Future<void> _standardize(BuildContext context) async {
    final next = lines.map(standardizeBusinessIngredient).toList();
    if (next.any((line) => line == null)) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(bt(context, '환산 범위를 벗어난 수량이 있습니다. 재료별 수량을 먼저 확인하세요.',
              'A quantity is outside the conversion range. Check each ingredient first.'))));
      return;
    }
    final changes = [
      for (var i = 0; i < lines.length; i++)
        if (lines[i].unit != next[i]!.unit ||
            lines[i].quantity != next[i]!.quantity)
          '${lines[i].label} → ${menuNumber(next[i]!.quantity)} ${next[i]!.unit}'
    ];
    if (changes.isEmpty) return;
    if (await businessConfirm(context,
        '${changes.join('\n')}\n\n${bt(context, '표준 단위로 정리할까요? g·ml·개로 통일하며 포장·조리 단위는 유지합니다. 저장 후 출시 메뉴에 새 레시피를 반영하고, 단위가 바뀐 재료의 구매 기준·재고 연결을 다시 확인하세요.', 'Standardize to g, ml and each? Package and cooking units stay unchanged. After saving, update released menus to this recipe revision and recheck purchasing defaults and stock links for changed units.')}')) {
      onChanged(next.cast<MenuIngredient>());
    }
  }

  Future<void> _edit(BuildContext context, [int? index]) async {
    final old = index == null ? null : lines[index];
    final form = GlobalKey<FormState>();
    final name = TextEditingController(text: old?.name),
        spec = TextEditingController(text: old?.spec),
        quantity = TextEditingController(
            text: old == null ? '' : menuNumber(old.quantity)),
        unit = TextEditingController(text: old?.unit);
    final result = await showDialog<MenuIngredient>(
        context: context,
        builder: (ctx) => ShoppingAccountGuard(
                child: AlertDialog(
                    scrollable: true,
                    title:
                        Text(bt(ctx, '구매 기준 재료', 'Ingredient purchase basis')),
                    content: SizedBox(
                        width: 450,
                        child: Form(
                            key: form,
                            child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  TextFormField(
                                      controller: name,
                                      maxLength: 150,
                                      decoration: InputDecoration(
                                          labelText: bt(
                                              ctx, '재료명', 'Ingredient name')),
                                      validator: (v) => (v ?? '').trim().isEmpty
                                          ? bt(ctx, '입력해 주세요.', 'Required.')
                                          : null),
                                  TextFormField(
                                      controller: spec,
                                      maxLength: 150,
                                      decoration: InputDecoration(
                                          labelText: bt(ctx, '규격·손질 상태',
                                              'Specification / preparation'))),
                                  TextFormField(
                                      controller: quantity,
                                      keyboardType:
                                          const TextInputType.numberWithOptions(
                                              decimal: true),
                                      decoration: InputDecoration(
                                          labelText: bt(ctx, '기준 인분에 필요한 조리량',
                                              'Cooking quantity for base servings')),
                                      validator: (v) {
                                        final n = parseUserNumber(v ?? '');
                                        return n == null ||
                                                !menuQuantityValid(n) ||
                                                n < 0.000001 ||
                                                n > 1e9
                                            ? bt(ctx, '올바른 수를 입력해 주세요.',
                                                'Enter a valid number.')
                                            : null;
                                      }),
                                  TextFormField(
                                      controller: unit,
                                      maxLength: 30,
                                      decoration: InputDecoration(
                                          labelText: bt(ctx, '조리 단위 (g·ml·개 등)',
                                              'Cooking unit (g / ml / pcs etc.)')),
                                      validator: (v) => (v ?? '').trim().isEmpty
                                          ? bt(ctx, '입력해 주세요.', 'Required.')
                                          : null),
                                  const SizedBox(height: 8),
                                  Wrap(spacing: 6, runSpacing: 6, children: [
                                    for (final u in businessStandardUnits)
                                      ActionChip(
                                          label: Text(
                                              AppLocalizations.of(ctx).isEnglish
                                                  ? u.en
                                                  : u.ko),
                                          onPressed: () {
                                            final n = parseUserNumber(
                                                quantity.text.trim());
                                            if (n != null &&
                                                businessUnitFactor(
                                                        unit.text, u.code) !=
                                                    null) {
                                              final converted =
                                                  businessConvertQuantity(
                                                      n, unit.text, u.code);
                                              if (converted == null) return;
                                              quantity.text =
                                                  menuNumber(converted);
                                            }
                                            unit.text = u.code;
                                          }),
                                  ]),
                                  Text(bt(
                                      ctx,
                                      '무게·부피·개수·포장을 구분하세요. 1봉·1컵의 양이나 g↔ml 환산은 재료마다 다르므로 추정하지 않습니다.',
                                      'Keep weight, volume, counts and packages distinct. A bag, cup or g↔ml conversion needs an ingredient-specific basis.')),
                                ]))),
                    actions: [
                  TextButton(
                      onPressed: () => Navigator.pop(ctx),
                      child: Text(bt(ctx, '취소', 'Cancel'))),
                  FilledButton(
                      onPressed: () {
                        if (form.currentState!.validate()) {
                          Navigator.pop(
                              ctx,
                              MenuIngredient(
                                  name: name.text.trim(),
                                  spec: spec.text.trim(),
                                  quantity: double.parse(quantity.text.trim()),
                                  unit: unit.text.trim()));
                        }
                      },
                      child: Text(bt(ctx, '반영', 'Apply')))
                ])));
    Future<void>.delayed(const Duration(seconds: 1), () {
      for (final c in [name, spec, quantity, unit]) {
        c.dispose();
      }
    });
    if (result != null && context.mounted) {
      final next = [...lines];
      if (index == null) {
        next.add(result);
      } else {
        next[index] = result;
      }
      onChanged(next);
    }
  }

  @override
  Widget build(BuildContext context) => Card(
      child: Padding(
          padding: const EdgeInsets.all(14),
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(bt(context, '구매 기준 재료', 'Ingredients for purchasing'),
                style: Theme.of(context).textTheme.titleMedium),
            Text(bt(
                context,
                '수량·단위를 등록하면 재료 목록을 이 값으로 저장합니다. 기존 자유 입력 재료는 자동 변환하지 않으므로 빠짐없이 확인하세요.',
                'Register quantities and units to save the ingredient list from these values. Existing free text is not converted automatically; check every ingredient.')),
            if (lines.any((line) => line.unit != businessBaseUnit(line.unit)))
              OutlinedButton.icon(
                  key: const Key('business-standardize-units'),
                  onPressed: enabled ? () => _standardize(context) : null,
                  icon: const Icon(Icons.swap_horiz),
                  label: Text(bt(context, '표준 단위로 정리 (g·ml·개)',
                      'Standardize units (g / ml / each)'))),
            for (final (i, line) in lines.indexed)
              ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(line.label),
                  onTap: enabled ? () => _edit(context, i) : null,
                  trailing: IconButton(
                      tooltip: bt(context, '재료 삭제', 'Remove ingredient'),
                      onPressed: enabled
                          ? () => onChanged([...lines]..removeAt(i))
                          : null,
                      icon: const Icon(Icons.close))),
            OutlinedButton.icon(
                onPressed:
                    enabled && lines.length < 100 ? () => _edit(context) : null,
                icon: const Icon(Icons.add),
                label: Text(bt(context, '수량·단위가 있는 재료 추가',
                    'Add ingredient with quantity and unit')))
          ])));
}
