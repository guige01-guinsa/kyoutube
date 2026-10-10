import '../../../core/localization/localized_text.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../../core/localization/app_localizations.dart';
import '../../../core/theme/app_theme.dart';
import '../../suppliers/domain/procurement_plan.dart';
import '../domain/guide_curriculum.dart';
import '../domain/guide_purchase_example.dart';
import '../domain/guide_example.dart';

class GuideTrainingCard extends StatefulWidget {
  const GuideTrainingCard(
      {super.key,
      required this.lesson,
      required this.purchase,
      required this.onPracticed});
  final GuideLesson lesson;
  final GuidePurchaseExample purchase;
  final VoidCallback onPracticed;
  @override
  State<GuideTrainingCard> createState() => _GuideTrainingCardState();
}

class _GuideTrainingCardState extends State<GuideTrainingCard> {
  final _input = TextEditingController();
  bool _confirmed = false, _result = false;
  String _filter = 'all', _status = 'draft', _photo = '';
  int _number = 1;
  String? _error;
  String t(String ko, String en) =>
      AppLocalizations.of(context).bilingual(ko, en);
  String name(String id) => switch (id) {
        'carrot' => t('당근', 'Carrot'),
        'onion' => t('양파', 'Onion'),
        _ => t('두부', 'Tofu')
      };
  String money(num n) => 'KRW ${NumberFormat('#,##0', 'en').format(n)}';
  @override
  void dispose() {
    _input.dispose();
    super.dispose();
  }

  void practiced([VoidCallback? action]) {
    setState(() {
      action?.call();
      _result = true;
      _error = null;
    });
    widget.onPracticed();
  }

