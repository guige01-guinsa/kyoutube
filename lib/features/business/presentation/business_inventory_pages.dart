part of 'business_pages.dart';

void _refreshStock(WidgetRef ref, String workspace) {
  ref.invalidate(businessStockItemsProvider(workspace));
  ref.invalidate(businessReceivingProvider);
  ref.invalidate(businessReservationsProvider);
  ref.invalidate(businessStockEventsProvider);
  ref.invalidate(businessRecordProvider);
  ref.invalidate(businessRecordsProvider);
}

Future<BusinessStockItem?> _stockDialog(
    BuildContext context, WidgetRef ref, String workspace, String action,
    {BusinessStockItem? item,
    Map<String, dynamic>? source,
    BusinessReceiving? receiving,
    List<BusinessStockItem> items = const []}) async {
  final account = ref.read(activeAccountIdProvider);
  BusinessStockItem? created;
  await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => ShoppingAccountGuard(
          child: _StockActionForm(
              workspace: workspace,
              action: action,
              item: item,
              source: source,
              receiving: receiving,
              items: items,
              onCreated: (item) => created = item)));
  if (context.mounted && account == ref.read(activeAccountIdProvider)) {
    _refreshStock(ref, workspace);
    return created;
  }
  return null;
}

String _stockActionLabel(BuildContext c, String action) => switch (action) {
      'item' => bt(c, '재고 품목 등록', 'Add stock item'),
      'adjust' => bt(c, '실사·재고 조정', 'Count & adjust stock'),
      'reserve' => bt(c, '조리용 예약', 'Reserve for cooking'),
      'consume' => bt(c, '실제 사용 기록', 'Record actual use'),
      'release' => bt(c, '남은 예약 해제', 'Release remaining reservation'),
      'receive' => bt(c, '품목 입고 기록', 'Record item receipt'),
      'return' => bt(c, '반품 기록', 'Record return'),
      'close' => bt(c, '입고 마감', 'Close receiving'),
      _ => action,
    };

Widget _stockBalance(BuildContext c, BusinessStockItem item,
    {bool inDialog = false}) {
  final tiles = <Widget>[
    for (final metric in [
      (bt(c, '현재고', 'On hand'), item.onHand),
      (bt(c, '예약량', 'Reserved'), item.reserved),
      (bt(c, '사용 가능', 'Available'), item.available),
    ])
      Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Theme.of(c).colorScheme.surfaceContainerLow,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(metric.$1, style: Theme.of(c).textTheme.labelMedium),
          const SizedBox(height: 6),
          LocalizedText('${menuNumber(metric.$2)} ${item.unit}',
              style: Theme.of(c).textTheme.titleMedium),
        ]),
      ),
  ];
  // AlertDialog measures intrinsic height. Its content cannot use LayoutBuilder.
  if (inDialog) {
    return Wrap(spacing: 8, runSpacing: 8, children: [
      for (final tile in tiles) SizedBox(width: 170, child: tile),
    ]);
  }
  return ScoutAdaptiveGrid(minTileWidth: 170, gap: 8, children: tiles);
}

class BusinessInventoryPage extends ConsumerStatefulWidget {
  const BusinessInventoryPage(
      {super.key, required this.workspace, this.itemId});
  final String workspace;
  final String? itemId;
  @override
  ConsumerState<BusinessInventoryPage> createState() =>
      _BusinessInventoryPageState();
}

