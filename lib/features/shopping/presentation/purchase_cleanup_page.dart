import '../../../core/localization/localized_text.dart';
import '../../../core/auth/auth_return.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../auth/application/auth_providers.dart';
import '../../business/data/business_repository.dart';
import '../../workspace/application/workspace_navigation.dart';
import '../data/purchase_cleanup_repository.dart';
import '../domain/purchase_cleanup.dart';
import 'shopping_assistant_dialogs.dart';

class PurchaseCleanupPage extends ConsumerWidget {
  const PurchaseCleanupPage({super.key, this.workspace, this.archived = false});
  final String? workspace;
  final bool archived;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final account = ref.watch(activeAccountIdProvider);
    String t(String ko, String en) => shopText(context, ko, en);
    if (account == null) {
      return Scaffold(
          appBar: AppBar(),
          body: Center(
              child: FilledButton(
                  onPressed: () => context.push(loginFor(GoRouterState.of(context).uri.toString(), resume: true)),
                  child: Text(t('로그인', 'Sign in')))));
    }
    Widget page({required bool manage, String? name}) => _CleanupWorkspace(
        key: ValueKey('$account:$workspace:$archived'),
        account: account,
        workspace: workspace,
        initialArchived: archived,
        canManage: manage,
        name: name);
    if (workspace == null) return page(manage: true);
    return ref.watch(businessContextProvider(workspace!)).when(
        skipLoadingOnReload: false,
        data: (business) => business.can('purchasing.read')
            ? page(
                manage: business.can('purchasing.write'), name: business.name)
            : Scaffold(
                appBar: AppBar(),
                body: Center(
                    child: Text(t('구매 기록 조회 권한이 없습니다.',
                        'Purchase access is required.')))),
        loading: () =>
            const Scaffold(body: Center(child: CircularProgressIndicator())),
        error: (_, __) => Scaffold(
            appBar: AppBar(),
            body: Center(
                child: TextButton(
                    onPressed: () =>
                        ref.invalidate(businessContextProvider(workspace!)),
                    child: Text(t('권한을 확인하지 못했습니다. 다시 시도',
                        'Could not check access. Retry'))))));
  }
}

class _CleanupWorkspace extends ConsumerStatefulWidget {
  const _CleanupWorkspace(
      {super.key,
      required this.account,
      required this.workspace,
      required this.initialArchived,
      required this.canManage,
      this.name});
  final String account;
  final String? workspace, name;
  final bool initialArchived, canManage;
  @override
  ConsumerState<_CleanupWorkspace> createState() => _CleanupWorkspaceState();
}

class _CleanupWorkspaceState extends ConsumerState<_CleanupWorkspace> {
  late String _kind =
      widget.workspace == null ? 'request' : 'business_purchase';
  late bool _archived = widget.initialArchived;
  final _query = TextEditingController();
  final _selected = <String>{};
  List<PurchaseCleanupEntry> _rows = [];
  int _days = 0, _offset = 0, _generation = 0;
  bool _loading = true, _busy = false, _more = false, _needsReload = false;
  String? _error;
  String t(String ko, String en) => shopText(context, ko, en);
  bool get _active =>
      mounted && ref.read(activeAccountIdProvider) == widget.account;
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

  Future<void> _load() async {
    if (!_active || _busy) return;
    final generation = ++_generation;
    setState(() {
      _loading = true;
      _error = null;
      _rows = [];
      _selected.clear();
      _needsReload = false;
    });
    ref.invalidate(purchaseCleanupIndexProvider(widget.workspace));
    try {
      final data = await ref.read(purchaseCleanupRepositoryProvider).list(
          workspace: widget.workspace,
          kind: _kind,
          archived: _archived,
          before: _days == 0
              ? null
              : DateTime.now().subtract(Duration(days: _days)),
          query: _query.text,
          offset: _offset);
      if (!_active || generation != _generation) return;
      setState(() {
        _rows = data.take(50).toList();
        _more = data.length > 50;
      });
    } catch (e) {
      if (_active && generation == _generation) {
        setState(() => _error = e is PurchaseCleanupUnavailable
            ? t('기록 정리 기능의 서버 준비가 아직 완료되지 않았습니다. 기존 구매 기능은 계속 사용할 수 있습니다.',
                'Record organization is not enabled on the server yet. Existing purchasing remains available.')
            : t('기록을 불러오지 못했습니다. 연결과 권한을 확인한 후 다시 시도해 주세요.',
                'Could not load records. Check access and connection, then retry.'));
      }
    } finally {
      if (_active && generation == _generation) {
        setState(() => _loading = false);
      }
    }
  }

