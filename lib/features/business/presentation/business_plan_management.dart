part of 'business_pages.dart';

/// Saved definitions only: managing a plan never mutates a previous purchase.
class _SavedPlanManager extends ConsumerStatefulWidget {
  const _SavedPlanManager(this.workspace, {required this.canWrite});
  final String workspace;
  final bool canWrite;
  @override
  ConsumerState<_SavedPlanManager> createState() => _SavedPlanManagerState();
}

class _SavedPlanManagerState extends ConsumerState<_SavedPlanManager> {
  late final _account = ref.read(activeAccountIdProvider);
  late Future<List<Map<String, dynamic>>> _rows = _load();
  String _query = '';
  String? _error;
  bool _archived = false, _busy = false;
  bool get _current => mounted && _account == ref.read(activeAccountIdProvider);
  BusinessMenuFastRepository get _repo =>
      ref.read(businessMenuFastRepositoryProvider);
  Future<List<Map<String, dynamic>>> _load() =>
      _repo.templates(widget.workspace);
  Future<void> _manage(Map<String, dynamic> row, String action) async {
    if (_busy || !_current) return;
    String? name;
    if (action == 'rename') {
      name = await _menuPlanName(
          context, bt(context, '계획 이름 변경', 'Rename plan'),
          initial: row['name'] as String);
      if (name == null || name.trim().isEmpty || !_current) return;
    } else {
      final yes = await confirmRecordManagement(
          context,
          bt(context, action == 'archive' ? '계획 보관' : '계획 복원',
              action == 'archive' ? 'Archive plan' : 'Restore plan'),
          bt(context, '저장한 계획의 표시만 변경합니다. 이미 만든 구매요청서와 재고 예약은 유지됩니다.',
              'Change only saved plan visibility. Existing purchase requests and stock reservations are preserved.'));
      if (!yes || !_current) return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await _repo.manageTemplate(widget.workspace, row['id'] as String,
          (row['revision'] as num).toInt(), action,
          name: name);
    } catch (e) {
      if (_current) setState(() => _error = businessError(context, e));
    } finally {
      if (_current) {
        setState(() {
          _busy = false;
          _rows = _load();
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
      canPop: !_busy,
      child: AlertDialog(
        title: Text(bt(context, '저장한 구매 계획 관리', 'Manage saved purchase plans')),
        content: SizedBox(
            width: 640,
            height:
                (MediaQuery.sizeOf(context).height * .5).clamp(180.0, 440.0),
            child: Column(children: [
              if (_error != null)
                Text(_error!,
                    style:
                        TextStyle(color: Theme.of(context).colorScheme.error)),
              TextField(
                  onChanged: (v) =>
                      setState(() => _query = v.trim().toLowerCase()),
                  decoration: InputDecoration(
                      labelText: bt(context, '계획 검색', 'Search plans'),
                      prefixIcon: const Icon(Icons.search))),
              SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(bt(context, '보관한 계획', 'Archived plans')),
                  value: _archived,
                  onChanged:
                      _busy ? null : (v) => setState(() => _archived = v)),
              Expanded(
                  child: FutureBuilder<List<Map<String, dynamic>>>(
                      future: _rows,
                      builder: (context, snapshot) {
                        if (snapshot.hasError) {
                          return _BusinessError(
                              snapshot.error!,
                              () => setState(() {
                                    _rows = _load();
                                  }));
                        }
                        if (!snapshot.hasData) {
                          return const Center(
                              child: CircularProgressIndicator());
                        }
                        final rows = snapshot.data!
                            .where((r) =>
                                (r['archived'] == true) == _archived &&
                                (r['name'] as String)
                                    .toLowerCase()
                                    .contains(_query))
                            .toList();
                        if (rows.isEmpty) {
                          return Center(
                              child: Text(bt(context, '저장한 계획이 없습니다.',
                                  'No saved plans.')));
                        }
                        return ListView(children: [
                          for (final row in rows)
                            Card(
                                child: Padding(
                                    padding: const EdgeInsets.all(8),
                                    child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(row['name'] as String,
                                              style: Theme.of(context)
                                                  .textTheme
                                                  .titleSmall),
                                          Wrap(
                                              spacing: 8,
                                              crossAxisAlignment:
                                                  WrapCrossAlignment.center,
                                              children: [
                                                if (!_archived)
                                                  TextButton(
                                                      onPressed: _busy
                                                          ? null
                                                          : () => Navigator.pop(
                                                                  context, {
                                                                ...row,
                                                                '_edit': false
                                                              }),
                                                      child: Text(bt(context,
                                                          '불러오기', 'Load'))),
                                                if (!_archived &&
                                                    widget.canWrite)
                                                  TextButton(
                                                      onPressed: _busy
                                                          ? null
                                                          : () => Navigator.pop(
                                                                  context, {
                                                                ...row,
                                                                '_edit': true
                                                              }),
                                                      child: Text(bt(
                                                          context,
                                                          '구성 수정',
                                                          'Edit contents'))),
                                                if (!_archived &&
                                                    widget.canWrite)
                                                  TextButton(
                                                      onPressed: _busy
                                                          ? null
                                                          : () => Navigator.pop(
                                                                  context, {
                                                                ...row,
                                                                '_copy': true
                                                              }),
                                                      child: Text(bt(
                                                          context,
                                                          '복사해서 만들기',
                                                          'Create a copy'))),
                                                if (widget.canWrite && !_busy)
                                                  RecordManagementMenu(
                                                      onError: (e) =>
                                                          businessError(
                                                              context, e),
                                                      actions: [
                                                        if (ref
                                                                .watch(businessContextProvider(
                                                                    widget
                                                                        .workspace))
                                                                .valueOrNull
                                                                ?.owner ==
                                                            true)
                                                          RecordManagementAction(
                                                              'erase',
                                                              bt(
                                                                  context,
                                                                  '영구 삭제',
                                                                  'Delete permanently'),
                                                              Icons
                                                                  .delete_forever,
                                                              () async {
                                                            if (await _eraseBusinessRecord(
                                                                    context,
                                                                    ref,
                                                                    widget
                                                                        .workspace,
                                                                    'template',
                                                                    row['id']
                                                                        as String) &&
                                                                _current) {
                                                              setState(() =>
                                                                  _rows =
                                                                      _load());
                                                            }
                                                          }),
                                                        RecordManagementAction(
                                                            'rename',
                                                            bt(context, '이름 변경',
                                                                'Rename'),
                                                            Icons.edit_outlined,
                                                            () => _manage(
                                                                row, 'rename')),
                                                        RecordManagementAction(
                                                            'archive',
                                                            bt(
                                                                context,
                                                                _archived
                                                                    ? '복원'
                                                                    : '보관',
                                                                _archived
                                                                    ? 'Restore'
                                                                    : 'Archive'),
                                                            _archived
                                                                ? Icons
                                                                    .unarchive_outlined
                                                                : Icons
                                                                    .archive_outlined,
                                                            () => _manage(
                                                                row,
                                                                _archived
                                                                    ? 'restore'
                                                                    : 'archive')),
                                                      ]),
                                              ]),
                                        ])))
                        ]);
                      })),
            ])),
        actions: [
          TextButton(
              onPressed: _busy ? null : () => Navigator.pop(context),
              child: Text(bt(context, '닫기', 'Close')))
        ],
      ));
}
