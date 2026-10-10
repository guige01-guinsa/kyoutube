part of 'guide_sample_page.dart';

extension _SamplePurchase on _GuideSamplePageState {
  List<Widget> shoppingContent() => [
        panel(t('샘플 구매 목록 · 3개 재료', 'Sample shopping list · 3 ingredients'), [
          note(
              '이 목록은 채소 두부 비빔밥의 구매 연습자료입니다. 레시피 조리량과 별도로 구매 수량을 정합니다. 인분을 바꿔도 이 값은 유지됩니다.',
              'A purchase practice list for the vegetable & tofu bowl. Set quantities separately from cooking amounts. Changing servings does not change these values.'),
          for (final id in d.purchase.quantities.keys) ...[
            CheckboxListTile(
                key: Key('sample-select-$id'),
                contentPadding: EdgeInsets.zero,
                title: Text(d.ingredientName(id)),
                value: d.purchase.selected.contains(id),
                onChanged: (v) => change(() {
                      v!
                          ? d.purchase.selected.add(id)
                          : d.purchase.selected.remove(id);
                    })),
            if (d.purchase.selected.contains(id)) ...[
              DropdownButtonFormField<String>(
                  key: ValueKey('$_epoch-shopping-unit-$id'),
                  initialValue: d.purchaseUnits[id],
                  isExpanded: true,
                  decoration:
                      InputDecoration(labelText: t('구매 단위', 'Purchase unit')),
                  items: [
                    for (final unit in ['kg', 'g'])
                      DropdownMenuItem(value: unit, child: Text(unit))
                  ],
                  onChanged: (unit) {
                    if (unit != null) {
                      change(() {
                        d.purchaseUnits[id] = unit;
                        _epoch++;
                      });
                    }
                  }),
              const SizedBox(height: 16),
              numeric(
                  'shopping-$id',
                  '${t('구매 수량', 'Purchase quantity')} (${d.purchaseUnits[id]})',
                  convertPurchaseQuantity(
                      d.purchase.quantities[id]!, 'kg', d.purchaseUnits[id]!),
                  (v) => d.purchase.quantity(id,
                      convertPurchaseQuantity(v, d.purchaseUnits[id]!, 'kg')!),
                  min: d.purchaseUnits[id] == 'g' ? 1 : .001,
                  max: d.purchaseUnits[id] == 'g' ? 100000 : 100),
            ]
          ],
          metric(t('선택한 재료', 'Selected ingredients'),
              '${d.purchase.selected.length} / 3'),
          if (d.purchase.selected.isEmpty)
            note('최소 1개 재료를 선택해 주세요.', 'Select at least one ingredient.'),
          if (d.purchase.selected.isNotEmpty)
            action(
                'sample-create-shopping',
                '연습 장보기 목록 만들기',
                'Create practice shopping list',
                () => save(action: () => d.shoppingCreated = true)),
          if (d.shoppingCreated)
            note('이 목록으로 업체 후보 선택과 구매요청 작성을 이어갈 수 있어요.',
                'Continue with this list to supplier selection and purchase requests.')
        ])
      ];
  String priorityLabel(ProcurementPriority p) => switch (p) {
        ProcurementPriority.fewestSuppliers => t('최소 거래처수', 'Fewest suppliers'),
        ProcurementPriority.lowestPrice => t('최저 구매가격', 'Lowest purchase cost'),
        ProcurementPriority.highestRating => t('평점 우선', 'Highest rating')
      };
  List<String> favoriteFirst(Iterable<String> ids) => ids.toList()
    ..sort((a, b) {
      final favorite = (d.purchase.favorites.contains(b) ? 1 : 0) -
          (d.purchase.favorites.contains(a) ? 1 : 0);
      return favorite != 0 ? favorite : a.compareTo(b);
    });
  String supplierInfo(String id) =>
      '${t('배송비', 'Shipping')} ${money(id == 'B' || id == 'C' ? 500 : 1000)} · ★ ${switch (id) {
        'A' => '4.1',
        'B' => '4.5',
        'C' => '4.4',
        _ => '4.9'
      }}';
  List<Widget> purchaseContent() => switch (lesson.id) {
        'buy-quantity' => shoppingContent(),
        'buy-suppliers' => [
            panel(t('내 거래처 먼저 보기', 'Your suppliers first'), [
              note(
                  '가상의 업체 4곳입니다. 별표를 켜서 내 거래처로 선택하고 저장해 보세요. 실제 업체로 공개되지 않습니다.',
                  'Four fictional suppliers. Star and save your favorites. These are never published as real businesses.'),
              for (final id in favoriteFirst(GuidePurchaseExample.prices.keys))
                Card(
                    child: Padding(
                        padding: const EdgeInsets.all(14),
                        child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(d.supplierName(id),
                                  style:
                                      Theme.of(context).textTheme.titleMedium),
                              Text(GuidePurchaseExample.prices[id]!.keys
                                  .map(d.ingredientName)
                                  .join(' · ')),
                              Text(supplierInfo(id)),
                              CheckboxListTile(
                                  contentPadding: EdgeInsets.zero,
                                  title: Text(t('내 거래처', 'My supplier')),
                                  value: d.purchase.favorites.contains(id),
                                  onChanged: (v) => change(() {
                                        v!
                                            ? d.purchase.favorites.add(id)
                                            : d.purchase.favorites.remove(id);
                                      }))
                            ])))
            ])
          ],
        'buy-candidates' => [
            note('재료마다 취급업체를 최대 3곳 선택합니다. 내 거래처가 먼저 보이며, 선택은 다음 비교 화면에 이어집니다.',
                'Choose up to three suppliers per ingredient. Favorites appear first, and choices carry into the comparison.'),
            if (d.purchase.selected.isEmpty)
              panel(t('선택한 재료가 없어요', 'No selected ingredients'), [
                action(
                    'sample-restore-selection',
                    '샘플 재료 3개 선택',
                    'Select the 3 sample ingredients',
                    () => change(() =>
                        d.purchase.selected.addAll(d.purchase.quantities.keys)))
              ]),
            for (final item in d.purchase.selected)
              panel(
                  '${d.ingredientName(item)} · ${d.purchase.candidates[item]!.length}/3',
                  [
                    photo(item),
                    const SizedBox(height: 8),
                    for (final id in favoriteFirst(d.purchase.available(item)))
                      CheckboxListTile(
                          key: Key('sample-candidate-$item-$id'),
                          contentPadding: EdgeInsets.zero,
                          title: LocalizedText(
                              '${d.purchase.favorites.contains(id) ? '★ ' : ''}${d.supplierName(id)}'),
                          subtitle: LocalizedText(
                              '${money(GuidePurchaseExample.prices[id]![item])} / 1 kg · ${supplierInfo(id)}'),
                          value: d.purchase.candidates[item]!.contains(id),
                          onChanged: (v) {
                            if (v == true &&
                                !d.purchase.candidates[item]!.contains(id) &&
                                d.purchase.candidates[item]!.length >= 3) {
                              redraw(() => _error = t(
                                  '재료별 최대 3곳입니다. 다른 업체를 해제한 뒤 선택하세요.',
                                  'Choose up to three per ingredient. Deselect another supplier first.'));
                              return;
                            }
                            change(
                                () => d.purchase.toggleCandidate(item, id, v!));
                          }),
                    if (d.purchase.candidates[item]!.isEmpty)
                      note('비교하려면 이 재료의 후보를 1곳 이상 골라 주세요.',
                          'Select at least one supplier for this ingredient before comparing.')
                  ])
          ],
        'buy-compare' => [
            panel(
                t('같은 목록, 세 가지 구매 기준', 'One list, three purchasing priorities'),
                [
                  note(
                      '가상 단가·평점·배송비를 사용합니다. 표시된 금액에는 배송비가 포함되며, 상품은 1kg 포장 단위로 올림 계산합니다.',
                      'Fictional prices, ratings and delivery charges. Totals include shipping and round up to whole 1 kg packs.'),
                  for (final p in ProcurementPriority.values) comparison(p),
                  if (d.purchase.compare() != null)
                    action('sample-create-requests', '선택 기준으로 구매요청 초안 만들기',
                        'Create drafts using this priority', () async {
                      if (await save(action: d.createRequests) && mounted) {
                        context.replace(guideSamplePath('buy-request'));
                      }
                    }, icon: Icons.description_outlined)
                  else ...[
                    note('구매 재료와 재료별 업체 후보를 먼저 선택하세요.',
                        'Select ingredients and at least one candidate for each.'),
                    TextButton(
                        onPressed: () => openLesson('buy-candidates'),
                        child: Text(t('후보 선택으로 이동', 'Choose candidates')))
                  ]
                ])
          ],
        'buy-request' => requestContent(),
        'buy-ledger' => ledgerContent(),
        _ => []
      };
  Widget comparison(ProcurementPriority p) {
    final plan = d.purchase.compare(criterion: p);
    return Card(
        color: d.purchase.priority == p ? ScoutStyle.mint : null,
        child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(priorityLabel(p),
                      style: Theme.of(context).textTheme.titleMedium),
                  metric(
                      t('배송비 포함 예상 합계', 'Estimated total including shipping'),
                      plan == null ? '—' : money(plan.total)),
                  if (plan != null) ...[
                    LocalizedText(
                        '${t('거래처', 'Suppliers')}: ${plan.supplierIds.length}'),
                    for (final id in plan.supplierIds)
                      LocalizedText(
                          '${d.supplierName(id)} · ${plan.forSupplier(id).map((r) => '${d.ingredientName(r.line.name)} ${r.packs} × 1 kg').join(' / ')}')
                  ],
                  const SizedBox(height: 8),
                  OutlinedButton(
                      onPressed: plan == null
                          ? null
                          : () => change(() => d.purchase.priority = p),
                      child: Text(t(
                          d.purchase.priority == p ? '선택한 기준' : '이 기준 선택',
                          d.purchase.priority == p
                              ? 'Selected priority'
                              : 'Use this priority')))
                ])));
  }

  List<Widget> requestContent() {
    final r = d.request;
    return [
      panel(t('구매요청 초안 수정', 'Edit the purchase request draft'), [
        DropdownButtonFormField<String>(
            key: ValueKey('$_epoch-request-picker'),
            initialValue: r.id,
            isExpanded: true,
            decoration:
                InputDecoration(labelText: t('요청서 선택', 'Choose a request')),
            items: [
              for (final request in d.requests)
                DropdownMenuItem(
                    value: request.id,
                    child: LocalizedText('${request.supplier.name} · ${request.id}',
                        maxLines: 1, overflow: TextOverflow.ellipsis))
            ],
            onChanged: (id) {
              if (id != null) {
                change(() {
                  d.selectedRequest = id;
                  _epoch++;
                  _review = false;
                });
              }
            }),
        const SizedBox(height: 16),
        field('request-buyer', t('요청 업소', 'Buyer business'), r.buyer,
            (v) => d.updateRequest(d.request, fields: {'buyer': v})),
        field('request-address', t('납품 장소', 'Delivery address'), r.address,
            (v) => d.updateRequest(d.request, fields: {'address': v})),
        field(
            'request-delivery',
            t('희망 납품일', 'Requested delivery date'),
            r.deliveryDate,
            (v) => d.updateRequest(d.request, fields: {'delivery_date': v}),
            required: false),
        for (var i = 0; i < r.lines.length; i++) ...[
          Text(r.lines[i].name, style: Theme.of(context).textTheme.titleMedium),
          Text(r.lines[i].spec),
          numeric(
              'request-qty-$i',
              '${t('구매 수량', 'Quantity')} (${requestUnit(r.lines[i].unit, en)})',
              r.lines[i].quantity!,
              (v) => editRequestLine(i, {'quantity': v}),
              max: 1000),
          numeric(
              'request-price-$i',
              t('요청 단가 (KRW)', 'Requested unit price (KRW)'),
              r.lines[i].price,
              (v) => editRequestLine(i, {'price': v}),
              min: 0,
              max: 100000000)
        ],
        field('request-notes', t('요청 메모', 'Request notes'), r.notes,
            (v) => d.updateRequest(d.request, fields: {'notes': v}),
            lines: 3, max: 2000, required: false),
        ExpansionTile(
            key: const Key('sample-preview'),
            title: Text(t('구매요청서 미리보기', 'Preview purchase request')),
            children: [
              Padding(
                  padding: const EdgeInsets.all(12),
                  child: SelectableText(
                      '${t('연습용 · 실제 주문 아님', 'PRACTICE ONLY · NOT AN ORDER')}\n${supplierRequestText(d.request, english: en)}'))
            ]),
        const SizedBox(height: 12),
        action('sample-pdf', '저장 후 샘플 PDF 보기', 'Save & preview sample PDF',
            () async {
          if (await save() && mounted) {
            await context
                .push('${guideSamplePath(lesson.id)}/pdf/${d.request.id}');
          }
        }, icon: Icons.picture_as_pdf_outlined),
        const SizedBox(height: 16),
        CheckboxListTile(
            key: const Key('sample-request-review'),
            contentPadding: EdgeInsets.zero,
            value: _review,
            onChanged: (v) => redraw(() => _review = v!),
            title: Text(t('업체·수량·금액을 검토했어요',
                'I reviewed supplier, quantities and prices'))),
        Align(
            alignment: Alignment.centerLeft,
            child: FilledButton.icon(
                key: const Key('sample-send'),
                onPressed: _review
                    ? () => save(
                        action: () =>
                            d.updateRequest(d.request, status: 'sent'))
                    : null,
                icon: const Icon(Icons.send_outlined),
                label: Text(t('발송 모의 실행', 'Simulate sending')))),
        if (d.request.status == 'sent')
          note('모의 전달을 기록했어요. 실제 메시지나 주문은 전송되지 않았습니다. 대장에서 이 요청서를 볼 수 있어요.',
              'Simulated delivery recorded. No message or order was sent. This request is available in the practice ledger.')
      ])
    ];
  }

  void editRequestLine(int index, Map<String, dynamic> changes) {
    final rows = [...d.request.lines];
    rows[index] =
        SupplierRequestLine.fromJson({...rows[index].toJson(), ...changes});
    d.updateRequest(d.request,
        fields: {'lines': rows.map((r) => r.toJson()).toList()});
  }

  List<Widget> ledgerContent() => [
        panel(t('샘플 구매요청 대장', 'Practice purchase request ledger'), [
          note('모든 상태는 연습용 기록입니다. 업체 수락·입고·전달이 실제로 발생했다는 뜻이 아닙니다.',
              'All statuses are practice records, not evidence of actual supplier acceptance, receipt or delivery.'),
          metric(t('요청서 수', 'Requests'), '${d.requests.length}'),
          for (final r in d.requests)
            Card(
                child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Text(r.supplier.name,
                              style: Theme.of(context).textTheme.titleMedium),
                          Text(r.reference),
                          Text(r.lines
                              .map((l) =>
                                  '${l.name} ${number(l.quantity)} ${requestUnit(l.unit, en)}')
                              .join(' · ')),
                          const SizedBox(height: 12),
                          DropdownButtonFormField<String>(
                              key: ValueKey(
                                  '$_epoch-status-${r.id}-${r.status}'),
                              initialValue: r.status,
                              isExpanded: true,
                              decoration: InputDecoration(
                                  labelText: t('모의 처리 상태', 'Simulated status')),
                              items: [
                                for (final s in [
                                  'draft',
                                  'sent',
                                  'accepted',
                                  'received',
                                  'cancelled'
                                ])
                                  DropdownMenuItem(
                                      value: s,
                                      child: Text(requestStatus(s, en)))
                              ],
                              onChanged: (s) {
                                if (s != null) {
                                  change(() => d.updateRequest(r, status: s));
                                }
                              }),
                          const SizedBox(height: 12),
                          Wrap(spacing: 8, runSpacing: 8, children: [
                            TextButton(
                                onPressed: () async {
                                  if (await save(
                                          action: () =>
                                              d.selectedRequest = r.id) &&
                                      mounted) {
                                    context.replace(
                                        guideSamplePath('buy-request'));
                                  }
                                },
                                child: Text(t('수정·미리보기', 'Edit & preview'))),
                            OutlinedButton.icon(
                                key: Key('sample-repeat-${r.id}'),
                                onPressed: () async {
                                  if (await save(
                                          action: () => d.repeatRequest(r)) &&
                                      mounted) {
                                    context.replace(
                                        guideSamplePath('buy-request'));
                                  }
                                },
                                icon: const Icon(Icons.replay),
                                label: Text(
                                    t('다시 요청 초안', 'Draft a repeat request')))
                          ]),
                          Text(t('재요청 시 가격·납품일은 비워집니다. 새 조건을 확인해서 입력하세요.',
                              'Repeat requests clear prices and delivery dates. Review and enter new terms.'))
                        ])))
        ]),
      ];
}
