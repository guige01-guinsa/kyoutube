part of 'business_pages.dart';

class BusinessRecordPage extends ConsumerStatefulWidget {
  const BusinessRecordPage(
      {super.key, required this.workspace, required this.recordId});
  final String workspace, recordId;
  @override
  ConsumerState<BusinessRecordPage> createState() => _BusinessRecordPageState();
}

class _BusinessRecordPageState extends ConsumerState<BusinessRecordPage> {
  bool _busy = false;
  String? _error;
  String? _handoverId;
  Future<void> _action(Future<void> Function(BusinessRepository) action) async {
    if (_busy) return;
    final owner = ref.read(activeAccountIdProvider);
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await action(ref.read(businessRepositoryProvider));
      if (!mounted || owner != ref.read(activeAccountIdProvider)) return;
      ref.invalidate(businessRecordProvider(
          (workspace: widget.workspace, id: widget.recordId)));
      ref.invalidate(businessRecordsProvider);
    } catch (e) {
      if (context.mounted &&
          mounted &&
          owner == ref.read(activeAccountIdProvider)) {
        setState(() => _error = businessError(context, e));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _transition(BusinessRecord r, String status) async {
    final message = switch (status) {
      'sent' => bt(
          context,
          '업체에 실제로 요청서를 전달했나요? 파일 생성이나 공유창 열기만으로는 전달 완료가 아닙니다.',
          'Have you actually shared the request with the supplier? Generating a file or opening a share sheet does not confirm delivery.'),
      'approved' => bt(context, '품목·구매량·단가·납품 조건을 확인하고 승인할까요?',
          'Approve after checking items, quantities, prices and delivery terms?'),
      'draft' => bt(context, '작성 중으로 되돌릴까요? 수정 후에는 다시 승인을 진행합니다.',
          'Return to draft? Changes will require approval again.'),
      'cancelled' => bt(
          context,
          '이 구매요청을 취소로 기록할까요? 업체와 별도로 확인해 주세요. 이미 입고한 재고는 유지되며 실제 반품은 따로 기록합니다.',
          'Record this request as cancelled? Confirm with the supplier separately. Received stock is retained; record actual returns separately.'),
      _ => bt(context, '확정한 구매량과 조건으로 승인을 요청할까요?',
          'Submit the confirmed quantities and terms for approval?')
    };
    if (!await businessConfirm(context, message) || !mounted) return;
    await _action((repo) async {
      await repo.transition(r, status);
    });
  }

  Future<void> _pdf(BusinessRecord r) async {
    final owner = ref.read(activeAccountIdProvider),
        repo = ref.read(businessRepositoryProvider);
    final english = Localizations.localeOf(context).languageCode != 'ko';
    Future<void> access() async {
      if (!mounted || owner != ref.read(activeAccountIdProvider)) {
        throw StateError('BUSINESS_AUTH');
      }
      await repo.document(r);
      if (!mounted || owner != ref.read(activeAccountIdProvider)) {
        throw StateError('BUSINESS_AUTH');
      }
    }

    await showDialog<void>(
        context: context,
        builder: (ctx) => ProviderScope(
                overrides: [
                  requestDocumentAccessProvider.overrideWithValue(access)
                ],
                child: PurchasePdfPreview(
                    title: bt(ctx, '공동 구매요청서 PDF', 'Team purchase request PDF'),
                    filename: 'PO-${r.id}',
                    controls: Padding(
                        padding: const EdgeInsets.all(12),
                        child: LocalizedText(
                            '${businessStatusLabel(ctx, r.status)} · ${bt(ctx, '문서 출력은 전달 상태를 바꾸지 않습니다.', 'Exporting does not change the sharing status.')}')),
                    buildDocument: () async {
                      await access();
                      final latest = await repo.document(r);
                      final font = await rootBundle
                          .load('assets/fonts/NanumGothic-Regular.ttf');
                      if (!mounted ||
                          owner != ref.read(activeAccountIdProvider)) {
                        throw StateError('BUSINESS_AUTH');
                      }
                      final bytes = await supplierRequestPdf(
                          latest.asPurchase(english: english), font,
                          english: english, practice: latest.isTest);
                      await access();
                      return bytes;
                    })));
  }

  Future<void> _history(BusinessRecord r) async {
    await showDialog<void>(
        context: context,
        builder: (ctx) => ShoppingAccountGuard(
                child: AlertDialog(
                    title: Text(bt(ctx, '최근 변경 이력', 'Recent changes')),
                    content: SizedBox(
                        width: 650,
                        height: 500,
                        child: FutureBuilder(
                            future: ref
                                .read(businessRepositoryProvider)
                                .versions(r.workspace, r.id),
                            builder: (ctx, snapshot) {
                              if (snapshot.hasError) {
                                return Text(
                                    businessError(ctx, snapshot.error!));
                              }
                              if (!snapshot.hasData) {
                                return const Center(
                                    child: CircularProgressIndicator());
                              }
                              return ListView(children: [
                                for (final v in snapshot.data!)
                                  ExpansionTile(
                                      title: LocalizedText(
                                          'v${v['revision']} · ${v['title']}'),
                                      subtitle: LocalizedText(
                                          '${businessStatusLabel(ctx, v['status'] as String)} · ${v['created_at']} · ${v['actor_name']}'),
                                      children: [
                                        if (r.kind == 'recipe' &&
                                            v['revision'] != r.revision)
                                          BusinessRecipeComparison(
                                              current: r, old: v),
                                        Padding(
                                            padding: const EdgeInsets.all(12),
                                            child: _BusinessRecordContents(
                                                record: BusinessRecord(
                                                    id: r.id,
                                                    workspace: r.workspace,
                                                    kind: r.kind,
                                                    title: v['title'] as String,
                                                    data: Map<String,
                                                            dynamic>.from(
                                                        v['data'] as Map),
                                                    status:
                                                        v['status'] as String,
                                                    revision:
                                                        (v['revision'] as num)
                                                            .toInt())))
                                      ])
                              ]);
                            })),
                    actions: [
                  TextButton(
                      onPressed: () => Navigator.pop(ctx),
                      child: Text(bt(ctx, '닫기', 'Close')))
                ])));
  }

  @override
  Widget build(BuildContext context) {
    final q = (workspace: widget.workspace, id: widget.recordId);
    return ref.watch(businessContextProvider(widget.workspace)).when(
        data: (business) => ref.watch(businessRecordProvider(q)).when(
            data: (r) => !business.can(businessPermission(r.kind))
                ? Scaffold(
                    appBar: AppBar(),
                    body: _BusinessError(
                        StateError('BUSINESS_DENIED'),
                        () => ref.invalidate(
                            businessContextProvider(widget.workspace))))
                : Scaffold(
                    appBar: AppBar(
                        title: Text(businessKindLabel(context, r.kind)),
                        actions: [
                          IconButton(
                              tooltip: bt(context, '최신 자료 다시 열기',
                                  'Reload latest record'),
                              onPressed: _busy
                                  ? null
                                  : () {
                                      ref.invalidate(businessContextProvider(
                                          widget.workspace));
                                      ref.invalidate(businessRecordProvider(q));
                                    },
                              icon: const Icon(Icons.refresh))
                        ]),
                    body: Center(
                        child: ConstrainedBox(
                            constraints: const BoxConstraints(maxWidth: 1000),
                            child: ListView(
                                padding: const EdgeInsets.all(20),
                                children: [
                                  if (business.isTest)
                                    const BusinessPracticeNotice(),
                                  _BusinessWorkHeader(
                                      workspace:
                                          '${business.name} · v${r.revision}',
                                      title: r.title,
                                      subtitle:
                                          businessKindLabel(context, r.kind),
                                      icon: r.kind == 'purchase'
                                          ? Icons.receipt_long_outlined
                                          : Icons.description_outlined),
                                  const SizedBox(height: 10),
                                  if (r.kind == 'purchase' ||
                                      r.status == 'cancelled')
                                    Text(
                                        r.kind != 'purchase'
                                            ? bt(context, '사용 중지', 'Archived')
                                            : businessStatusLabel(
                                                context, r.status),
                                        style: Theme.of(context)
                                            .textTheme
                                            .titleLarge),
                                  const SizedBox(height: 12),
                                  if (r.kind == 'recipe')
                                    BusinessRecipeLifecycle(
                                        business: business, recipe: r),
                                  if (r.kind == 'purchase' &&
                                      r.status != 'cancelled')
                                    BusinessWorkflowSteps(
                                        current: [
                                          'draft',
                                          'review',
                                          'approved',
                                          'sent',
                                          'received'
                                        ].indexOf(r.status),
                                        labels: [
                                          for (final state in [
                                            'draft',
                                            'review',
                                            'approved',
                                            'sent',
                                            'received'
                                          ])
                                            businessStatusLabel(context, state)
                                        ]),
                                  if (r.kind == 'purchase')
                                    BusinessPurchaseBasis(record: r),
                                  if (r.kind == 'purchase')
                                    BusinessSupplierSnapshot(record: r),
                                  if (r.kind == 'purchase')
                                    Align(
                                        alignment: Alignment.centerLeft,
                                        child: BusinessCoupangEntry(
                                            business: business,
                                            request: r,
                                            enabled: !_busy,
                                            explainBlocked: true)),
                                  if (r.kind == 'purchase' &&
                                      ['sent', 'received', 'cancelled']
                                          .contains(r.status))
                                    Align(
                                        alignment: Alignment.centerLeft,
                                        child: FilledButton.icon(
                                            onPressed: _busy
                                                ? null
                                                : () => context.push(
                                                    '/business-workspaces/${r.workspace}/receiving/${r.id}'),
                                            icon: const Icon(
                                                Icons.inventory_2_outlined),
                                            label: Text(bt(context, '품목별 입고·반품',
                                                'Item receipts & returns')))),
                                  Wrap(spacing: 10, runSpacing: 8, children: [
                                    if (!_busy &&
                                        business.can(businessPermission(r.kind,
                                            write: true)) &&
                                        ((business.owner &&
                                                ['purchase', 'sale']
                                                    .contains(r.kind)) ||
                                            (r.kind == 'purchase' &&
                                                const [
                                                  'draft',
                                                  'received',
                                                  'cancelled'
                                                ].contains(r.status))))
                                      RecordManagementMenu(
                                          onError: (e) =>
                                              businessError(context, e),
                                          actions: [
                                            if (business.owner)
                                              RecordManagementAction(
                                                  'erase',
                                                  bt(context, '영구 삭제',
                                                      'Delete permanently'),
                                                  Icons.delete_forever,
                                                  () async {
                                                if (await _eraseBusinessRecord(
                                                        context,
                                                        ref,
                                                        widget.workspace,
                                                        r.kind,
                                                        r.id) &&
                                                    context.mounted) {
                                                  context.go(
                                                      '/business-workspaces/${widget.workspace}');
                                                }
                                              }),
                                            if (r.kind == 'purchase' &&
                                                const [
                                                  'draft',
                                                  'received',
                                                  'cancelled'
                                                ].contains(r.status))
                                              RecordManagementAction(
                                                  'archive',
                                                  bt(context, '보관·복원',
                                                      'Archive / restore'),
                                                  Icons.archive_outlined,
                                                  () async {
                                                if (await managePurchaseArchive(
                                                    context, ref,
                                                    workspace: widget.workspace,
                                                    kind: 'business_purchase',
                                                    id: r.id,
                                                    title: r.title)) {
                                                  ref.invalidate(
                                                      businessRecordsProvider);
                                                }
                                              }),
                                          ]),
                                    if (r.status == 'draft' &&
                                        business.can(businessPermission(r.kind,
                                            write: true)))
                                      FilledButton.icon(
                                          onPressed: _busy
                                              ? null
                                              : () => context.push(
                                                  '/business-workspaces/${widget.workspace}/edit/${r.id}'),
                                          icon: const Icon(Icons.edit_outlined),
                                          label: Text(
                                              bt(context, '수정하기', 'Edit'))),
                                    OutlinedButton.icon(
                                        onPressed:
                                            _busy ? null : () => _history(r),
                                        icon: const Icon(Icons.history),
                                        label: Text(bt(context, '버전·변경 이력',
                                            'Versions & history'))),
                                    if (r.kind != 'purchase' &&
                                        r.status == 'draft' &&
                                        business.can(businessPermission(r.kind,
                                            write: true)))
                                      OutlinedButton.icon(
                                          onPressed: _busy
                                              ? null
                                              : () async {
                                                  if (!await businessConfirm(
                                                          context,
                                                          bt(
                                                              context,
                                                              '이 자료를 사용 중지할까요? 판매 기록은 집계에서 제외되고 변경 이력은 남습니다.',
                                                              'Archive this record? Sales will be excluded from totals and history is retained.')) ||
                                                      !context.mounted) {
                                                    return;
                                                  }
                                                  await _action((repo) =>
                                                      repo.archive(r));
                                                },
                                          icon: const Icon(
                                              Icons.archive_outlined),
                                          label: Text(
                                              bt(context, '사용 중지', 'Archive'))),
                                    if (r.kind == 'recipe' &&
                                        r.status == 'draft' &&
                                        business.can('recipes.write') &&
                                        business.can('purchasing.read'))
                                      OutlinedButton.icon(
                                          onPressed: _busy
                                              ? null
                                              : () async {
                                                  if (!await businessConfirm(
                                                          context,
                                                          bt(
                                                              context,
                                                              '재료를 공동 구매 준비로 넘길까요? 구매 담당자가 품명·구매량·단위를 따로 확인합니다.',
                                                              'Send these ingredients to shared purchasing? The purchaser confirms item names, quantities and units separately.')) ||
                                                      !mounted) {
                                                    return;
                                                  }
                                                  final owner = ref.read(
                                                      activeAccountIdProvider);
                                                  await _action((repo) async {
                                                    final next =
                                                        await repo.handover(
                                                            r,
                                                            _handoverId ??=
                                                                newShoppingId());
                                                    _handoverId = null;
                                                    if (context.mounted &&
                                                        mounted &&
                                                        owner ==
                                                            ref.read(
                                                                activeAccountIdProvider)) {
                                                      context.push(
                                                          '/business-workspaces/${widget.workspace}/records/${next.id}');
                                                    }
                                                  });
                                                },
                                          icon: const Icon(
                                              Icons.shopping_basket_outlined),
                                          label: Text(bt(context, '구매 준비로 넘기기',
                                              'Hand over to purchasing'))),
                                    if (r.kind == 'purchase' &&
                                        r.status != 'cancelled' &&
                                        business.paid)
                                      OutlinedButton.icon(
                                          onPressed:
                                              _busy ? null : () => _pdf(r),
                                          icon: const Icon(
                                              Icons.picture_as_pdf_outlined),
                                          label: Text(bt(
                                              context,
                                              'PDF 미리보기·공유·인쇄',
                                              'PDF preview, share & print'))),
                                  ]),
                                  if (_busy) const LinearProgressIndicator(),
                                  if (_error != null)
                                    Padding(
                                        padding: const EdgeInsets.all(12),
                                        child: Text(_error!,
                                            style: TextStyle(
                                                color: Theme.of(context)
                                                    .colorScheme
                                                    .error))),
                                  const SizedBox(height: 20),
                                  ScoutSectionLabel(
                                      title: bt(
                                          context, '등록 내용', 'Record details')),
                                  _BusinessRecordContents(record: r),
                                  const SizedBox(height: 20),
                                  if (r.kind == 'purchase')
                                    Wrap(spacing: 8, runSpacing: 8, children: [
                                      for (final status
                                          in businessNextStatuses(business, r))
                                        OutlinedButton(
                                            onPressed: _busy
                                                ? null
                                                : () => _transition(r, status),
                                            child: Text(switch (status) {
                                              'review' => bt(context, '승인 요청',
                                                  'Request approval'),
                                              'draft' => bt(
                                                  context,
                                                  '수정 요청·작성으로',
                                                  'Return to draft'),
                                              'approved' => bt(context, '구매 승인',
                                                  'Approve purchase'),
                                              'sent' => bt(context, '전달 완료로 기록',
                                                  'Record sharing'),
                                              _ => bt(context, '요청 취소',
                                                  'Cancel request')
                                            }))
                                    ]),
                                ])))),
            loading: () => const Scaffold(
                body: Center(child: CircularProgressIndicator())),
            error: (e, _) => Scaffold(
                appBar: AppBar(),
                body: _BusinessError(
                    e, () => ref.invalidate(businessRecordProvider(q))))),
        loading: () =>
            const Scaffold(body: Center(child: CircularProgressIndicator())),
        error: (e, _) => Scaffold(
            appBar: AppBar(),
            body: _BusinessError(
                e,
                () => ref
                    .invalidate(businessContextProvider(widget.workspace)))));
  }
}

class _BusinessRecordContents extends ConsumerWidget {
  const _BusinessRecordContents({required this.record});
  final BusinessRecord record;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final d = record.data;
    if (record.kind == 'purchase') {
      return SupplierRequestDocument(
          request: record.asPurchase(
              english: Localizations.localeOf(context).languageCode != 'ko'));
    }
    Widget info(String label, String value) => Padding(
        padding: const EdgeInsets.only(bottom: 16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(label, style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 5),
          SelectableText(value)
        ]));
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      if (record.kind == 'recipe') ...[
        info(bt(context, '기준 인분', 'Base servings'), '${d['servings']}'),
        info(bt(context, '재료·조리 수량', 'Ingredients & cooking quantities'),
            '${d['ingredients']}'),
        info(bt(context, '조리 순서·연구 기록', 'Steps & research'), '${d['steps']}')
      ],
      if (record.kind == 'meal') ...[
        info(bt(context, '식단 날짜', 'Meal date'), '${d['date']}'),
        info(bt(context, '예정 인분', 'Planned servings'), '${d['servings']}'),
        for (final id in d['recipe_ids'] as List)
          ref
              .watch(businessRecordProvider(
                  (workspace: record.workspace, id: id as String)))
              .when(
                  data: (r) => Card(
                      child: ListTile(
                          title: Text(r.title),
                          subtitle: Text(
                              bt(context, '공동 레시피 열기', 'Open team recipe')),
                          trailing: const Icon(Icons.chevron_right),
                          onTap: () => context.push(
                              '/business-workspaces/${record.workspace}/records/${r.id}'))),
                  loading: () => const LinearProgressIndicator(),
                  error: (e, _) => Text(bt(context, '연결된 레시피를 불러오지 못했습니다.',
                      'Could not load a linked recipe.')))
      ],
      if (record.kind == 'cost' || record.kind == 'sale') ...[
        info(bt(context, '1인분 원가', 'Cost per serving'),
            '${d['unit_cost']} ${d['currency']}'),
        info(bt(context, '1인분 판매가', 'Price per serving'),
            '${d['unit_price']} ${d['currency']}'),
        if (record.kind == 'sale') ...[
          info(bt(context, '판매 날짜', 'Sale date'), '${d['date']}'),
          info(bt(context, '판매 수량', 'Quantity sold'), '${d['quantity']}'),
          info(bt(context, '매출', 'Revenue'),
              '${(d['quantity'] as num) * (d['unit_price'] as num)} ${d['currency']}')
        ],
        Text(bt(context, '입력한 원가 기준이며 미입력 경비·세금은 포함되지 않습니다.',
            'Based on recorded costs; unentered expenses and taxes are excluded.'))
      ],
      if ((d['notes'] as String? ?? '').isNotEmpty)
        info(bt(context, '메모·요청사항', 'Notes / requests'), d['notes'] as String),
    ]);
  }
}

