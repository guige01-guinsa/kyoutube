import '../../../core/localization/localized_text.dart';
import '../../../core/auth/auth_return.dart';
import '../data/purchase_cleanup_repository.dart';
import '../../guide/presentation/guide_help_button.dart';
import 'package:flutter/material.dart';
import '../../../core/widgets/scout_page.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../auth/application/auth_providers.dart';
import '../application/request_document_service.dart';
import '../application/request_ledger_documents.dart';
import '../data/request_ledger_repository.dart';
import '../data/supplier_request_repository.dart';
import '../domain/purchase_request_ledger.dart';
import '../domain/supplier_request.dart';
import 'request_document_preview.dart';
import 'shopping_assistant_dialogs.dart';
import 'supplier_request_editor.dart';
import 'supplier_requests_page.dart';

class RequestLedgerPage extends ConsumerWidget {
  const RequestLedgerPage({super.key, this.embedded = false});
  final bool embedded;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final owner = ref.watch(activeAccountIdProvider);
    if (owner == null) {
      return Scaffold(
          appBar: AppBar(
              title: Text(
                  shopText(context, '구매요청 대장', 'Purchase request ledger'))),
          body: Center(
              child: FilledButton(
                  onPressed: () => context.push(loginFor(
                      GoRouterState.of(context).uri.toString(),
                      resume: true)),
                  child: Text(shopText(context, '로그인', 'Sign in')))));
    }
    return _LedgerWorkspace(key: ValueKey(owner), embedded: embedded);
  }
}

class _LedgerWorkspace extends ConsumerStatefulWidget {
  const _LedgerWorkspace({super.key, this.embedded = false});
  final bool embedded;
  @override
  ConsumerState<_LedgerWorkspace> createState() => _LedgerWorkspaceState();
}

class _LedgerWorkspaceState extends ConsumerState<_LedgerWorkspace> {
  final _query = TextEditingController();
  late final _owner = ref.read(activeAccountIdProvider);
  DateTimeRange? _range = DateTimeRange(
      start: DateTime(DateTime.now().year, DateTime.now().month),
      end: DateTime(
          DateTime.now().year, DateTime.now().month, DateTime.now().day));
  String _status = '';
  List<RequestLedgerRow> _rows = [];
  RequestLedgerPageData? _data;
  RequestLedgerFilter? _loadedFilter;
  String? _error;
  bool _loading = true, _working = false;
  int _generation = 0;
  bool get _active =>
      mounted && _owner != null && ref.read(activeAccountIdProvider) == _owner;
  bool get _english => Localizations.localeOf(context).languageCode != 'ko';
  String t(String ko, String en) => shopText(context, ko, en);
  RequestLedgerFilter get _filter => RequestLedgerFilter(
      from: _range?.start,
      before: _range == null
          ? null
          : DateTime(_range!.end.year, _range!.end.month, _range!.end.day + 1),
      status: _status,
      query: _query.text);
  String _label(RequestLedgerFilter f) =>
      '${f.from == null ? t('전체 기간', 'All dates') : '${ledgerDate(f.from!)} ~ ${ledgerDate(f.before!.subtract(const Duration(days: 1)))}'} · ${f.status.isEmpty ? t('전체 상태', 'All statuses') : requestStatus(f.status, _english)}${f.query.isEmpty ? '' : ' · ${f.query}'}';
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  @override
  void dispose() {
    _query.dispose();
    super.dispose();
  }

  Future<void> _load({bool more = false}) async {
    if (!mounted || !_active) return;
    ref.invalidate(purchaseCleanupIndexProvider(null));
    final generation = ++_generation;
    final filter = more ? _loadedFilter! : _filter;
    setState(() {
      _loading = true;
      _error = null;
      if (!more) {
        _rows = [];
        _data = null;
      }
    });
    try {
      final data = await ref
          .read(requestLedgerRepositoryProvider)
          .search(filter, offset: more ? _rows.length : 0);
      if (!_active || generation != _generation) return;
      setState(() {
        _data = data;
        _loadedFilter = filter;
        _rows = more
            ? [
                ..._rows,
                ...data.rows.where((r) => !_rows.any((old) => old.id == r.id))
              ]
            : data.rows;
      });
    } catch (_) {
      if (_active && generation == _generation) {
        setState(() => _error = t('대장을 불러오지 못했습니다. 연결을 확인하고 다시 시도해 주세요.',
            'Could not load the ledger. Check your connection and retry.'));
      }
    } finally {
      if (_active && generation == _generation) {
        setState(() => _loading = false);
      }
    }
  }