class _BusinessInventoryPageState extends ConsumerState<BusinessInventoryPage> {
  String _search = '';
  bool _hideEmpty = false;
  @override
  Widget
      build(BuildContext context) =>
          ref.watch(businessContextProvider(widget.workspace)).when(
              loading: () => const Scaffold(
                  body: Center(child: CircularProgressIndicator())),
              error: (e, _) => Scaffold(
                  appBar: AppBar(),
                  body: _BusinessError(
                      e,
                      () => ref.invalidate(
                          businessContextProvider(widget.workspace)))),
              data: (b) => Scaffold(
                  appBar: AppBar(
                      title: Text(bt(
                          context, '재고·조리 예약', 'Stock & cooking reservations')),
                      actions: [
                        IconButton(
                            tooltip: bt(context, '새로고침', 'Refresh'),
                            onPressed: () =>
                                _refreshStock(ref, widget.workspace),
                            icon: const Icon(Icons.refresh)),
                      ]),
                  body: !b.can('purchasing.read')
                      ? Text(
                          businessError(context, StateError('BUSINESS_DENIED')))
                      : Center(
                          child: ConstrainedBox(
                              constraints: const BoxConstraints(maxWidth: 960),
                              child: ListView(
                                  padding: const EdgeInsets.all(20),
                                  children: [
                                    _BusinessWorkHeader(
                                        workspace: b.name,
                                        title: bt(context, '재고·조리 예약',
                                            'Stock & cooking reservations'),
                                        subtitle: bt(
                                            context,
                                            '실제 입고·반품·조리 사용을 기록해 재고를 관리합니다. 예약은 다른 작업이 사용할 수량을 확보하며, 판매 기록만으로 재고가 차감되지는 않습니다.',
                                            'Record actual deliveries, returns and cooking use. Reservations hold quantities for a task; sales records alone do not deduct stock.'),
                                        icon: Icons.inventory_2_outlined),
                                    const SizedBox(height: 12),
                                    if (widget.itemId == null &&
                                        b.can('purchasing.write'))
                                      Align(
                                          alignment: Alignment.centerLeft,
                                          child: FilledButton.icon(
                                              onPressed: () => _stockDialog(
                                                  context, ref, b.id, 'item'),
                                              icon: const Icon(Icons.add),
                                              label: Text(_stockActionLabel(
                                                  context, 'item')))),
                                    if (widget.itemId == null)
                                      TextField(
                                          decoration: InputDecoration(
                                              labelText: bt(
                                                  context,
                                                  '재료명·규격·단위 검색',
                                                  'Search ingredient, specification or unit'),
                                              prefixIcon:
                                                  const Icon(Icons.search)),
                                          onChanged: (v) =>
                                              setState(() => _search = v)),
                                    if (widget.itemId == null)
                                      SwitchListTile(
                                          contentPadding: EdgeInsets.zero,
                                          title: Text(bt(
                                              context,
                                              '현재고·예약이 없는 품목 숨기기',
                                              'Hide items without stock or reservations')),
                                          value: _hideEmpty,
                                          onChanged: (v) =>
                                              setState(() => _hideEmpty = v)),
                                    ref
                                        .watch(businessStockItemsProvider(
                                            widget.workspace))
                                        .when(
                                            loading: () =>
                                                const LinearProgressIndicator(),
                                            error: (e, _) => _BusinessError(
                                                e,
                                                () => ref.invalidate(
                                                    businessStockItemsProvider(
                                                        widget.workspace))),
                                            data: (items) {
                                              final rows = widget.itemId == null
                                                  ? findStockItems(
                                                          items, _search)
                                                      .where((i) =>
                                                          !_hideEmpty ||
                                                          i.onHand != 0 ||
                                                          i.reserved != 0)
                                                      .toList()
                                                  : items
                                                      .where((i) =>
                                                          i.id == widget.itemId)
                                                      .toList();
                                              return Column(
                                                  crossAxisAlignment:
                                                      CrossAxisAlignment
                                                          .stretch,
                                                  children: [
                                                    ScoutSectionLabel(
                                                        title: bt(
                                                            context,
                                                            '재고 품목 ${rows.length}개',
                                                            '${rows.length} stock items')),
                                                    if (rows.isEmpty)
                                                      Padding(
                                                          padding:
                                                              const EdgeInsets
                                                                  .all(20),
                                                          child: Text(bt(
                                                              context,
                                                              '일치하는 재고 품목이 없습니다.',
                                                              'No matching stock items.'))),
                                                    for (final i in rows)
                                                      Card(
                                                          child: Padding(
                                                              padding:
                                                                  const EdgeInsets
                                                                      .all(16),
                                                              child: Column(
                                                                  crossAxisAlignment:
                                                                      CrossAxisAlignment
                                                                          .start,
                                                                  children: [
                                                                    Text(
                                                                        i.label,
                                                                        style: Theme.of(context)
                                                                            .textTheme
                                                                            .titleMedium),
                                                                    const SizedBox(
                                                                        height:
                                                                            8),
                                                                    _stockBalance(
                                                                        context,
                                                                        i),
                                                                    if (i.note
                                                                        .isNotEmpty)
                                                                      Padding(
                                                                          padding: const EdgeInsets
                                                                              .symmetric(
                                                                              vertical:
                                                                                  8),
                                                                          child:
                                                                              Text(i.note)),
                                                                    if (b.can(
                                                                        'purchasing.write'))
                                                                      RecordManagementMenu(
                                                                          onError: (e) => businessError(
                                                                              context,
                                                                              e),
                                                                          actions: [
                                                                            if (b.owner) ...[
                                                                              RecordManagementAction('unit', bt(context, '재고 단위 변경', 'Change stock unit'), Icons.swap_horiz, () => _manageStockIdentity(context, ref, b.id, i, true, detail: widget.itemId != null)),
                                                                              RecordManagementAction('erase', bt(context, '영구 삭제', 'Delete permanently'), Icons.delete_forever, () => _manageStockIdentity(context, ref, b.id, i, false, detail: widget.itemId != null)),
                                                                            ],
                                                                            RecordManagementAction(
                                                                                'note',
                                                                                bt(context, '관리 메모 수정', 'Edit management note'),
                                                                                Icons.edit_note,
                                                                                () => _stockNote(context, ref, b.id, i)),
                                                                          ]),
                                                                    if (widget
                                                                            .itemId ==
                                                                        null)
                                                                      TextButton(
                                                                          onPressed: () => context.push(
                                                                              '/business-workspaces/${b.id}/inventory/${i.id}'),
                                                                          child: Text(bt(
                                                                              context,
                                                                              '수불·예약 보기',
                                                                              'View movements & reservations')))
                                                                    else ...[
                                                                      const SizedBox(
                                                                          height:
                                                                              12),
                                                                      Wrap(
                                                                          spacing:
                                                                              8,
                                                                          runSpacing:
                                                                              8,
                                                                          children: [
                                                                            if (b.can('purchasing.write'))
                                                                              OutlinedButton(onPressed: () => _stockDialog(context, ref, b.id, 'adjust', item: i), child: Text(_stockActionLabel(context, 'adjust'))),
                                                                            if (b.can('purchasing.write') ||
                                                                                b.can('recipes.write'))
                                                                              FilledButton(onPressed: i.available > 0 ? () => _stockDialog(context, ref, b.id, 'reserve', item: i) : null, child: Text(_stockActionLabel(context, 'reserve'))),
                                                                          ]),
                                                                      const Divider(
                                                                          height:
                                                                              32),
                                                                      Text(
                                                                          bt(
                                                                              context,
                                                                              '사용 대기 중인 예약',
                                                                              'Reservations awaiting use'),
                                                                          style: Theme.of(context)
                                                                              .textTheme
                                                                              .titleMedium),
                                                                      ref
                                                                          .watch(
                                                                              businessReservationsProvider((
                                                                            workspace:
                                                                                b.id,
                                                                            item:
                                                                                i.id
                                                                          )))
                                                                          .when(
                                                                              loading: () => const LinearProgressIndicator(),
                                                                              error: (e, _) => _BusinessError(e, () => ref.invalidate(businessReservationsProvider)),
                                                                              data: (rows) => Column(children: [
                                                                                    if (rows.isEmpty) Text(bt(context, '남은 예약이 없습니다.', 'No remaining reservations.')),
                                                                                    for (final r in rows)
                                                                                      ListTile(
                                                                                          contentPadding: EdgeInsets.zero,
                                                                                          title: Text(r['purpose'] as String),
                                                                                          subtitle: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                                                                            LocalizedText('${menuNumber((r['remaining'] as num).toDouble())} ${i.unit} · ${_businessDate(context, r['created_at'])}'),
                                                                                            if (b.can('purchasing.write') || b.can('recipes.write'))
                                                                                              Wrap(spacing: 8, children: [
                                                                                                TextButton(onPressed: () => _stockDialog(context, ref, b.id, 'consume', item: i, source: r), child: Text(_stockActionLabel(context, 'consume'))),
                                                                                                TextButton(onPressed: () => _stockDialog(context, ref, b.id, 'release', item: i, source: r), child: Text(_stockActionLabel(context, 'release'))),
                                                                                              ]),
                                                                                          ])),
                                                                                  ])),
                                                                    ],
                                                                  ]))),
                                                    if (widget.itemId != null &&
                                                        rows.isNotEmpty)
                                                      _StockHistory(
                                                          workspace: b.id,
                                                          item: widget.itemId,
                                                          canReturn: b.can(
                                                              'purchasing.write')),
                                                  ]);
                                            }),
                                  ])))));
}

