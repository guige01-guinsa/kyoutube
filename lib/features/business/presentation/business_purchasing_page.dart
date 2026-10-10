part of 'business_pages.dart';

class _BusinessPurchasingPage extends ConsumerStatefulWidget {
  const _BusinessPurchasingPage(
      {super.key, required this.business, required this.initialStatus});
  final BusinessContext business;
  final String initialStatus;
  @override
  ConsumerState<_BusinessPurchasingPage> createState() =>
      _BusinessPurchasingPageState();
}

class _BusinessPurchasingPageState
    extends ConsumerState<_BusinessPurchasingPage> {
  int _offset = 0;
  String _search = '';
  late String _status = widget.initialStatus;
  late ShoppingStage _stage = businessShoppingStage(widget.initialStatus);
  @override
  Widget build(BuildContext context) {
    final b = widget.business;
    final base = '/business-workspaces/${b.id}';
    if (!b.can('purchasing.read')) {
      return Scaffold(
          appBar: AppBar(),
          body: Text(businessError(context, StateError('BUSINESS_DENIED'))));
    }
    final query = (workspace: b.id, kind: 'purchase', offset: _offset);
    ref.listen(businessRecordsProvider(query), (_, next) {
      if (next.hasValue) ref.invalidate(purchaseCleanupIndexProvider(b.id));
    });
    final records = ref.watch(businessRecordsProvider(query));
    final archives = ref.watch(purchaseCleanupIndexProvider(b.id)).valueOrNull;
    return Scaffold(
      appBar: AppBar(title: Text(bt(context, '장보기', 'Shopping')), actions: [
        PurchaseCleanupMenu(workspace: b.id),
        IconButton(
            tooltip: bt(context, '새로고침', 'Refresh'),
            onPressed: () {
              ref.invalidate(businessContextProvider(b.id));
              ref.invalidate(businessRecordsProvider);
            },
            icon: const Icon(Icons.refresh)),
      ]),
      body: Center(
          child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: ScoutStyle.workspaceWidth),
        child: ListView(padding: const EdgeInsets.all(20), children: [
          if (b.isTest) const BusinessPracticeNotice(),
          ShoppingStageTabs(
              stage: _stage,
              onChanged: (value) => setState(() {
                    _stage = value;
                    _status = 'all';
                    _offset = 0;
                  })),
          const SizedBox(height: 12),
          if (_stage == ShoppingStage.prepare)
            ScoutPageHeading(
                title: bt(
                    context, '필요한 재료부터 입고까지', 'From ingredients to receiving'),
                subtitle: bt(
                    context,
                    '${b.name} · 재료·수량 정리 → 요청서 검토·승인 → 전달·입고 확인',
                    '${b.name} · Plan quantities → review requests → share and receive'),
                icon: Icons.shopping_basket_outlined),
          const SizedBox(height: 16),
          if (_stage == ShoppingStage.prepare && b.can('purchasing.write')) ...[
            Wrap(spacing: 8, runSpacing: 8, children: [
              if (b.can('recipes.read'))
                FilledButton.icon(
                    key: const Key('business-purchase-start'),
                    onPressed: () => context.push('$base/menu-fast'),
                    icon: const Icon(Icons.playlist_add_check),
                    label: Text(bt(context, '메뉴로 구매 목록 만들기',
                        'Plan purchases from menus'))),
              if (b.can('recipes.read'))
                TextButton.icon(
                    onPressed: () => context.push('$base/menu-purchase'),
                    icon: const Icon(Icons.science_outlined),
                    label: Text(bt(context, '시험 조리용', 'For trial cooking'))),
              OutlinedButton.icon(
                  key: const Key('business-purchase-manual'),
                  onPressed: () => context.push('$base/new/purchase'),
                  icon: const Icon(Icons.edit_note),
                  label: Text(bt(context, '직접 구매요청 작성', 'Write a request'))),
            ]),
            const SizedBox(height: 8),
            Text(bt(
                context,
                '판매 메뉴와 인분을 고르면 재료를 취합하고, 재고와 포장을 확인해 업체별 초안을 만듭니다.',
                'Choose selling menus and servings, review stock and pack sizes, then prepare supplier drafts.')),
          ],
          const SizedBox(height: 12),
          Wrap(spacing: 8, runSpacing: 8, children: [
            OutlinedButton.icon(
                onPressed: () => context.push('$base/suppliers'),
                icon: const Icon(Icons.storefront_outlined),
                label: Text(
                    bt(context, '업소 거래처·상품', 'Business suppliers & products'))),
            OutlinedButton.icon(
                onPressed: () => context.push('$base/inventory'),
                icon: const Icon(Icons.inventory_2_outlined),
                label: Text(
                    bt(context, '재고·조리 예약', 'Stock & cooking reservations'))),
            if (b.can('recipes.read'))
              OutlinedButton.icon(
                  onPressed: () => context.push('$base/meals'),
                  icon: const Icon(Icons.calendar_month_outlined),
                  label: Text(bt(context, '식단 달력', 'Meal calendar'))),
          ]),
          const SizedBox(height: 24),
          ScoutSectionLabel(
              title: switch (_stage) {
            ShoppingStage.prepare => bt(context, '작성 중인 목록', 'Draft lists'),
            ShoppingStage.active =>
              bt(context, '승인·전달·입고 확인', 'Approval, sharing & receipt'),
            ShoppingStage.records =>
              bt(context, '완료·취소 내역', 'Completed & cancelled'),
          }),
          TextField(
              key: const ValueKey('business-search-purchase'),
              decoration: InputDecoration(
                  prefixIcon: const Icon(Icons.search),
                  labelText: bt(context, '업체·재료·요청서 검색',
                      'Search supplier, ingredient or request')),
              onChanged: (v) => setState(() => _search = v)),
          const SizedBox(height: 8),
          Text(
              bt(context, '검색·단계별 건수는 현재 불러온 50개 이내의 요청서 기준입니다.',
                  'Search and status counts apply to this page of up to 50 requests.'),
              style: Theme.of(context).textTheme.bodySmall),
          const SizedBox(height: 8),
          records.when(
              loading: () => const LinearProgressIndicator(),
              error: (e, _) => _BusinessError(
                  e, () => ref.invalidate(businessRecordsProvider(query))),
              data: (allRows) {
                final rows = allRows
                    .where((r) => !(archives?.hidesRequest(
                            'business_purchase', r.id, r.status) ??
                        false))
                    .toList();
                final filtered = rows
                    .where((r) =>
                        businessShoppingStage(r.status) == _stage &&
                        (_status == 'all' || r.status == _status) &&
                        businessPurchaseMatches(r, _search))
                    .toList();
                return Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Wrap(spacing: 6, runSpacing: 6, children: [
                        for (final s in [
                          'all',
                          'draft',
                          'review',
                          'approved',
                          'sent',
                          'received',
                          'cancelled'
                        ].where((s) =>
                            s == 'all' || businessShoppingStage(s) == _stage))
                          ChoiceChip(
                              key: ValueKey('business-purchase-status-$s'),
                              label: LocalizedText(
                                  '${s == 'all' ? bt(context, '전체', 'All') : businessStatusLabel(context, s)} ${rows.where((r) => businessShoppingStage(r.status) == _stage && (s == 'all' || r.status == s)).length}'),
                              selected: _status == s,
                              onSelected: (_) => setState(() => _status = s)),
                      ]),
                      const SizedBox(height: 12),
                      if (filtered.isEmpty)
                        Padding(
                            padding: const EdgeInsets.all(16),
                            child: Text(bt(
                                context,
                                rows.isEmpty
                                    ? '아직 구매요청이 없습니다. 위에서 구매 목록을 만들어 시작하세요.'
                                    : '조건에 맞는 요청서가 없습니다. 검색어나 단계를 바꿔 보세요.',
                                rows.isEmpty
                                    ? 'No requests yet. Start by planning your purchase list above.'
                                    : 'No matching requests. Change the search or status.'))),
                      Column(
                          key: const Key('business-record-cards'),
                          children: [
                            for (final r in filtered) _requestCard(r, base),
                          ]),
                      Wrap(
                          spacing: 12,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: [
                            if (_offset > 0)
                              TextButton(
                                  onPressed: () =>
                                      setState(() => _offset -= 50),
                                  child: Text(
                                      bt(context, '이전 50개', 'Previous 50'))),
                            LocalizedText(
                                '${allRows.isEmpty ? 0 : _offset + 1}–${_offset + allRows.length}'),
                            if (allRows.length == 50)
                              TextButton(
                                  onPressed: () =>
                                      setState(() => _offset += 50),
                                  child:
                                      Text(bt(context, '다음 50개', 'Next 50'))),
                          ]),
                    ]);
              }),
        ]),
      )),
    );
  }

  Widget _requestCard(BusinessRecord r, String base) {
    final b = widget.business;
    final lines =
        (r.data['lines'] as List? ?? const []).whereType<Map>().toList();
    final supplier = (r.data['supplier'] as String? ?? '').trim();
    final delivery = (r.data['delivery_date'] as String? ?? '').trim();
    final editable = r.status == 'draft' && b.can('purchasing.write');
    final receiving = r.status == 'sent' && b.can('purchasing.write');
    final action = editable
        ? bt(context, '이어서 작성', 'Continue draft')
        : receiving
            ? bt(context, '입고 확인', 'Check receipt')
            : r.status == 'review' && b.can('purchases.approve')
                ? bt(context, '승인 내용 검토', 'Review for approval')
                : r.status == 'approved' && b.can('purchasing.write')
                    ? bt(context, '전달 준비', 'Prepare to share')
                    : bt(context, '요청서 확인', 'View request');
    final path = editable
        ? '$base/edit/${r.id}'
        : receiving
            ? '$base/receiving/${r.id}'
            : '$base/records/${r.id}';
    return Card(
        key: ValueKey('business-purchase-${r.id}'),
        child: InkWell(
            onTap: () => context.push('$base/records/${r.id}'),
            borderRadius: BorderRadius.circular(16),
            child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(r.title,
                        style: Theme.of(context).textTheme.titleMedium),
                    const SizedBox(height: 6),
                    LocalizedText(
                        '${businessStatusLabel(context, r.status)} · ${supplier.isEmpty ? bt(context, '구매처 미지정', 'Supplier not set') : supplier}'),
                    Text(bt(
                        context,
                        '재료 ${lines.length}개 · 납품 ${delivery.isEmpty ? '미정' : delivery}',
                        '${lines.length} items · Delivery ${delivery.isEmpty ? 'not set' : delivery}')),
                    if (lines.isNotEmpty)
                      Text(
                          lines.take(3).map((l) => l['name'] ?? '').join(' · '),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis),
                    if (r.status == 'sent')
                      Text(bt(context, '부분 입고가 있으면 남은 수량을 확인하세요.',
                          'For partial receipts, check the remaining quantity.')),
                    const SizedBox(height: 8),
                    Wrap(spacing: 8, runSpacing: 8, children: [
                      FilledButton.tonal(
                          onPressed: () => context.push(path),
                          child: Text(action)),
                      BusinessCoupangEntry(business: b, request: r),
                      if (editable || receiving)
                        TextButton(
                            onPressed: () =>
                                context.push('$base/records/${r.id}'),
                            child: Text(bt(context, '상세 보기', 'Details'))),
                    ]),
                  ],
                ))));
  }
}
