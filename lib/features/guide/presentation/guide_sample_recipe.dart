part of 'guide_sample_page.dart';

extension _SampleRecipe on _GuideSamplePageState {
  Widget recipePicker({bool home = false}) => Padding(
      padding: const EdgeInsets.only(bottom: 18),
      child: DropdownButtonFormField<String>(
          key: ValueKey('$_epoch-recipe-picker'),
          initialValue: d.selectedRecipe,
          isExpanded: true,
          decoration:
              InputDecoration(labelText: t('샘플 레시피 선택', 'Sample recipe')),
          items: [
            for (final e in d.recipes.entries.where((e) =>
                !home ||
                ['bowl', 'stew', 'fried-rice', d.selectedRecipe]
                    .contains(e.key)))
              DropdownMenuItem(value: e.key, child: Text(e.value.title))
          ],
          onChanged: (id) {
            if (id != null) {
              change(() {
                d.selectedRecipe = id;
                _epoch++;
                _review = false;
              });
            }
          }));
  List<Widget> homeContent() => switch (lesson.id) {
        'home-search' => [
            panel(t('검색해서 내 요리 고르기', 'Find a recipe to try'), [
              note('실제 영상 검색 대신 준비된 샘플 3개를 사용합니다. 요리를 고르면 초안 검토에서 이어집니다.',
                  'Search three prepared samples instead of live videos. Your choice continues into draft review.'),
              field('search', t('요리 검색', 'Search recipes'), d.search,
                  (v) => d.search = v,
                  required: false),
              for (final e in d.recipes.entries.take(3).where((e) =>
                  d.search.trim().isEmpty ||
                  e.value.title
                      .toLowerCase()
                      .contains(d.search.trim().toLowerCase())))
                Card(
                    color: d.selectedRecipe == e.key ? ScoutStyle.mint : null,
                    child: Padding(
                        padding: const EdgeInsets.all(14),
                        child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              photo(e.key == 'fried-rice' ? 'egg' : 'tofu'),
                              const SizedBox(height: 10),
                              Text(e.value.title,
                                  style:
                                      Theme.of(context).textTheme.titleMedium),
                              Text(t('4인분 · 조리 기준과 재료가 준비되어 있어요',
                                  '4 servings · ingredients and instructions provided')),
                              TextButton(
                                  onPressed: () =>
                                      change(() => d.selectedRecipe = e.key),
                                  child: Text(t(
                                      d.selectedRecipe == e.key
                                          ? '선택됨'
                                          : '이 요리 선택',
                                      d.selectedRecipe == e.key
                                          ? 'Selected'
                                          : 'Choose recipe')))
                            ]))),
              if (!d.recipes.values.take(3).any((r) => r.title
                  .toLowerCase()
                  .contains(d.search.trim().toLowerCase())))
                note('검색 결과가 없어요. 검색어를 지우면 샘플 3개를 볼 수 있어요.',
                    'No matches. Clear the search to see all three samples.')
            ])
          ],
        'home-draft' => [
            recipePicker(home: true),
            panel(t('AI 초안 검토 연습', 'Review a sample AI draft'), [
              note(
                  '미리 준비한 초안입니다. 실제 영상 분석·AI 호출·사용량 차감이 없습니다. 재료 수량을 수정하고 검토 표시를 해보세요.',
                  'A prepared draft. No live video analysis, AI request or quota use. Edit an ingredient amount and mark your review.'),
              ...recipeFields(),
              CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(t('재료와 조리 순서를 검토했어요',
                      'I reviewed ingredients and instructions')),
                  value: d.draftReviewed,
                  onChanged: (v) => change(() => d.draftReviewed = v!))
            ])
          ],
        'home-save' => [
            recipePicker(home: true),
            panel(t('내 레시피로 정리', 'Make the recipe your own'), [
              ...recipeFields(ingredients: false),
              metric(
                  t('검토 상태', 'Review'),
                  d.draftReviewed
                      ? t('검토함', 'Reviewed')
                      : t('확인 필요', 'Needs review')),
              note('아래 저장 버튼을 누르면 이 레시피의 수정 내용이 연습 공간에 남습니다.',
                  'Save below to keep these recipe edits in your practice workspace.')
            ])
          ],
        'home-shopping' => shoppingContent(),
        'home-repeat' => [
            recipePicker(home: true),
            panel(t('구매 이력과 다음 요리 메모', 'Purchase history & cooking notes'), [
              note('구매 완료를 기록해도 조리 사용량에 따라 재고를 차감하지 않습니다.',
                  'Completing a purchase does not deduct inventory when you cook.'),
              for (final id in d.purchase.selected)
                CheckboxListTile(
                    contentPadding: EdgeInsets.zero,
                    title: LocalizedText(
                        '${d.ingredientName(id)} · ${number(d.purchase.quantities[id])} kg'),
                    subtitle: Text(t('샘플 구매 완료', 'Sample purchase completed')),
                    value: d.bought.contains(id),
                    onChanged: (v) => change(() {
                          v! ? d.bought.add(id) : d.bought.remove(id);
                        })),
              metric(
                  t('구매 완료 기록', 'Completed purchases'), '${d.bought.length}'),
              field('repeat-notes', t('다음 조리 때 기억할 점', 'Notes for next time'),
                  d.recipe.notes, (v) => d.changeRecipe({'notes': v}),
                  lines: 3, required: false, max: 1000),
              action(
                  'sample-repeat-shopping',
                  '같은 구매 목록 다시 준비',
                  'Prepare this shopping list again',
                  () => save(action: () {
                        d.bought.clear();
                        d.shoppingCreated = true;
                      }),
                  icon: Icons.replay)
            ])
          ],
        _ => []
      };

  List<Widget> recipeFields({bool ingredients = true}) => [
        field('recipe-title', t('레시피 이름', 'Recipe name'), d.recipe.title,
            (v) => d.changeRecipe({'title': v})),
        if (ingredients)
          for (var i = 0; i < d.recipe.ingredients.length; i++) ...[
            Text(d.recipe.ingredients[i].name,
                style: Theme.of(context).textTheme.titleMedium),
            numeric(
                'recipe-qty-$i',
                t('조리 사용량', 'Cooking quantity'),
                d.recipe.ingredients[i].quantity!,
                (v) => updateIngredient(i, {'quantity': v})),
            ChefUnitField(
                key: ValueKey('$_epoch-recipe-unit-$i'),
                label: t('조리 단위', 'Cooking unit'),
                value: d.recipe.ingredients[i].unit,
                onChanged: (v) =>
                    change(() => updateIngredient(i, {'unit': v.name})))
          ],
        field('recipe-steps', t('조리 순서', 'Cooking instructions'),
            d.recipe.steps, (v) => d.changeRecipe({'steps': v}),
            lines: 3, max: 2000),
        field('recipe-notes', t('내 메모', 'My notes'), d.recipe.notes,
            (v) => d.changeRecipe({'notes': v}),
            lines: 2, max: 1000, required: false)
      ];
  void updateIngredient(int i, Map<String, dynamic> values) =>
      d.changeIngredient(
          i,
          ChefIngredient.fromJson(
              {...d.recipe.ingredients[i].toJson(), ...values}));
  List<Widget> chefContent() => [
        recipePicker(),
        ...switch (lesson.id) {
          'pro-standard' => [
              panel(t('기준 레시피', 'Standard recipe'), [
                numeric(
                    'base-servings',
                    t('기준 인분', 'Base servings'),
                    d.recipe.baseServings!,
                    (v) => d.changeRecipe({'baseServings': v}),
                    max: 1000),
                ...recipeFields()
              ])
            ],
          'pro-scale' => [
              panel(t('인분 자동 환산', 'Scale cooking quantities'), [
                numeric(
                    'target-servings',
                    t('목표 인분', 'Target servings'),
                    d.recipe.targetServings!,
                    (v) => d.changeRecipe({'targetServings': v}),
                    max: 1000),
                metric(
                    t('환산 배수', 'Scale factor'), '× ${number(d.recipe.ratio)}'),
                for (final i in d.recipe.ingredients)
                  metric(i.name,
                      '${number(i.quantity! * d.recipe.ratio!)} ${i.unit.displayLabel(en)}'),
                note('인분에 따른 조리 사용량입니다. 장보기 구매 수량은 별도로 정합니다.',
                    'These are scaled cooking quantities. Set shopping purchase quantities separately.')
              ])
            ],
          'pro-yield' => [
              for (var i = 0; i < d.recipe.ingredients.length; i++)
                panel(d.recipe.ingredients[i].name, [
                  numeric(
                      'yield-$i',
                      t('손질 수율 (%)', 'Trim yield (%)'),
                      d.recipe.ingredients[i].yieldPercent,
                      (v) => updateIngredient(i, {'yieldPercent': v}),
                      min: 1,
                      max: 100),
                  metric(t('손질 후 조리 사용량', 'Edible cooking quantity'),
                      '${number(d.recipe.ingredients[i].quantity! * d.recipe.ratio!)} ${d.recipe.ingredients[i].unit.displayLabel(en)}'),
                  metric(t('원가 계산용 손질 전 분량', 'Pre-trim quantity for costing'),
                      '${number(d.recipe.ingredients[i].neededPurchase(d.recipe.ratio!))} ${d.recipe.ingredients[i].unit.displayLabel(en)}'),
                  note('원가를 계산하기 위한 손실 반영입니다. 장보기 목록이나 재고 수량을 자동 변경하지 않습니다.',
                      'This accounts for trimming loss in costing. It does not change shopping or inventory quantities.')
                ])
            ],
          'pro-cost' => [
              for (var i = 0; i < d.recipe.ingredients.length; i++)
                panel(d.recipe.ingredients[i].name, [
                  numeric(
                      'pack-qty-$i',
                      t('구매 포장량', 'Purchased pack quantity'),
                      d.recipe.ingredients[i].purchaseQuantity!,
                      (v) => updateIngredient(i, {'purchaseQuantity': v})),
                  ChefUnitField(
                      key: ValueKey('$_epoch-pack-unit-$i'),
                      label: t('구매 단위', 'Purchase unit'),
                      value: d.recipe.ingredients[i].purchaseUnit,
                      onChanged: (v) => change(
                          () => updateIngredient(i, {'purchaseUnit': v.name}))),
                  if (d.recipe.ingredients[i].unit
                          .convert(1, d.recipe.ingredients[i].purchaseUnit) ==
                      null) ...[
                    note('서로 다른 단위입니다. 원가 계산에 사용할 환산 기준을 직접 알려 주세요.',
                        'These units differ. Enter your conversion for costing.'),
                    numeric(
                        'conversion-$i',
                        '1 ${d.recipe.ingredients[i].purchaseUnit.displayLabel(en)} = ? ${d.recipe.ingredients[i].unit.displayLabel(en)}',
                        d.recipe.ingredients[i].purchaseUnitInUsageUnits,
                        (v) => updateIngredient(
                            i, {'purchaseUnitInUsageUnits': v}))
                  ],
                  numeric(
                      'pack-price-$i',
                      t('포장 구매가 (KRW)', 'Pack price (KRW)'),
                      d.recipe.ingredients[i].purchasePrice!,
                      (v) => updateIngredient(i, {'purchasePrice': v}),
                      min: 0,
                      max: 100000000),
                  metric(t('재료 원가', 'Ingredient cost'),
                      money(d.recipe.ingredients[i].cost(d.recipe.ratio!)))
                ]),
              panel(t('추가 비용', 'Additional costs'), [
                for (var i = 0; i < d.recipe.costItems.length; i++) ...[
                  field('cost-name-$i', t('항목명', 'Cost item'),
                      d.recipe.costItems[i].name, (v) => costItem(i, name: v)),
                  numeric(
                      'cost-amount-$i',
                      t('기준 인분 비용 (KRW)', 'Cost for base servings (KRW)'),
                      d.recipe.costItems[i].amount,
                      (v) => costItem(i, amount: v),
                      min: 0),
                  TextButton(
                      onPressed: () => change(() {
                            final rows = [...d.recipe.costItems]..removeAt(i);
                            d.changeRecipe({
                              'costItems': rows.map((c) => c.toJson()).toList()
                            });
                            _epoch++;
                          }),
                      child: Text(t('이 비용 삭제', 'Remove this cost')))
                ],
                if (d.recipe.costItems.length < 10)
                  OutlinedButton.icon(
                      onPressed: () => change(() => d.changeRecipe({
                            'costItems': [
                              ...d.recipe.costItems.map((c) => c.toJson()),
                              ChefCostItem(
                                      id: 'sample-cost-${++d.serial}',
                                      name: t('추가 비용', 'Extra cost'),
                                      amount: 0)
                                  .toJson()
                            ]
                          })),
                      icon: const Icon(Icons.add),
                      label: Text(t('비용 항목 추가', 'Add cost item')))
              ])
            ],
          'pro-pricing' => [
              panel(t('원가에 이익 가산', 'Set cost markup'), [
                numeric(
                    'markup',
                    t('이익 가산율 (0~100%)', 'Markup (0–100%)'),
                    d.recipe.markupPercent,
                    (v) => d.changeRecipe({'markupPercent': v}),
                    min: 0,
                    max: 100),
                metric(t('자동 판매가', 'Calculated selling price'),
                    money(d.recipe.sellingPrice)),
                note('판매가 = 1인분 원가 × (1 + 가산율). 원가에 더하는 비율이며 매출 대비 마진율과 다릅니다.',
                    'Selling price = portion cost × (1 + markup). Markup is based on cost, not a margin percentage of sales.')
              ])
            ],
          'pro-sales' => [
              panel(
                  t('판매 입력 · 일/주/월 보기', 'Record sales · day / week / month'), [
                note('샘플 날짜는 자료를 처음 준비한 날을 기준으로 합니다. 금액은 모두 KRW입니다.',
                    'Sample dates are anchored to the day these records were prepared. All amounts are KRW.'),
                Text(chefDate(d.anchor)),
                numeric('sale-quantity', t('판매 수량', 'Sold portions'),
                    _saleQuantity.toDouble(), (v) => _saleQuantity = v.toInt(),
                    min: 1, max: 10000, integer: true),
                action('sample-add-sale', '샘플 매출 기록', 'Record sample sale',
                    () => save(action: () => d.recordSale(_saleQuantity))),
                const SizedBox(height: 16),
                Wrap(spacing: 8, runSpacing: 8, children: [
                  for (final p in ChefSalesPeriod.values)
                    ChoiceChip(
                        label: Text(switch (p) {
                          ChefSalesPeriod.day => t('일', 'Day'),
                          ChefSalesPeriod.week => t('주', 'Week'),
                          ChefSalesPeriod.month => t('월', 'Month')
                        }),
                        selected: _period == p,
                        onSelected: (_) => redraw(() => _period = p))
                ]),
                metric(
                    t('판매량', 'Portions sold'), '${d.totals(_period).quantity}'),
                metric(t('매출액', 'Revenue'), money(d.totals(_period).revenue)),
                metric(t('매출 − 기록한 원가', 'Revenue − recorded costs'),
                    money(d.totals(_period).profit)),
                note('수익 표시는 기록한 원가를 뺀 값입니다. 입력하지 않은 임차료·세금 등은 포함되지 않습니다.',
                    'The difference subtracts recorded costs only. Unentered rent, taxes and other expenses are excluded.'),
                ExpansionTile(
                    title: Text(t('샘플 판매 기록', 'Sample sales records')),
                    children: [
                      for (final s in d.sales.reversed.take(12))
                        ListTile(
                            title: Text(s.title),
                            subtitle: LocalizedText(
                                '${chefDate(s.date)} · ${s.quantity} × ${money(s.unitPrice)}'))
                    ])
              ])
            ],
          'pro-versions' => [
              panel(t('수정 전후 비교', 'Compare recipe versions'), [
                field('version-notes', t('개선 메모', 'Improvement note'),
                    d.recipe.notes, (v) => d.changeRecipe({'notes': v}),
                    lines: 2, max: 1000, required: false),
                numeric(
                    'version-markup',
                    t('비교해 볼 가산율 (%)', 'Markup to compare (%)'),
                    d.recipe.markupPercent,
                    (v) => d.changeRecipe({'markupPercent': v}),
                    min: 0,
                    max: 100),
                DropdownButtonFormField<int>(
                    key: ValueKey('$_epoch-versions'),
                    initialValue: _version.clamp(
                        0, d.versions[d.selectedRecipe]!.length - 1),
                    isExpanded: true,
                    decoration: InputDecoration(
                        labelText: t('비교할 저장 버전', 'Saved version to compare')),
                    items: [
                      for (var i = 0;
                          i < d.versions[d.selectedRecipe]!.length;
                          i++)
                        DropdownMenuItem(
                            value: i,
                            child: LocalizedText(
                                '${t('저장 버전', 'Saved version')} ${d.versions[d.selectedRecipe]!.length - i}'))
                    ],
                    onChanged: (v) => redraw(() => _version = v!)),
                const SizedBox(height: 16),
                ...versionDiff(),
                action(
                    'sample-version',
                    '새 버전으로 저장',
                    'Save new version',
                    () => save(action: () {
                          d.snapshot();
                          _epoch++;
                          _version = 1;
                        }))
              ])
            ],
          'pro-ai' => [
              panel(t('영상 분석 결과 검토 연습', 'Review a sample video analysis'), [
                note(
                    '월간 프리미엄 영상 분석의 검토 흐름을 미리 체험합니다. 샘플 응답을 사용하므로 요금·분석 횟수가 발생하지 않습니다.',
                    'Try the review workflow for premium video analysis. Prepared responses use no AI quota or fees.'),
                action(
                    'sample-ai',
                    '준비된 분석 결과 불러오기',
                    'Load prepared analysis',
                    () => change(() {
                          d.changeRecipe({
                            'notes': t(
                                '샘플 분석: 기준 4인분. 두부와 채소의 수량은 재료 표에서 확인하세요. 조리 시간은 원본 확인이 필요합니다.',
                                'Sample analysis: 4 base servings. Review tofu and vegetable quantities in the ingredient table. Verify cooking times against the source.')
                          });
                          _epoch++;
                        })),
                const SizedBox(height: 16),
                ...recipeFields(),
                CheckboxListTile(
                    contentPadding: EdgeInsets.zero,
                    value: d.aiReviewed,
                    onChanged: (v) => change(() => d.aiReviewed = v!),
                    title: Text(t('근거가 없는 수량·시간을 확인했어요',
                        'I checked unsupported quantities and times')))
              ])
            ],
          _ => []
        },
        panel(t('현재 레시피 계산 결과', 'Current recipe calculation'), [
          metric(t('기준 → 목표 인분', 'Base → target servings'),
              '${number(d.recipe.baseServings)} → ${number(d.recipe.targetServings)}'),
          metric(t('전체 원가', 'Batch cost'), money(d.recipe.batchCost)),
          metric(t('1인분 원가', 'Portion cost'), money(d.recipe.portionCost)),
          metric(t('1인분 판매가', 'Selling price per portion'),
              money(d.recipe.sellingPrice)),
          if (d.recipe.incompleteCosts > 0)
            note('빠진 단가 또는 환산 기준을 원가 체험에서 입력하면 계산됩니다.',
                'Enter missing prices or conversion factors in the costing lesson to finish the calculation.')
        ])
      ];
  void costItem(int i, {String? name, double? amount}) {
    final rows = [...d.recipe.costItems], old = rows[i];
    rows[i] = ChefCostItem(
        id: old.id, name: name ?? old.name, amount: amount ?? old.amount);
    d.changeRecipe({'costItems': rows.map((r) => r.toJson()).toList()});
  }

  List<Widget> versionDiff() {
    final versions = d.versions[d.selectedRecipe]!,
        old = versions[_version.clamp(0, versions.length - 1)];
    final differences = old.compare(d.recipe);
    return [
      metric(t('비교 원가 → 현재 원가', 'Previous → current cost'),
          '${money(old.portionCost)} → ${money(d.recipe.portionCost)}'),
      if (differences.isEmpty)
        note('변경이 없어요. 메모나 가산율을 바꿔 보세요.',
            'No differences yet. Try editing the note or markup.'),
      for (final diff in differences)
        ListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(diff.ingredient ??
                switch (diff.field) {
                  'notes' => t('메모', 'Notes'),
                  'markupPercent' => t('가산율', 'Markup'),
                  'title' => t('이름', 'Name'),
                  'targetServings' => t('목표 인분', 'Target servings'),
                  'baseServings' => t('기준 인분', 'Base servings'),
                  'steps' => t('조리 순서', 'Instructions'),
                  _ => t('레시피 변경', 'Recipe change')
                }),
            subtitle: LocalizedText('${diff.before ?? '—'} → ${diff.after ?? '—'}'))
    ];
  }
}