class BusinessReceivingPage extends ConsumerWidget {
  const BusinessReceivingPage(
      {super.key, required this.workspace, required this.request});
  final String workspace, request;
  @override
  Widget build(BuildContext context, WidgetRef ref) =>
      ref.watch(businessContextProvider(workspace)).when(
          loading: () =>
              const Scaffold(body: Center(child: CircularProgressIndicator())),
          error: (e, _) => Scaffold(
              appBar: AppBar(),
              body: _BusinessError(
                  e, () => ref.invalidate(businessContextProvider(workspace)))),
          data: (b) => Scaffold(
              appBar: AppBar(
                  title:
                      Text(bt(context, '품목별 입고·반품', 'Item receipts & returns')),
                  actions: [
                    IconButton(
                        tooltip: bt(context, '새로고침', 'Refresh'),
                        onPressed: () => _refreshStock(ref, workspace),
                        icon: const Icon(Icons.refresh)),
                  ]),
              body: !b.can('purchasing.read')
                  ? Text(businessError(context, StateError('BUSINESS_DENIED')))
                  : Center(
                      child: ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 960),
                          child: ListView(
                              padding: const EdgeInsets.all(20),
                              children: [
                                _BusinessWorkHeader(
                                    workspace: b.name,
                                    title: bt(context, '입고 검수·반품',
                                        'Inspect deliveries & returns'),
                                    subtitle: bt(
                                        context,
                                        '품목을 검수한 뒤 실제 도착한 양만 입력하세요. 구매 단위와 재고 단위가 다르면 환산량을 직접 확인합니다.',
                                        'Inspect each item and record only the quantity actually delivered. Confirm the conversion when purchase and stock units differ.'),
                                    icon: Icons.fact_check_outlined),
                                Wrap(spacing: 8, children: [
                                  TextButton(
                                      onPressed: () => context.push(
                                          '/business-workspaces/$workspace/records/$request'),
                                      child: Text(bt(context, '구매요청서 확인',
                                          'Review purchase request'))),
                                  if (b.can('purchasing.write'))
                                    TextButton(
                                        onPressed: () => _stockDialog(
                                            context, ref, workspace, 'item'),
                                        child: Text(_stockActionLabel(
                                            context, 'item'))),
                                ]),
                                ref
                                    .watch(businessReceivingProvider((
                                      workspace: workspace,
                                      request: request
                                    )))
                                    .when(
                                        loading: () =>
                                            const LinearProgressIndicator(),
                                        error: (e, _) => _BusinessError(
                                            e,
                                            () => ref.invalidate(
                                                    businessReceivingProvider((
                                                  workspace: workspace,
                                                  request: request
                                                )))),
                                        data: (r) => Column(
                                                crossAxisAlignment:
                                                    CrossAxisAlignment.stretch,
                                                children: [
                                                  Text(r.title,
                                                      style: Theme.of(context)
                                                          .textTheme
                                                          .titleLarge),
                                                  Text(r.status == 'received' &&
                                                          !r.legacy
                                                      ? _stockActionLabel(
                                                          context, 'close')
                                                      : businessStatusLabel(
                                                          context, r.status)),
                                                  if (r.legacy)
                                                    Card(
                                                        child: Padding(
                                                            padding:
                                                                const EdgeInsets
                                                                    .all(16),
                                                            child: Text(bt(
                                                                context,
                                                                '이전 방식으로 입고 완료한 요청입니다. 과거 입고는 재고에 자동 반영되지 않습니다. 실제 보유량은 재고 화면에서 실사 조정으로 기록하세요.',
                                                                'This request was completed with the earlier receipt workflow. Past receipts are not imported into stock. Record an actual stock count in inventory.')))),
                                                  if (r.closure != null)
                                                    Card(
                                                        child: Padding(
                                                            padding:
                                                                const EdgeInsets
                                                                    .all(16),
                                                            child: LocalizedText(
                                                                '${bt(context, '마감 사유', 'Closing reason')}: ${r.closure!['reason']}\n${bt(context, '마감 후 반품은 기록할 수 있습니다. 교환·추가 입고는 새 요청서로 관리하세요.', 'Returns remain available after closing. Use a new request for replacements or further deliveries.')}'))),
                                                  if (r.status == 'cancelled')
                                                    Text(bt(
                                                        context,
                                                        '취소 전에 입고한 재고는 그대로 남아 있습니다. 실제 반품했다면 아래 입고 이력에서 반품을 기록하세요.',
                                                        'Stock received before cancellation remains on hand. Record actual returns against the receipt history below.')),
                                                  ref
                                                      .watch(
                                                          businessStockItemsProvider(
                                                              workspace))
                                                      .when(
                                                          loading: () =>
                                                              const LinearProgressIndicator(),
                                                          error: (e, _) => _BusinessError(
                                                              e,
                                                              () => ref.invalidate(
                                                                  businessStockItemsProvider(
                                                                      workspace))),
                                                          data: (items) =>
                                                              Column(children: [
                                                                for (final l
                                                                    in r.lines)
                                                                  Card(
                                                                      child: Padding(
                                                                          padding: const EdgeInsets.all(16),
                                                                          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                                                                            LocalizedText('${l['name']} · ${l['spec']}',
                                                                                style: Theme.of(context).textTheme.titleMedium),
                                                                            Wrap(spacing: 16, runSpacing: 8, children: [
                                                                              for (final k in [
                                                                                'quantity',
                                                                                'received',
                                                                                'returned',
                                                                                'net',
                                                                                'outstanding'
                                                                              ])
                                                                                LocalizedText('${_receivingQuantityLabel(context, k)}: ${menuNumber((l[k] as num? ?? 0).toDouble())} ${l['unit']}'),
                                                                            ]),
                                                                            if (r.status == 'sent' &&
                                                                                b.can('purchasing.write') &&
                                                                                (l['outstanding'] as num) > 0)
                                                                              Align(alignment: Alignment.centerLeft, child: OutlinedButton(onPressed: () => _stockDialog(context, ref, workspace, 'receive', source: l, receiving: r, items: items), child: Text(items.isEmpty ? bt(context, '재고 등록·입고', 'Add stock item & receive') : _stockActionLabel(context, 'receive')))),
                                                                          ])))
                                                              ])),
                                                  if (r.status == 'sent' &&
                                                      b.can(
                                                          'purchasing.write')) ...[
                                                    Text(bt(
                                                        context,
                                                        '입고 기록만으로 요청서가 마감되지는 않습니다. 잔량과 반품을 확인한 뒤 마감하세요.',
                                                        'Receipts alone do not close the request. Review outstanding quantities and returns before closing.')),
                                                    Align(
                                                        alignment: Alignment
                                                            .centerLeft,
                                                        child: FilledButton(
                                                            onPressed: () =>
                                                                _stockDialog(
                                                                    context,
                                                                    ref,
                                                                    workspace,
                                                                    'close',
                                                                    receiving:
                                                                        r),
                                                            child: Text(
                                                                _stockActionLabel(
                                                                    context,
                                                                    'close')))),
                                                  ],
                                                  _StockHistory(
                                                      workspace: workspace,
                                                      request: request,
                                                      canReturn: b.can(
                                                          'purchasing.write')),
                                                ])),
                              ])))));
}