  Future<void> _apply() async {
    if (_busy || _loading || _needsReload || !widget.canManage || !_active) {
      return;
    }
    final entries =
        _rows.where((r) => r.eligible && _selected.contains(r.id)).toList();
    if (entries.isEmpty) return;
    final confirmed = await showDialog<bool>(
        context: context,
        builder: (ctx) => ShoppingAccountGuard(
                child: AlertDialog(
                    scrollable: true,
                    title: Text(_archived
                        ? t('선택한 기록을 복원할까요?', 'Restore selected records?')
                        : t('선택한 기록을 보관할까요?', 'Archive selected records?')),
                    content: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          LocalizedText(
                              '${widget.name ?? t('개인 공간', 'Personal space')} · ${entries.length}${t('건', ' records')}'),
                          Text(t('구매 상태·금액·재고·입고 내역은 그대로 유지됩니다.',
                              'Purchase status, amounts, stock and receipts stay unchanged.')),
                          if (widget.workspace != null)
                            Text(t('업소의 공유 목록에 반영되며 실행 이력이 남습니다.',
                                'This updates the shared list and records who made the change.')),
                          const SizedBox(height: 12),
                          for (final entry in entries) LocalizedText('• ${entry.title}'),
                        ]),
                    actions: [
                  TextButton(
                      onPressed: () => Navigator.pop(ctx, false),
                      child: Text(t('취소', 'Cancel'))),
                  FilledButton(
                      key: const Key('confirm-record-cleanup'),
                      onPressed: () => Navigator.pop(ctx, true),
                      child: Text(
                          _archived ? t('복원', 'Restore') : t('보관', 'Archive')))
                ])));
    if (confirmed != true || !_active || !widget.canManage) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    var success = false;
    try {
      final changed = await ref.read(purchaseCleanupRepositoryProvider).apply(
          workspace: widget.workspace,
          kind: _kind,
          entries: entries,
          archive: !_archived);
      if (!mounted || !_active) return;
      if (changed != entries.length) throw StateError('Incomplete change');
      ref.invalidate(purchaseCleanupIndexProvider(widget.workspace));
      success = true;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(_archived
              ? t('$changed건을 복원했습니다.', 'Restored $changed records.')
              : t('$changed건을 보관했습니다. 보관함에서 복원할 수 있습니다.',
                  'Archived $changed records. Restore them from the archive.'))));
    } catch (_) {
      if (_active) {
        setState(() {
          _needsReload = true;
          _error = t(
              '처리 결과를 확인하지 못했거나 기록·권한이 변경되었습니다. 새로고침해 상태를 확인한 후 다시 선택해 주세요.',
              'The result is uncertain or records/access changed. Refresh to check the current state before selecting again.');
        });
      }
    } finally {
      if (_active) setState(() => _busy = false);
    }
    if (success && _active) await _load();
  }

  String _status(String status) => switch (status) {
        'draft' => t('작성 중', 'Draft'),
        'review' => t('승인 대기', 'Awaiting approval'),
        'approved' => t('승인 완료', 'Approved'),
        'sent' => t('전달 확인', 'Sent'),
        'accepted' => t('수락 확인', 'Accepted'),
        'received' => t('완료', 'Completed'),
        'cancelled' => t('취소', 'Cancelled'),
        _ => t('저장됨', 'Saved')
      };
  @override
  Widget build(BuildContext context) {
    final locked = _busy || _loading;
    final eligible = _rows.where((r) => r.eligible).toList();
    return WorkspaceEditGuard(
        dirty: false,
        busy: _busy,
        confirmLeave: () async => false,
        child: PopScope(
            canPop: !_busy,
            child: Scaffold(
                appBar: AppBar(
                    title: Text(t('기록 정리·보관함', 'Organize & archive')),
                    actions: [
                      IconButton(
                          tooltip: t('새로고침', 'Refresh'),
                          onPressed: locked ? null : _load,
                          icon: const Icon(Icons.refresh))
                    ]),
                body: Center(
                    child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 900),
                        child: ListView(
                            padding: const EdgeInsets.all(16),
                            children: [
                              Text(widget.name ?? t('개인 공간', 'Personal space'),
                                  style:
                                      Theme.of(context).textTheme.titleMedium),
                              Text(t(
                                  '보관하면 목록에서 숨겨집니다. 금액·재고 집계와 변경 이력은 유지되며 보관함에서 복원할 수 있습니다.',
                                  'Archive records to hide them from lists. Amounts, inventory totals and history are preserved. Restore them from the archive.')),
                              const SizedBox(height: 12),
                              Wrap(spacing: 8, children: [
                                for (final archived in [false, true])
                                  ChoiceChip(
                                      key: ValueKey('cleanup-view-$archived'),
                                      selected: _archived == archived,
                                      label: Text(archived
                                          ? t('보관함', 'Archive')
                                          : t('기록 정리', 'Organize records')),
                                      onSelected: locked
                                          ? null
                                          : (_) {
                                              _archived = archived;
                                              _offset = 0;
                                              _load();
                                            })
                              ]),
                              const SizedBox(height: 12),
                              if (widget.workspace == null)
                                DropdownButtonFormField<String>(
                                    key: const Key('cleanup-kind'),
                                    initialValue: _kind,
                                    isExpanded: true,
                                    decoration: InputDecoration(
                                        labelText: t('정리 대상', 'Record type')),
                                    items: [
                                      for (final kind in [
                                        'request',
                                        'record',
                                        'favorite',
                                        'supplier'
                                      ])
                                        DropdownMenuItem(
                                            value: kind,
                                            child: Text(switch (kind) {
                                              'request' =>
                                                t('구매요청', 'Purchase requests'),
                                              'record' => t('상품별 구매 기록',
                                                  'Item purchases'),
                                              'favorite' =>
                                                t('저장 상품', 'Saved products'),
                                              _ =>
                                                t('저장 구매처', 'Saved suppliers')
                                            }))
                                    ],
                                    onChanged: locked
                                        ? null
                                        : (v) {
                                            if (v == null) return;
                                            _kind = v;
                                            _days = 0;
                                            _offset = 0;
                                            _load();
                                          }),
                              const SizedBox(height: 12),
                              DropdownButtonFormField<int>(
                                  key: ValueKey('cleanup-period-$_kind'),
                                  initialValue: _days,
                                  isExpanded: true,
                                  decoration: InputDecoration(
                                      labelText: t('수정·기록일 기준',
                                          'Last changed / recorded')),
                                  items: [
                                    for (final days in [0, 30, 90, 180])
                                      DropdownMenuItem(
                                          value: days,
                                          child: Text(days == 0
                                              ? t('전체 기간', 'All dates')
                                              : t('$days일 이전',
                                                  'Older than $days days')))
                                  ],
                                  onChanged: locked || _kind == 'favorite'
                                      ? null
                                      : (v) {
                                          _days = v ?? 0;
                                          _offset = 0;
                                          _load();
                                        }),
                              const SizedBox(height: 12),
                              TextField(
                                  controller: _query,
                                  enabled: !locked,
                                  maxLength: 200,
                                  decoration: InputDecoration(
                                      labelText: t('이름·거래처·품목 검색',
                                          'Search name, supplier or item'),
                                      suffixIcon: IconButton(
                                          onPressed: locked
                                              ? null
                                              : () {
                                                  _offset = 0;
                                                  _load();
                                                },
                                          icon: const Icon(Icons.search))),
                                  onSubmitted: (_) {
                                    _offset = 0;
                                    _load();
                                  }),
                              if (!widget.canManage)
                                Text(t('조회만 가능합니다. 정리는 구매 관리 권한이 필요합니다.',
                                    'Read only. Purchasing write access is required to organize records.')),
                              if (_error != null) ...[
                                Text(_error!, key: const Key('cleanup-error')),
                                TextButton(
                                    onPressed: locked ? null : _load,
                                    child: Text(t('다시 불러오기', 'Reload')))
                              ],
                              if (_loading) const LinearProgressIndicator(),
                              if (!_loading && _error == null && _rows.isEmpty)
                                Text(t('조건에 맞는 기록이 없습니다.',
                                    'No matching records.')),
                              if (_rows.isNotEmpty) ...[
                                Text(t('현재 페이지 최대 50건 중 선택한 항목만 처리합니다.',
                                    'Only selected records on this page (up to 50) are changed.')),
                                Wrap(spacing: 8, children: [
                                  TextButton(
                                      onPressed: locked || !widget.canManage
                                          ? null
                                          : () => setState(() =>
                                              _selected.addAll(
                                                  eligible.map((r) => r.id))),
                                      child: Text(
                                          t('가능한 항목 선택', 'Select eligible'))),
                                  TextButton(
                                      onPressed: locked
                                          ? null
                                          : () => setState(_selected.clear),
                                      child:
                                          Text(t('선택 해제', 'Clear selection'))),
                                ]),
                                for (final row in _rows)
                                  Card(
                                      child: Column(children: [
                                    CheckboxListTile(
                                        key: ValueKey('cleanup-item-${row.id}'),
                                        value: _selected.contains(row.id),
                                        title: Text(row.title),
                                        subtitle: LocalizedText(
                                            '${_status(row.status)} · ${row.date?.toLocal().toString().substring(0, 10) ?? t('날짜 없음', 'No date')}\n${row.detail}'),
                                        onChanged: locked ||
                                                !widget.canManage ||
                                                !row.eligible
                                            ? null
                                            : (v) => setState(() {
                                                  v == true
                                                      ? _selected.add(row.id)
                                                      : _selected
                                                          .remove(row.id);
                                                })),
                                    if (!row.eligible)
                                      Padding(
                                          padding: const EdgeInsets.all(8),
                                          child: Wrap(
                                              crossAxisAlignment:
                                                  WrapCrossAlignment.center,
                                              children: [
                                                Text(t('진행 중인 요청은 보관할 수 없습니다.',
                                                    'Active requests cannot be archived.')),
                                                TextButton(
                                                    onPressed: locked
                                                        ? null
                                                        : () => context.push(widget
                                                                    .workspace ==
                                                                null
                                                            ? '/shopping?stage=active&view=requests&request=${Uri.encodeQueryComponent(row.id)}'
                                                            : '/business-workspaces/${widget.workspace}/records/${row.id}'),
                                                    child: Text(t('요청 확인',
                                                        'Review request')))
                                              ])),
                                    if (_archived && row.archivedAt != null)
                                      Padding(
                                          padding: const EdgeInsets.all(8),
                                          child: Text(t(
                                              '보관일: ${row.archivedAt!.toLocal().toString().substring(0, 16)}',
                                              'Archived: ${row.archivedAt!.toLocal().toString().substring(0, 16)}'))),
                                  ])),
                              ],
                              Wrap(
                                  spacing: 12,
                                  crossAxisAlignment: WrapCrossAlignment.center,
                                  children: [
                                    if (_offset > 0)
                                      TextButton(
                                          onPressed: locked
                                              ? null
                                              : () {
                                                  _offset -= 50;
                                                  _load();
                                                },
                                          child: Text(t('이전', 'Previous'))),
                                    LocalizedText(
                                        '${_offset ~/ 50 + 1}${t('페이지', ' page')}'),
                                    if (_more)
                                      TextButton(
                                          onPressed: locked
                                              ? null
                                              : () {
                                                  _offset += 50;
                                                  _load();
                                                },
                                          child: Text(t('다음', 'Next'))),
                                  ]),
                              FilledButton.icon(
                                  key: const Key('apply-record-cleanup'),
                                  onPressed: locked ||
                                          _needsReload ||
                                          !widget.canManage ||
                                          _selected.isEmpty
                                      ? null
                                      : _apply,
                                  icon: Icon(_archived
                                      ? Icons.restore
                                      : Icons.archive_outlined),
                                  label: Text(_archived
                                      ? t('선택 ${_selected.length}건 복원',
                                          'Restore ${_selected.length} selected')
                                      : t('선택 ${_selected.length}건 보관',
                                          'Archive ${_selected.length} selected'))),
                            ]))))));
  }
}
