part of 'business_pages.dart';

class BusinessStockPurchaseHints extends ConsumerStatefulWidget {
  const BusinessStockPurchaseHints(
      {super.key, required this.workspace, required this.requirements});
  final String workspace;
  final List<Map<String, dynamic>> requirements;
  @override
  ConsumerState<BusinessStockPurchaseHints> createState() =>
      _BusinessStockPurchaseHintsState();
}

class _BusinessStockPurchaseHintsState
    extends ConsumerState<BusinessStockPurchaseHints> {
  late Future<List<Map<String, dynamic>>> _pending = _load();
  Future<List<Map<String, dynamic>>> _load() => Future.sync(() => ref
      .read(businessInventoryRepositoryProvider)
      .hints(widget.workspace, widget.requirements));
  @override
  Widget build(BuildContext context) => Card(
      child: Padding(
          padding: const EdgeInsets.all(16),
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Text(
                bt(context, '재고·중복 요청 확인',
                    'Check stock & overlapping requests'),
                style: Theme.of(context).textTheme.titleMedium),
            Text(bt(
                context,
                '재고와 예약은 계속 바뀝니다. 조회한 가용량 중 이번 조리에 쓸 양만 아래에 입력하세요. 이 화면은 재고를 예약하지 않습니다.',
                'Stock and reservations can change. Enter below only the available quantity allocated to this cooking task. This screen does not reserve stock.')),
            FutureBuilder(
                future: _pending,
                builder: (context, s) {
                  if (s.hasError) return Text(businessError(context, s.error!));
                  if (!s.hasData) return const LinearProgressIndicator();
                  return Column(children: [
                    for (final h in s.data!)
                      ExpansionTile(
                        tilePadding: EdgeInsets.zero,
                        title: Text(widget.requirements.firstWhere(
                            (r) => r['key'] == h['key'],
                            orElse: () => {'name': ''})['name'] as String),
                        subtitle: LocalizedText(
                            '${h['item'] == null ? bt(context, '같은 이름·규격·단위의 재고가 없습니다.', 'No stock matches this name, specification and unit.') : '${bt(context, '조회 시 사용 가능', 'Available when checked')}: ${menuNumber((h['item']['available'] as num).toDouble())} ${h['item']['unit']}'} · ${bt(context, '진행 중 요청', 'Open requests')} ${(h['open_requests'] as List).length}'),
                        children: [
                          if (h['item'] != null) ...[
                            _stockBalance(
                                context,
                                BusinessStockItem.fromJson(
                                    Map<String, dynamic>.from(
                                        h['item'] as Map))),
                            TextButton(
                                onPressed: () => context.push(
                                    '/business-workspaces/${widget.workspace}/inventory/${h['item']['id']}'),
                                child: Text(bt(context, '수불·예약 보기',
                                    'View movements & reservations'))),
                          ],
                          if ((h['open_requests'] as List).isNotEmpty)
                            Text(bt(
                                context,
                                '같은 재료를 기준으로 만든 진행 중 요청을 최대 5개 표시합니다. 작성 후 수정됐을 수 있으므로 실제 품목·납품일을 확인하세요. 입고 예정량은 자동 차감하지 않습니다.',
                                'Up to 5 open requests originally based on this ingredient are shown. They may have been edited; check actual items and delivery dates. Incoming quantities are not deducted automatically.')),
                          for (final r in h['open_requests'] as List)
                            ListTile(
                                contentPadding: EdgeInsets.zero,
                                title: Text(r['title'] as String),
                                subtitle: Text(businessStatusLabel(
                                    context, r['status'] as String)),
                                trailing: const Icon(Icons.chevron_right),
                                onTap: () => context.push(
                                    '/business-workspaces/${widget.workspace}/records/${r['id']}')),
                        ],
                      )
                  ]);
                }),
            Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                    onPressed: () => setState(() {
                          _pending = _load();
                        }),
                    icon: const Icon(Icons.refresh),
                    label: Text(bt(context, '최신 재고·요청 다시 조회',
                        'Reload current stock & requests')))),
          ])));
}