String _receivingQuantityLabel(BuildContext c, String k) => switch (k) {
      'quantity' => bt(c, '요청량', 'Requested'),
      'received' => bt(c, '누적 입고', 'Total received'),
      'returned' => bt(c, '반품량', 'Returned'),
      'net' => bt(c, '순입고', 'Net received'),
      _ => bt(c, '미입고', 'Outstanding'),
    };

class _StockHistory extends ConsumerStatefulWidget {
  const _StockHistory(
      {required this.workspace,
      this.item,
      this.request,
      required this.canReturn});
  final String workspace;
  final String? item, request;
  final bool canReturn;
  @override
  ConsumerState<_StockHistory> createState() => _StockHistoryState();
}

class _StockHistoryState extends ConsumerState<_StockHistory> {
  int _offset = 0;
  @override
  Widget build(BuildContext context) {
    final q = (
      workspace: widget.workspace,
      item: widget.item,
      request: widget.request,
      offset: _offset
    );
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      const Divider(height: 32),
      Text(bt(context, '재고 수불 이력', 'Stock movement history'),
          style: Theme.of(context).textTheme.titleMedium),
      ref.watch(businessStockEventsProvider(q)).when(
          loading: () => const LinearProgressIndicator(),
          error: (e, _) => _BusinessError(
              e, () => ref.invalidate(businessStockEventsProvider(q))),
          data: (events) =>
              Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                if (events.isEmpty)
                  Text(bt(context, '기록된 수불이 없습니다.',
                      'No recorded stock movements.')),
                for (final e in events)
                  Card(
                      child: Padding(
                          padding: const EdgeInsets.all(12),
                          child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                LocalizedText(
                                    '${_stockActionLabel(context, e['kind'] as String)} · ${_businessDate(context, e['created_at'])}'),
                                Text(e['reason'] as String),
                                LocalizedText(
                                    '${bt(context, '현재고 증감', 'On-hand change')}: ${menuNumber((e['delta'] as num).toDouble())} ${e['item_unit'] ?? ''} · ${bt(context, '예약 증감', 'Reservation change')}: ${menuNumber((e['reserved_delta'] as num).toDouble())} ${e['item_unit'] ?? ''}'),
                                if (e['purchase_quantity'] != null)
                                  LocalizedText(
                                      '${(e['snapshot'] as Map?)?['line']?['name'] ?? ''} · ${menuNumber((e['purchase_quantity'] as num).toDouble())} ${(e['snapshot'] as Map?)?['line']?['unit'] ?? ''} · 1 ${(e['snapshot'] as Map?)?['line']?['unit'] ?? ''} = ${menuNumber((e['factor'] as num).toDouble())} ${(e['snapshot'] as Map?)?['item_unit'] ?? ''}'),
                                if (e['kind'] == 'receive' &&
                                    (e['returnable'] as num? ?? 0) > 0 &&
                                    widget.canReturn)
                                  TextButton(
                                      onPressed: () => _stockDialog(context,
                                          ref, widget.workspace, 'return',
                                          source: e),
                                      child: Text(_stockActionLabel(
                                          context, 'return'))),
                              ]))),
                Wrap(spacing: 12, children: [
                  TextButton(
                      onPressed: _offset == 0
                          ? null
                          : () => setState(() => _offset -= 50),
                      child: Text(bt(context, '이전', 'Previous'))),
                  LocalizedText(
                      '${events.isEmpty ? _offset : _offset + 1}–${_offset + events.length}'),
                  TextButton(
                      onPressed: events.length < 50
                          ? null
                          : () => setState(() => _offset += 50),
                      child: Text(bt(context, '다음', 'Next'))),
                ]),
              ])),
    ]);
  }
}