  void _message(String message) {
    if (_active) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(message)));
    }
  }

  Future<void> _open(RequestLedgerRow row) async {
    setState(() => _working = true);
    try {
      final request =
          await ref.read(requestLedgerRepositoryProvider).request(row.id);
      if (!mounted || !_active) return;
      final action = await showDialog<String>(
          context: context,
          barrierDismissible: false,
          builder: (_) => ShoppingAccountGuard(
              child: SupplierRequestDetails(request: request)));
      if (!mounted || !_active) return;
      if (action == 'edit' || action == 'repeat') {
        final allSuppliers = await ref.read(shoppingSuppliersProvider.future);
        final archives =
            ref.read(purchaseCleanupIndexProvider(null)).valueOrNull;
        final suppliers = allSuppliers
            .where((s) => !(archives?.contains('supplier', s.id) ?? false))
            .toList();
        if (!mounted || !_active) return;
        final draft = action == 'repeat' ? request.repeat() : request;
        await showDialog<SupplierRequest>(
            context: context,
            barrierDismissible: false,
            builder: (_) => ShoppingAccountGuard(
                    child: SupplierRequestEditor(suppliers: [
                  if (action == 'edit' &&
                      !suppliers.any((s) => s.id == draft.supplier.id))
                    draft.supplier,
                  ...suppliers
                ], groups: const [], request: draft)));
      }
      if (_active) {
        ref.invalidate(supplierRequestsProvider);
        await _load();
      }
    } catch (_) {
      _message(t('요청서를 열지 못했습니다. 새로고침해 주세요.',
          'Could not open the request. Refresh and try again.'));
    } finally {
      if (_active) setState(() => _working = false);
    }
  }

  Future<void> _events(RequestLedgerRow row) async {
    setState(() => _working = true);
    try {
      final events =
          await ref.read(requestLedgerRepositoryProvider).events(row.id);
      if (!mounted || !_active) return;
      await showDialog<void>(
          context: context,
          builder: (ctx) => ShoppingAccountGuard(
                  child: AlertDialog(
                      title: Text(t('처리 이력', 'Activity history')),
                      content: SizedBox(
                          width: 560,
                          child: SingleChildScrollView(
                              child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                SelectableText(row.reference),
                                const SizedBox(height: 12),
                                Text(t(
                                    '최근 200개 변경을 표시합니다. 상태는 사용자가 확인해 기록한 내용입니다.',
                                    'Latest 200 changes. Statuses are recorded by the user after confirmation.')),
                                if (events.isEmpty)
                                  Text(t('기록이 없습니다.', 'No activity yet.')),
                                for (final event in events)
                                  ListTile(
                                      contentPadding: EdgeInsets.zero,
                                      title: Text(event['event'] == 'baseline'
                                          ? t('대장 도입 시점의 상태',
                                              'Status when ledger tracking began')
                                          : event['event'] == 'created'
                                              ? t('요청서 생성', 'Request created')
                                              : event['event'] == 'edited'
                                                  ? t('내용 수정',
                                                      'Contents edited')
                                                  : t('상태 변경',
                                                      'Status changed')),
                                      subtitle: LocalizedText(
                                          '${requestStatus(event['to_status'] as String, _english)} · v${event['revision']}\n${DateTime.parse(event['recorded_at'] as String).toLocal().toString().split('.').first}')),
                              ]))),
                      actions: [
                    TextButton(
                        onPressed: () => Navigator.pop(ctx),
                        child: Text(t('닫기', 'Close')))
                  ])));
    } catch (_) {
      _message(t('처리 이력을 불러오지 못했습니다.', 'Could not load activity history.'));
    } finally {
      if (_active) setState(() => _working = false);
    }
  }

  Future<void> _export(bool pdf, BuildContext button) async {
    final filter = _loadedFilter;
    if (filter == null) return;
    final box = button.findRenderObject() as RenderBox;
    final origin = box.localToGlobal(Offset.zero) & box.size;
    final english = _english, label = _label(filter);
    setState(() => _working = true);
    try {
      final data = await ref
          .read(requestLedgerRepositoryProvider)
          .search(filter, limit: 1000);
      if (!mounted || !_active) return;
      if (data.totalCount > 1000) {
        _message(t('출력은 한 번에 1,000건까지 가능합니다. 기간·업체 조건을 좁혀 주세요.',
            'Export supports up to 1,000 requests at once. Narrow the date range or supplier filter.'));
        return;
      }
      final name = 'purchase-request-ledger-${ledgerDate(DateTime.now())}';
      if (pdf) {
        await showDialog<void>(
            context: context,
            builder: (_) => PurchasePdfPreview(
                title: t('대장 PDF 미리보기', 'Ledger PDF preview'),
                filename: name,
                buildDocument: () async {
                  await ref.read(requestDocumentAccessProvider)();
                  if (!_active) throw StateError('Account changed');
                  final font = await rootBundle
                      .load('assets/fonts/NanumGothic-Regular.ttf');
                  if (!_active) throw StateError('Account changed');
                  return requestLedgerPdf(data, font,
                      english: english, filterLabel: label);
                }));
      } else {
        await ref.read(requestDocumentExportProvider)(
            requestLedgerCsv(data.rows, english: english),
            '$name.csv',
            'text/csv',
            origin);
        _message(t('대장 CSV 출력 화면을 열었습니다.', 'Ledger CSV export opened.'));
      }
    } catch (_) {
      _message(t('대장을 출력하지 못했습니다. 연결 상태를 확인해 주세요.',
          'Could not export the ledger. Check your connection.'));
    } finally {
      if (_active) setState(() => _working = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: widget.embedded
            ? null
            : AppBar(
                title: Text(t('구매요청 대장', 'Purchase request ledger')),
                actions: [
                    GuideHelpButton(lesson: 'buy-ledger', enabled: !_working),
                    IconButton(
                        onPressed: _working ? null : () => _load(),
                        tooltip: t('새로고침', 'Refresh'),
                        icon: const Icon(Icons.refresh))
                  ]),
        body: Center(
            child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 1120),
                child: ListView(padding: const EdgeInsets.all(20), children: [
                  ScoutPageHeading(
                      title: t('요청부터 입고 확인까지, 한눈에',
                          'From request to receipt, in one place'),
                      subtitle: t('기간은 작성일 기준입니다. 실제 결제·구매 이력과 구분하여 관리합니다.',
                          'Dates filter request creation. Keep these records separate from payments and actual purchases.'),
                      icon: Icons.table_chart_outlined),
                  const SizedBox(height: 16),
                  ScoutPanel(
                      child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                        ScoutSectionLabel(title: t('검색 조건', 'Search filters')),
                        TextField(
                            controller: _query,
                            maxLength: 120,
                            enabled: !_working,
                            decoration: InputDecoration(
                                labelText: t('업체·요청자·요청번호·사업자번호 검색',
                                    'Search supplier, buyer, reference or registration'),
                                prefixIcon: const Icon(Icons.search),
                                suffixIcon: IconButton(
                                    tooltip: t('검색', 'Search'),
                                    onPressed: _working ? null : () => _load(),
                                    icon: const Icon(Icons.arrow_forward))),
                            onSubmitted: (_) => _load()),
                        Wrap(
                            spacing: 10,
                            runSpacing: 10,
                            crossAxisAlignment: WrapCrossAlignment.center,
                            children: [
                              OutlinedButton.icon(
                                  onPressed: _working
                                      ? null
                                      : () async {
                                          final range =
                                              await showDateRangePicker(
                                                  context: context,
                                                  firstDate: DateTime(2020),
                                                  lastDate: DateTime.now(),
                                                  initialDateRange: _range);
                                          if (range != null && _active) {
                                            setState(() => _range = range);
                                            await _load();
                                          }
                                        },
                                  icon: const Icon(Icons.date_range),
                                  label: LocalizedText(_range == null
                                      ? t('기간 선택', 'Select dates')
                                      : '${ledgerDate(_range!.start)} ~ ${ledgerDate(_range!.end)}')),
                              TextButton(
                                  onPressed: _working
                                      ? null
                                      : () {
                                          setState(() => _range = null);
                                          _load();
                                        },
                                  child: Text(t('전체 기간', 'All dates'))),
                              SizedBox(
                                  width: 250,
                                  child: DropdownButtonFormField<String>(
                                      initialValue: _status,
                                      isExpanded: true,
                                      decoration: InputDecoration(
                                          labelText: t('진행 상태', 'Status')),
                                      items: [
                                        for (final s in [
                                          '',
                                          'draft',
                                          'sent',
                                          'accepted',
                                          'received',
                                          'cancelled'
                                        ])
                                          DropdownMenuItem(
                                              value: s,
                                              child: Text(
                                                  s.isEmpty
                                                      ? t('전체', 'All')
                                                      : requestStatus(
                                                          s, _english),
                                                  overflow:
                                                      TextOverflow.ellipsis))
                                      ],
                                      onChanged: _working
                                          ? null
                                          : (v) {
                                              setState(() => _status = v!);
                                              _load();
                                            })),
                            ]),
                      ])),
                  const SizedBox(height: 20),
                  if (_loading) const LinearProgressIndicator(),
                  if (_error != null)
                    Column(children: [
                      Text(_error!),
                      TextButton(
                          onPressed: () => _load(),
                          child: Text(t('다시 시도', 'Retry')))
                    ]),
                  if (_data != null) ...[
                    Text(
                        t('검색 결과 ${_data!.totalCount}건',
                            '${_data!.totalCount} matching requests'),
                        style: Theme.of(context).textTheme.titleMedium),
                    const SizedBox(height: 8),
                    Text(t('합계: 취소 제외 · 입력 단가가 있는 품목만 · 배송비·세금 별도 확인',
                        'Totals: exclude cancelled and unpriced items · confirm delivery charges and taxes separately')),
                    Text(t('합계와 내보내기에는 보관 기록도 포함됩니다.',
                        'Totals and exports include archived records.')),
                    Wrap(spacing: 10, runSpacing: 8, children: [
                      for (final total in _data!.totals)
                        Card(
                            child: Padding(
                                padding: const EdgeInsets.all(16),
                                child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      LocalizedText('${total.currency} ${total.amount}',
                                          style: Theme.of(context)
                                              .textTheme
                                              .titleLarge),
                                      Text(t(
                                          '견적 대기 ${total.unpricedCount}품목 · 취소 ${total.cancelledCount}건',
                                          '${total.unpricedCount} unpriced items · ${total.cancelledCount} cancelled')),
                                    ])))
                    ]),
                    const SizedBox(height: 12),
                    Wrap(spacing: 8, runSpacing: 8, children: [
                      Builder(
                          builder: (ctx) => OutlinedButton.icon(
                              onPressed: _working || _loading
                                  ? null
                                  : () => _export(false, ctx),
                              icon: const Icon(Icons.table_view),
                              label: Text(t('CSV 대장 출력', 'Export CSV')))),
                      Builder(
                          builder: (ctx) => OutlinedButton.icon(
                              onPressed: _working || _loading
                                  ? null
                                  : () => _export(true, ctx),
                              icon: const Icon(Icons.print_outlined),
                              label: Text(
                                  t('PDF 미리보기·인쇄', 'PDF preview & print')))),
                    ]),
                    const SizedBox(height: 16),
                    if (_rows.isEmpty)
                      Padding(
                          padding: const EdgeInsets.all(24),
                          child: Text(
                              t('조건에 맞는 요청서가 없습니다.', 'No matching requests.'))),
                    for (final r in _rows.where((r) => !(ref
                            .watch(purchaseCleanupIndexProvider(null))
                            .valueOrNull
                            ?.hidesRequest('request', r.id, r.status) ??
                        false)))
                      Card(
                          margin: const EdgeInsets.only(bottom: 12),
                          child: Padding(
                              padding: const EdgeInsets.all(16),
                              child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(r.supplier,
                                        style: Theme.of(context)
                                            .textTheme
                                            .titleMedium),
                                    const SizedBox(height: 6),
                                    LocalizedText(
                                        '${ledgerDate(r.createdAt)} · ${requestStatus(r.status, _english)} · ${r.buyer}'),
                                    LocalizedText(
                                        '${t('단가 입력분', 'Entered-price subtotal')}: ${r.currency} ${r.amount} · ${t('견적 대기', 'Unpriced')} ${r.unpricedCount}'),
                                    if (r.deliveryDate.isNotEmpty)
                                      LocalizedText(
                                          '${t('희망 납품일', 'Delivery date')}: ${r.deliveryDate}'),
                                    SelectableText(r.reference,
                                        style: Theme.of(context)
                                            .textTheme
                                            .bodySmall),
                                    Wrap(spacing: 8, children: [
                                      TextButton.icon(
                                          onPressed:
                                              _working ? null : () => _open(r),
                                          icon: const Icon(
                                              Icons.description_outlined),
                                          label: Text(
                                              t('요청서 열기', 'Open request'))),
                                      TextButton.icon(
                                          onPressed: _working
                                              ? null
                                              : () => _events(r),
                                          icon: const Icon(Icons.history),
                                          label: Text(t('처리 이력', 'Activity')))
                                    ]),
                                  ]))),
                    if (_rows.length < _data!.totalCount)
                      TextButton(
                          onPressed: _loading || _working
                              ? null
                              : () => _load(more: true),
                          child: Text(t('더 보기', 'Load more'))),
                  ],
                ]))),
      );
}