class BusinessSalesPage extends ConsumerStatefulWidget {
  const BusinessSalesPage({super.key, required this.workspace});
  final String workspace;
  @override
  ConsumerState<BusinessSalesPage> createState() => _BusinessSalesPageState();
}

class _BusinessSalesPageState extends ConsumerState<BusinessSalesPage> {
  ChefSalesPeriod _period = ChefSalesPeriod.day;
  DateTime _date = DateTime.now();
  String _currency = 'KRW';
  @override
  Widget build(BuildContext context) {
    final range = ChefSalesRange.forDate(_date, _period);
    final q = (
      workspace: widget.workspace,
      from: chefDate(range.from),
      until: chefDate(range.until),
      currency: _currency
    );
    String money(Object? v) =>
        '${NumberFormat('#,##0.##').format(v ?? 0)} $_currency';
    return Scaffold(
        appBar: AppBar(title: Text(bt(context, '업소 매출 현황', 'Business sales'))),
        body: Center(
            child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 850),
                child: ListView(padding: const EdgeInsets.all(20), children: [
                  if (ref
                          .watch(businessContextProvider(widget.workspace))
                          .valueOrNull
                          ?.isTest ==
                      true)
                    const BusinessPracticeNotice(),
                  Wrap(spacing: 8, runSpacing: 8, children: [
                    for (final p in ChefSalesPeriod.values)
                      ChoiceChip(
                          label: Text(switch (p) {
                            ChefSalesPeriod.day => bt(context, '일', 'Day'),
                            ChefSalesPeriod.week => bt(context, '주', 'Week'),
                            ChefSalesPeriod.month => bt(context, '월', 'Month')
                          }),
                          selected: p == _period,
                          onSelected: (_) => setState(() => _period = p)),
                    for (final c in ['KRW', 'USD'])
                      ChoiceChip(
                          label: Text(c),
                          selected: c == _currency,
                          onSelected: (_) => setState(() => _currency = c))
                  ]),
                  OutlinedButton.icon(
                      onPressed: () async {
                        final value = await showDatePicker(
                            context: context,
                            initialDate: _date,
                            firstDate: DateTime(2000),
                            lastDate: DateTime(2100));
                        if (value != null && mounted) {
                          setState(() => _date = value);
                        }
                      },
                      icon: const Icon(Icons.calendar_today),
                      label: LocalizedText(
                          '${chefDate(range.from)} ~ ${chefDate(range.until.subtract(const Duration(days: 1)))}')),
                  ref.watch(businessSalesTotalsProvider(q)).when(
                      data: (totals) => Card(
                          child: Padding(
                              padding: const EdgeInsets.all(20),
                              child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    LocalizedText(
                                        '${bt(context, '판매 수량', 'Quantity')}: ${totals['quantity']}'),
                                    const SizedBox(height: 12),
                                    LocalizedText(
                                        '${bt(context, '매출', 'Revenue')}: ${money(totals['revenue'])}',
                                        style: Theme.of(context)
                                            .textTheme
                                            .titleLarge),
                                    const SizedBox(height: 12),
                                    LocalizedText(
                                        '${bt(context, '판매분 원가', 'Recorded cost')}: ${money(totals['cost'])}'),
                                    const SizedBox(height: 12),
                                    LocalizedText(
                                        '${bt(context, '예상이익', 'Estimated profit')}: ${money((totals['revenue'] as num) - (totals['cost'] as num))}')
                                  ]))),
                      loading: () => const LinearProgressIndicator(),
                      error: (e, _) => _BusinessError(
                          e,
                          () =>
                              ref.invalidate(businessSalesTotalsProvider(q)))),
                  const SizedBox(height: 14),
                  Text(bt(
                      context,
                      '해당 통화의 공동 판매 기록만 집계합니다. 예상이익은 매출에서 기록한 원가를 뺀 값이며 실제 순이익과 다릅니다.',
                      'Only shared sales in this currency are included. Estimated profit is revenue minus recorded cost; it is not net profit.')),
                ]))));
  }
}