Future<void> _stockNote(BuildContext context, WidgetRef ref, String workspace,
    BusinessStockItem item) async {
  final account = ref.read(activeAccountIdProvider);
  String value = item.note;
  final note = await showDialog<String>(
      context: context,
      builder: (ctx) => ShoppingAccountGuard(
              child: AlertDialog(
            title: Text(bt(ctx, '재고 관리 메모', 'Stock management note')),
            content: SizedBox(
                width: 480,
                child: TextFormField(
                    initialValue: value,
                    minLines: 2,
                    maxLines: 5,
                    maxLength: 500,
                    onChanged: (v) => value = v,
                    decoration: InputDecoration(
                        helperText: bt(
                            ctx,
                            '보관 위치 등 관리 정보를 적으세요. 수량·단위는 바뀌지 않습니다.',
                            'Add storage location or other notes. Quantities and units stay unchanged.'),
                        helperMaxLines: 3))),
            actions: [
              TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: Text(bt(ctx, '취소', 'Cancel'))),
              FilledButton(
                  onPressed: () => Navigator.pop(ctx, value.trim()),
                  child: Text(bt(ctx, '저장', 'Save')))
            ],
          )));
  if (!context.mounted ||
      note == null ||
      account == null ||
      account != ref.read(activeAccountIdProvider)) {
    return;
  }
  await ref
      .read(businessInventoryRepositoryProvider)
      .saveNote(workspace, item, note);
  if (context.mounted && account == ref.read(activeAccountIdProvider)) {
    _refreshStock(ref, workspace);
  }
}