  Widget result(String text) => Container(
      margin: const EdgeInsets.only(top: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
          color: Colors.white, borderRadius: BorderRadius.circular(16)),
      child: Text(text,
          key: const Key('guide-training-result'),
          style: Theme.of(context).textTheme.titleMedium));
  Widget button(String ko, String en, VoidCallback action) => Padding(
      padding: const EdgeInsets.only(top: 12),
      child: FilledButton(onPressed: action, child: Text(t(ko, en))));
  Widget chips(List<int> values, String suffix) =>
      Wrap(spacing: 8, runSpacing: 8, children: [
        for (final n in values)
          ChoiceChip(
              label: LocalizedText('$n $suffix'),
              selected: _number == n,
              onSelected: (_) => practiced(() => _number = n))
      ]);
  @override
  Widget build(BuildContext context) => Material(
      key: const Key('guide-training'),
      color: ScoutStyle.mint,
      borderRadius: BorderRadius.circular(22),
      clipBehavior: Clip.antiAlias,
      child: Padding(
          padding: const EdgeInsets.all(20),
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Text(t('연습 전용 · 가상 자료', 'Practice only · sample data'),
                style: Theme.of(context).textTheme.labelLarge),
            const SizedBox(height: 8),
            Text(t('아래에서 직접 바꿔 보세요. 실제 저장·공개·발송·AI 호출은 실행되지 않습니다.',
                'Try the controls below. No real saving, publishing, sharing or AI calls take place.')),
            const SizedBox(height: 20),
            ..._exercise(),
            if (_error != null)
              Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: Text(_error!,
                      style: TextStyle(
                          color: Theme.of(context).colorScheme.error))),
            if (_result)
              Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: Text(t('체험했습니다. 아래에서 실습을 완료하거나 다시 바꿔볼 수 있어요.',
                      'Example tried. Complete the lesson below or keep experimenting.'))),
          ])));
  List<Widget> _exercise() {
    final id = widget.lesson.id, p = widget.purchase;
    if (id == 'buy-quantity' || id == 'home-shopping') {
      return [
        Text(t('조리 원문: 당근 200g · 구매 포장: 1kg',
            'Recipe: 200 g carrot · Purchase pack: 1 kg')),
        for (final item in p.quantities.keys)
          Card(
              child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        CheckboxListTile(
                            contentPadding: EdgeInsets.zero,
                            title: Text(name(item)),
                            value: p.selected.contains(item),
                            onChanged: (v) => setState(() {
                                  v!
                                      ? p.selected.add(item)
                                      : p.selected.remove(item);
                                  _result = false;
                                })),
                        Wrap(spacing: 8, runSpacing: 8, children: [
                          for (final n in [1, 2, 3])
                            ChoiceChip(
                                label: LocalizedText('$n kg'),
                                selected: p.quantities[item] == n,
                                onSelected: (_) => setState(() {
                                      p.quantity(item, n.toDouble());
                                      _result = false;
                                    }))
                        ]),
                      ]))),
        button('구매량 확인', 'Confirm purchase quantities', () {
          if (p.selected.isEmpty) {
            setState(() => _error =
                t('재료를 한 개 이상 선택하세요.', 'Choose at least one ingredient.'));
            return;
          }
          practiced();
        }),
        if (_result)
          result(
              '${t('연습 구매 목록', 'Practice purchase list')}\n${p.selected.map((i) => '${name(i)} ${p.quantities[i]!.toInt()} kg').join('\n')}\n${t('조리 원문 200g은 그대로입니다.', 'The original recipe remains 200 g.')}'),
      ];
    }
    if (id == 'buy-suppliers') {
      return [
        Text(t('가상 업체를 내 거래처로 골라 보세요.',
            'Choose a sample business for your suppliers.')),
        for (final s in ['A', 'B', 'C'])
          CheckboxListTile(
              title: LocalizedText('${t('연습 업체', 'Sample supplier')} $s'),
              subtitle: Text(p.favorites.contains(s)
                  ? t('내 거래처 · 우선 표시', 'My supplier · shown first')
                  : t('공개 업체 예시', 'Public listing example')),
              value: p.favorites.contains(s),
              onChanged: (v) => practiced(() {
                    v! ? p.favorites.add(s) : p.favorites.remove(s);
                  })),
        if (_result)
          result('${t('내 거래처', 'My suppliers')}: ${p.favorites.join(', ')}'),
      ];
    }
    if (id == 'buy-candidates') {
      return [
        Text(t('각 재료의 후보를 1~3곳으로 바꿔 보세요. 네 번째 업체를 고르면 안내합니다.',
            'Adjust candidates to 1–3 suppliers per ingredient. A fourth selection shows a limit message.')),
        for (final item in p.quantities.keys)
          Card(
              child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        LocalizedText('${name(item)} · ${p.candidates[item]!.length}/3',
                            style: Theme.of(context).textTheme.titleMedium),
                        for (final s in p.available(item))
                          CheckboxListTile(
                              key: Key('guide-candidate-$item-$s'),
                              title:
                                  LocalizedText('${t('연습 업체', 'Sample supplier')} $s'),
                              value: p.candidates[item]!.contains(s),
                              onChanged: (v) {
                                final ok = p.toggleCandidate(item, s, v!);
                                setState(() => _error = ok
                                    ? null
                                    : t('재료마다 최대 3곳입니다. 먼저 다른 후보를 해제하세요.',
                                        'Up to three per ingredient. Deselect another candidate first.'));
                              }),
                      ]))),
        button('이 후보로 연습', 'Use these candidates', () {
          if (p.quantities.keys.any((i) => p.candidates[i]!.isEmpty)) {
            setState(() => _error = t('각 재료에 후보를 한 곳 이상 선택하세요.',
                'Choose at least one candidate for each ingredient.'));
            return;
          }
          practiced();
        }),
        if (_result)
          result(t('재료별 후보 선택을 확인했습니다.', 'Candidate selections are ready.')),
      ];
    }
    if (id == 'buy-compare') {
      final plan = p.compare();
      return [
        Text(t('가상 가격 · 1kg 포장 · 세금 포함 · 업체별 배송비 포함',
            'Sample prices · 1 kg packs · tax included · shipping per supplier included')),
        for (final c in ProcurementPriority.values)
          ListTile(
              leading: Icon(p.priority == c
                  ? Icons.radio_button_checked
                  : Icons.radio_button_unchecked),
              selected: p.priority == c,
              title: Text(switch (c) {
                ProcurementPriority.fewestSuppliers =>
                  t('최소 거래처 수', 'Fewest suppliers'),
                ProcurementPriority.lowestPrice =>
                  t('최저 구매가격', 'Lowest purchase price'),
                ProcurementPriority.highestRating =>
                  t('평점 우선', 'Highest rating first')
              }),
              onTap: () => practiced(() => p.priority = c)),
        if (plan == null)
          result(t('선택 재료와 재료별 후보가 필요합니다. 예제 초기화로 기본값을 불러올 수 있어요.',
              'Select ingredients and candidates. Restart the example to restore the defaults.'))
        else
          result(
              '${t('요청서', 'Requests')}: ${plan.supplierIds.length}\n${t('비교 예상액', 'Estimated total')}: ${money(plan.total!)}\n${plan.purchases.map((r) => '${name(r.line.id)} → ${r.candidate.offer.supplier.id} · ${r.packs} ${t('팩', 'pack(s)')}').join('\n')}'),
        Text(t(
            '연습 A는 한 업체로 묶기, B·C는 낮은 가격, D는 높은 평점을 비교하는 예시입니다. 후보를 바꾸면 결과도 달라집니다.',
            'A illustrates grouping, B/C lower prices, and D higher ratings. Changing candidates can change the result.')),
      ];
    }
    if (id == 'buy-request') {
      final plan = p.compare();
      return [
        TextField(
            controller: _input,
            maxLength: 80,
            decoration: InputDecoration(
                labelText: t('연습 요청자 이름', 'Practice buyer name')),
            onChanged: (_) => setState(() => _result = false)),
        CheckboxListTile(
            title: Text(t('수량·거래처·희망 납품일 확인',
                'Confirm quantities, supplier and desired delivery date')),
            value: _confirmed,
            onChanged: (v) => setState(() => _confirmed = v!)),
        button('연습 미리보기', 'Preview example', () {
          if (plan == null) {
            setState(() => _error = t('구매량과 재료별 업체 후보를 먼저 확인하세요.',
                'Check purchase quantities and supplier candidates first.'));
            return;
          }
          if (_input.text.trim().isEmpty || !_confirmed) {
            setState(() => _error = t('연습 이름을 입력하고 검토 항목을 확인하세요.',
                'Enter a practice name and confirm the review.'));
            return;
          }
          practiced();
        }),
        if (_result && plan != null) ...[
          result([
            t('연습 구매요청서 · 저장/발송되지 않음', 'Sample request · not saved or sent'),
            _input.text.trim()
          ].join(String.fromCharCode(10))),
          for (final supplier in plan.supplierIds)
            result([
              '${t('연습 업체', 'Sample supplier')} $supplier',
              ...plan.purchases
                  .where((r) => r.candidate.offer.supplier.id == supplier)
                  .map((r) =>
                      '${name(r.line.id)} · ${r.packs} ${t('팩', 'pack(s)')} × 1 kg')
            ].join(String.fromCharCode(10))),
          Text(t('등록번호·등록증은 실제 화면에서 별도로 연결합니다.',
              'Registration numbers and certificates are linked separately in the real form.')),
        ],
        Text(t('이 연습은 문서 구성 확인입니다. 실제 PDF 미리보기·파일 저장·인쇄는 내 자료로 시작에서 이용하세요.',
            'This example previews the document structure. Use your own data for real PDF preview, export and printing.')),
      ];
    }
    if (id == 'buy-ledger') {
      return [
        Text(t('공유창을 열어도 상태는 준비 중입니다. 실제 확인에 해당하는 연습 상태를 선택하세요.',
            'Opening sharing leaves the status as Preparing. Choose a practice status after confirmation.')),
        Wrap(spacing: 8, runSpacing: 8, children: [
          for (final s in ['draft', 'sent', 'received'])
            ChoiceChip(
                label: Text(switch (s) {
                  'draft' => t('준비 중', 'Preparing'),
                  'sent' => t('전달 확인', 'Sent confirmed'),
                  _ => t('입고 확인', 'Receipt confirmed')
                }),
                selected: _status == s,
                onSelected: (_) => practiced(() => _status = s))
        ]),
        result('${t('연습 대장 상태', 'Practice ledger status')}: ${switch (_status) {
          'draft' => t('준비 중', 'Preparing'),
          'sent' => t('진행 중', 'In progress'),
          _ => t('완료', 'Completed')
        }}'),
        button('지난 요청으로 새 초안 연습', 'Practice copying a past request',
            () => practiced(() => _status = 'draft')),
      ];
    }
    if (id == 'supplier-product') {
      return [
        Text(t('예제 상품: 당근 · 농산물 / 채소',
            'Sample product: carrot · Produce / Vegetables')),
        Wrap(spacing: 12, runSpacing: 12, children: [
          for (final value in ['carrot', 'onion'])
            OutlinedButton.icon(
                onPressed: () => practiced(() => _photo = value),
                icon: Icon(value == 'carrot'
                    ? Icons.eco_outlined
                    : Icons.spa_outlined),
                label:
                    LocalizedText('${name(value)} · ${t('가상 사진 선택', 'sample image')}'))
        ]),
        if (_photo.isNotEmpty)
          result(
              '${name(_photo)} · ${t('예제 이미지 선택됨 · 업로드 없음', 'sample image selected · no upload')}'),
      ];
    }
    if (id == 'supplier-pack') {
      return [
        Text(t('판매 단위: 상자 · 한 상자 가격: KRW 10,000',
            'Selling unit: box · Price per box: KRW 10,000')),
        chips([1, 2, 5], t('kg / 상자', 'kg / box')),
        result(
            '${t('1상자 내용량', 'Contents per box')}: $_number kg\n${t('비교용 kg당 금액', 'Price per kg for comparison')}: ${money(10000 / _number)}'),
      ];
    }
    if (id == 'supplier-publish') {
      return [
        CheckboxListTile(
            title: Text(t('연습 업체 정보·상품 사진·규격 확인',
                'Review sample profile, product photo and pack size')),
            value: _confirmed,
            onChanged: (v) => setState(() => _confirmed = v!)),
        button('공개 과정 연습', 'Practice publication', () {
          if (!_confirmed) {
            setState(() => _error =
                t('공개할 내용을 먼저 확인하세요.', 'Review the public information first.'));
            return;
          }
          practiced();
        }),
        if (_result)
          result(t('연습 결과: 로그인한 무료·유료 회원에게 표시됩니다. 실제 업체는 공개되지 않았습니다.',
              'Example result: visible to signed-in free and paid members. No real listing was published.')),
      ];
    }
    if (id == 'supplier-update') {
      return [
        SwitchListTile(
            title: Text(t('연습 상품 판매 중', 'Sample product active')),
            value: _confirmed,
            onChanged: (v) => practiced(() => _confirmed = v)),
        result(_confirmed
            ? t('연습 목록에 표시 · 과거 요청서는 변경하지 않음',
                'Shown in sample list · historical requests stay unchanged')
            : t('연습 목록에서 숨김 · 과거 요청서는 유지',
                'Hidden from sample list · historical requests retained')),
      ];
    }
    if (id == 'pro-sales') {
      return [
        Text(t('연습 판매가 KRW 4,500 · 기록 원가 KRW 3,000 / 1인분',
            'Sample selling price KRW 4,500 · recorded cost KRW 3,000 per serving')),
        chips([1, 10, 20], t('개 판매', 'sold')),
        result(
            '${t('매출', 'Revenue')}: ${money(4500 * _number)}\n${t('기록 원가 차감 후 차액', 'Difference after recorded cost')}: ${money(1500 * _number)}'),
        Text(t('미입력 비용을 제외하지 않은 차액이며 회계 순이익이 아닙니다.',
            'This difference excludes no unentered costs and is not accounting net profit.')),
      ];
    }
    if (id == 'pro-cost') {
      return [
        Text(t('연습 손질 후 800g · 수율 80% → 원가 기준 구매량 1kg',
            'Sample edible 800 g · yield 80% → cost basis 1 kg purchased')),
        chips([1, 2, 3], t('× 포장 가격 KRW 12,000', '× pack price KRW 12,000')),
        result(
            '${t('연습 재료비', 'Sample ingredient cost')}: ${money(12000 * _number)}\n${t('4인분 기준 1인분 원가', 'Cost per serving for four')}: ${money(GuideExample().recipe.portionCost! * _number)}'),
      ];
    }
    if (id == 'pro-versions') {
      return [
        Wrap(spacing: 8, runSpacing: 8, children: [
          for (final s in ['A', 'B'])
            ChoiceChip(
                label: LocalizedText('${t('연습 버전', 'Practice version')} $s'),
                selected: _filter == s,
                onSelected: (_) => practiced(() => _filter = s))
        ]),
        result(_filter == 'B'
            ? t('B: 닭고기 900g · 변경 이유: 양 보강\nA 대비 +100g · 선택해도 실제 레시피는 바뀌지 않음',
                'B: chicken 900 g · reason: larger portion\n+100 g versus A · selecting does not change a real recipe')
            : t('A: 닭고기 800g · 기준 레시피\nB를 선택해 차이를 확인하세요.',
                'A: chicken 800 g · baseline recipe\nChoose B to compare.')),
      ];
    }
    if (id == 'home-search') {
      return [
        Wrap(spacing: 8, runSpacing: 8, children: [
          for (final value in ['all', 'rice'])
            ChoiceChip(
                label: Text(value == 'all'
                    ? t('전체', 'All')
                    : t('밥·면', 'Rice & noodles')),
                selected: _filter == value,
                onSelected: (_) => practiced(() => _filter = value))
        ]),
        result(_filter == 'rice'
            ? t('연습 결과: 비빔밥 · 볶음밥', 'Sample results: bibimbap · fried rice')
            : t('연습 결과: 비빔밥 · 볶음밥 · 된장찌개',
                'Sample results: bibimbap · fried rice · doenjang stew')),
      ];
    }
    if (id == 'home-draft' || id == 'pro-ai') {
      return [
        Text(t('가상 원본: 밥 120g. 가상 AI 초안: 밥 수량 확인 필요. 원본을 확인한 결과를 선택하세요.',
            'Sample source: rice 120 g. Sample AI draft: rice quantity needs review. Choose the source-verified action.')),
        button('원본 근거대로 120g 입력', 'Use the source quantity: 120 g',
            () => practiced()),
        if (_result)
          result(t('연습 초안: 밥 120g · 원본 근거 확인됨\nAI 호출 없이 예제만 수정했습니다.',
              'Sample draft: rice 120 g · source reviewed\nOnly the example changed; no AI was called.')),
      ];
    }
    return [
      Text(id == 'supplier-profile'
          ? t('가상 업체명 입력 · 나머지 필수 항목은 안내의 실제 화면 단계에서 확인합니다.',
              'Enter a sample business name. Review other required fields in the real-screen steps.')
          : t('연습 메뉴의 이름이나 다음에 참고할 메모를 입력하세요.',
              'Enter a sample recipe name or a note for next time.')),
      TextField(
          controller: _input,
          maxLength: 80,
          decoration: InputDecoration(
              labelText: id == 'supplier-profile'
                  ? t('연습 업체명', 'Sample business name')
                  : t('연습 제목·메모', 'Practice title or note')),
          onChanged: (_) => setState(() => _result = false)),
      button('예제에 적용', 'Apply to the example', () {
        if (_input.text.trim().isEmpty) {
          setState(() => _error = t('연습 내용을 입력하세요.', 'Enter a sample value.'));
          return;
        }
        practiced();
      }),
      if (_result)
        result(
            '${t('연습 결과', 'Example result')}: ${_input.text.trim()}\n${t('실제 계정 자료에는 저장되지 않았습니다.', 'Nothing was saved to your account.')}'),
    ];
  }
}
