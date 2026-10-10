part of 'guide_sample_page.dart';

extension _SampleSupplier on _GuideSamplePageState {
  List<Widget> supplierContent() => switch (lesson.id) {
        'supplier-profile' => [
            panel(t('가상 업체 정보', 'Fictional business profile'), [
              field('business-name', t('업체명 · 필수', 'Business name · required'),
                  d.businessName, (v) {
                d.businessName = v;
                d.published = false;
              }),
              field(
                  'business-region',
                  t('배송 지역 · 필수', 'Delivery area · required'),
                  d.businessRegion, (v) {
                d.businessRegion = v;
                d.published = false;
              }),
              field(
                  'business-intro',
                  t('업체 소개 · 선택', 'Business introduction · optional'),
                  d.businessIntro, (v) {
                d.businessIntro = v;
                d.published = false;
              }, lines: 3, required: false, max: 1000),
              note('연락처나 사업자등록증 없이 연습할 수 있어요. 실제 개인정보 대신 가상의 이름과 지역을 사용하세요.',
                  'Practice without a phone number or certificate. Use fictional names and locations.')
            ])
          ],
        'supplier-product' => productEditor(pack: false),
        'supplier-pack' => productEditor(pack: true),
        'supplier-publish' => [
            panel(t('공개 전 확인', 'Review before publishing'), [
              Text(d.businessName,
                  style: Theme.of(context).textTheme.titleMedium),
              Text(d.businessRegion),
              Text(d.businessIntro),
              const SizedBox(height: 16),
              ...productCards(),
              CheckboxListTile(
                  key: const Key('sample-publish-review'),
                  contentPadding: EdgeInsets.zero,
                  value: _review,
                  onChanged: (v) => redraw(() => _review = v!),
                  title: Text(t('업체 정보·상품 이미지·규격·가격을 확인했어요',
                      'I checked the profile, images, packs and prices'))),
              Align(
                  alignment: Alignment.centerLeft,
                  child: FilledButton.icon(
                      key: const Key('sample-publish'),
                      onPressed: _review && d.publishable
                          ? () => save(action: () => d.published = true)
                          : null,
                      icon: const Icon(Icons.public),
                      label: Text(
                          t('회원 공개 모의 실행', 'Simulate member publication')))),
              if (d.published)
                note('샘플 공개 완료! 이 작업실에서만 공개 상태로 보입니다. 실제 회원에게 노출되지 않습니다.',
                    'Sample publication complete! It is visible only in this practice workspace, never to real members.'),
              if (!d.publishable)
                note('업체명·배송 지역·상품명·규격·가격을 먼저 채워 주세요.',
                    'Complete the business name, delivery area, product names, pack sizes and prices first.')
            ])
          ],
        'supplier-update' => [
            panel(t('상품 정보 유지 관리', 'Keep product information current'), [
              note('원하는 상품을 골라 가격이나 규격을 바꾸고 저장하세요. 공개 검토 화면에서도 수정한 정보가 보입니다.',
                  'Choose a product, edit its price or pack, and save. The publication review uses your saved changes.'),
              ...productEditor(pack: true, wrapped: false)
            ])
          ],
        _ => []
      };
  List<Widget> productCards() => [
        for (final p in d.products)
          Padding(
              padding: const EdgeInsets.only(bottom: 16),
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    photo(p.image),
                    const SizedBox(height: 8),
                    Text(p.name,
                        style: Theme.of(context).textTheme.titleMedium),
                    LocalizedText(
                        '${number(p.content)} ${p.unit} / ${t('포장', 'pack')} · ${money(p.price)}'),
                    LocalizedText('${p.origin} · ${p.region}')
                  ]))
      ];
  List<Widget> productEditor({required bool pack, bool wrapped = true}) {
    final p = d.products[_product];
    final widgets = <Widget>[
      DropdownButtonFormField<int>(
          key: ValueKey('$_epoch-product-picker'),
          initialValue: _product,
          isExpanded: true,
          decoration: InputDecoration(
              labelText: t('샘플 상품 6개 중 선택', 'Choose one of 6 sample products')),
          items: [
            for (var i = 0; i < d.products.length; i++)
              DropdownMenuItem(value: i, child: Text(d.products[i].name))
          ],
          onChanged: (i) {
            if (i != null) {
              redraw(() {
                _product = i;
                _epoch++;
                _review = false;
              });
            }
          }),
      const SizedBox(height: 16),
      photo(p.image, height: 160),
      const SizedBox(height: 16),
      if (!pack) ...[
        field('product-name', t('상품명 · 필수', 'Product name · required'), p.name,
            (v) {
          p.name = v;
          d.published = false;
        }),
        Text(t('준비된 상품 이미지 선택', 'Choose a prepared product image')),
        const SizedBox(height: 8),
        Wrap(spacing: 8, runSpacing: 8, children: [
          for (final id in GuideSampleData.imageIds)
            Semantics(
                label: d.ingredientName(id),
                selected: p.image == id,
                button: true,
                child: InkWell(
                    key: Key('sample-photo-$id'),
                    borderRadius: BorderRadius.circular(12),
                    onTap: () => change(() {
                          p.image = id;
                          d.published = false;
                        }),
                    child: Container(
                        width: 96,
                        padding: const EdgeInsets.all(4),
                        decoration: BoxDecoration(
                            border: Border.all(
                                color: p.image == id
                                    ? ScoutStyle.forest
                                    : Colors.transparent,
                                width: 3),
                            borderRadius: BorderRadius.circular(12)),
                        child: Column(children: [
                          photo(id, height: 56),
                          Text(d.ingredientName(id),
                              textAlign: TextAlign.center)
                        ]))))
        ]),
        const SizedBox(height: 16),
        DropdownButtonFormField<String>(
            key: ValueKey('$_epoch-category'),
            initialValue: p.category,
            isExpanded: true,
            decoration:
                InputDecoration(labelText: t('상품 분류', 'Product category')),
            items: [
              for (final id in [
                'vegetables',
                'mushrooms',
                'tofu',
                'eggs',
                'grains'
              ])
                DropdownMenuItem(
                    value: id, child: Text(supplierCategoryLabel(id, en)))
            ],
            onChanged: (v) {
              if (v != null) {
                change(() {
                  p.category = v;
                  d.published = false;
                });
              }
            }),
        const SizedBox(height: 16),
        field('product-origin', t('원산지', 'Origin'), p.origin, (v) {
          p.origin = v;
          d.published = false;
        }, required: false),
        field('product-region', t('배송 지역', 'Delivery area'), p.region, (v) {
          p.region = v;
          d.published = false;
        })
      ] else ...[
        numeric('product-content', t('포장당 내용량', 'Content per pack'), p.content,
            (v) {
          p.content = v;
          d.published = false;
        }, max: 100000),
        ChefUnitField(
            key: ValueKey('$_epoch-product-unit'),
            label: t('내용량 단위', 'Content unit'),
            value: ChefUnit.parse(p.unit),
            onChanged: (v) => change(() {
                  p.unit = v.name;
                  d.published = false;
                })),
        numeric('product-price', t('포장당 판매가 (KRW)', 'Price per pack (KRW)'),
            p.price, (v) {
          p.price = v;
          d.published = false;
        }, min: 0, max: 100000000),
        metric(t('내용량 1단위당 가격', 'Price per content unit'),
            '${money(p.price / p.content)} / ${ChefUnit.parse(p.unit).displayLabel(en)}'),
        note('구매 규격을 명확히 적으면 업체 비교가 쉬워집니다. 이 상품 수정은 연습용 공개 검토에만 반영됩니다.',
            'Clear pack sizes help buyers compare. These edits apply only to the sample publication review.')
      ]
    ];
    return wrapped
        ? [
            panel(
                t(
                    pack ? '규격과 가격 편집' : '상품과 이미지 등록',
                    pack
                        ? 'Edit packs and prices'
                        : 'Register a product with an image'),
                widgets)
          ]
        : widgets;
  }
}
