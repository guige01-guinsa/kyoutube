part of 'business_pages.dart';

class MealPurchaseSelection {
  MealPurchaseSelection(this.meals);
  final List<BusinessMeal> meals;
}

class BusinessMenuFastPage extends ConsumerWidget {
  const BusinessMenuFastPage(
      {super.key, required this.workspace, this.mealSources});
  final MealPurchaseSelection? mealSources;
  final String workspace;
  @override
  Widget build(BuildContext context, WidgetRef ref) => ref
      .watch(businessContextProvider(workspace))
      .when(
        loading: () =>
            const Scaffold(body: Center(child: CircularProgressIndicator())),
        error: (e, _) => Scaffold(
            appBar: AppBar(),
            body: _BusinessError(
                e, () => ref.invalidate(businessContextProvider(workspace)))),
        data: (b) => _MenuFastForm(
            key: ValueKey('${ref.watch(activeAccountIdProvider)}:$workspace'),
            business: b,
            selection: mealSources),
      );
}

class _MenuFastForm extends ConsumerStatefulWidget {
  const _MenuFastForm({super.key, required this.business, this.selection});
  final MealPurchaseSelection? selection;
  final BusinessContext business;
  @override
  ConsumerState<_MenuFastForm> createState() => _MenuFastFormState();
}

class _MenuFastFormState extends ConsumerState<_MenuFastForm> {
  final _quantities = <String, TextEditingController>{};
  final _delivery = TextEditingController(
      text: DateFormat('yyyy-MM-dd').format(DateTime.now()));
  final _selected = <String>{};
  final _coupang = <String, CoupangPurchasePlan>{};
  late final String? _account = ref.read(activeAccountIdProvider);
  String _token = newShoppingId();
  Map<String, dynamic>? _preview, _result, _pending;
  String? _error;
  Map<String, dynamic>? _editingPlan;
  bool _busy = false, _useStock = true, _confirmed = false;
  bool get _current =>
      mounted &&
      _account != null &&
      _account == ref.read(activeAccountIdProvider);
  bool get _locked => _busy || _pending != null || _result != null;
  String get _workspace => widget.business.id;
  BusinessMenuFastRepository get _repo =>
      ref.read(businessMenuFastRepositoryProvider);
  @override
  void initState() {
    super.initState();
    if (widget.selection != null) {
      _selected.addAll(widget.selection!.meals.map((m) => m.id));
    }
  }

  String get _title => widget.selection == null
      ? bt(context, '판매 메뉴로 빠른 구매', 'Quick purchase from menus')
      : bt(context, '확정 식단 구매 준비', 'Purchase from confirmed meals');
  @override
  void dispose() {
    _delivery.dispose();
    for (final c in _quantities.values) {
      c.dispose();
    }
    super.dispose();
  }

  void _invalidate() {
    _coupang.clear();
    _preview = null;
    _confirmed = false;
    _error = null;
  }

  List<Map<String, dynamic>> _sources(List<BusinessMenuItem> menus) =>
      widget.selection != null
          ? widget.selection!.meals.map((m) => m.purchaseSource).toList()
          : [
              for (final m in menus.where((m) => _selected.contains(m.id)))
                {
                  'kind': 'menu',
                  'id': m.id,
                  'revision': m.revision,
                  'servings':
                      parseUserNumber(_quantities[m.id]?.text.trim() ?? '')
                }
            ];
  Future<void> _calculate(List<BusinessMenuItem> menus) async {
    final sources = _sources(menus);
    if (sources.isEmpty ||
        sources.length > 20 ||
        sources.any((s) {
          final n = (s['servings'] as num?)?.toDouble();
          return n == null || !menuQuantityValid(n) || n < .001 || n > 100000;
        })) {
      setState(() => _error = bt(context, '메뉴 1~20개와 올바른 인분을 입력하세요.',
          'Select 1–20 menus with valid servings.'));
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
      _confirmed = false;
    });
    try {
      final result = await _repo.preview(_workspace, sources, _useStock);
      if (_current) {
        setState(() {
          _preview = result;
          _coupang.clear();
        });
      }
    } catch (e) {
      if (_current) setState(() => _error = businessError(context, e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _mapping(
      Map<String, dynamic> row, List<BusinessMenuItem> menus) async {
    final saved = await showDialog<bool>(
        context: context,
        barrierDismissible: false,
        builder: (_) => ShoppingAccountGuard(
            child: _MenuDefaultEditor(workspace: _workspace, row: row)));
    if (_current && saved == true) await _calculate(menus);
  }

  Future<void> _loadPlan(List<BusinessMenuItem> menus,
      {required bool recent}) async {
    if (_locked) return;
    setState(() => _busy = true);
    try {
      final rows =
          recent ? await _repo.recent(_workspace) : <Map<String, dynamic>>[];
      if (!mounted || !_current) return;
      setState(() => _busy = false);
      final chosen = await showDialog<Map<String, dynamic>>(
          context: context,
          builder: (_) => ShoppingAccountGuard(
              child: recent
                  ? BusinessSupplierChoice<Map<String, dynamic>>(
                      title: bt(context, '구매 계획 불러오기', 'Load a menu plan'),
                      future: Future.value(rows),
                      label: (r) => '${r['delivery_date']}',
                      detail: (r) =>
                          '${(r['sources'] as List).length} ${bt(context, '개 메뉴', 'menus')}',
                    )
                  : _SavedPlanManager(_workspace,
                      canWrite: widget.business.can('purchasing.write'))));
      if (!_current || chosen == null) return;
      final sources =
          List<Map<String, dynamic>>.from(chosen['sources'] as List);
      final current = {for (final m in menus) m.id: m};
      if (sources.any((s) =>
          current[s['id']] == null ||
          current[s['id']]!.revision != s['revision'])) {
        setState(() {
          if (!recent && chosen['_edit'] == true) {
            _editingPlan = chosen;
            _selected.clear();
            _invalidate();
          }
          _error = bt(
              context,
              '저장된 계획의 메뉴가 변경·중지되었습니다. 현재 판매 메뉴와 인분을 다시 선택하세요.',
              'A saved menu changed or stopped. Select current menus and servings again.');
        });
        return;
      }
      setState(() {
        _editingPlan = !recent && chosen['_edit'] == true ? chosen : null;
        _selected.clear();
        for (final s in sources) {
          final id = s['id'] as String;
          _selected.add(id);
          _quantities.putIfAbsent(id, () => TextEditingController()).text =
              menuNumber(s['servings'] as num);
        }
        _invalidate();
      });
      if (chosen['_copy'] == true) {
        // Copy current, validated sources under a new identity.
        setState(() => _busy = false);
        await _template(menus,
            copy: true, initialName: '${chosen['name']} (2)');
      }
    } catch (e) {
      if (_current) setState(() => _error = businessError(context, e));
    } finally {
      if (_current) setState(() => _busy = false);
    }
  }

  Future<void> _template(List<BusinessMenuItem> menus,
      {bool copy = false, String? initialName}) async {
    if (_locked) return;
    final editing = copy ? null : _editingPlan;
    final name = await _menuPlanName(context,
        bt(context, '계획 이름 (예: 월요일 점심)', 'Plan name (e.g. Monday lunch)'),
        initial: initialName ?? editing?['name'] as String? ?? '');
    if (!_current || name == null || name.trim().isEmpty) return;
    setState(() => _busy = true);
    try {
      if (editing == null) {
        await _repo.saveTemplate(
            _workspace, newShoppingId(), name.trim(), _sources(menus));
      } else {
        await _repo.updateTemplate(_workspace, editing['id'] as String,
            (editing['revision'] as num).toInt(), name.trim(), _sources(menus));
      }
      if (mounted && _current) {
        setState(() => _editingPlan = null);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(bt(context, '구매 계획을 저장했습니다.', 'Menu plan saved.'))));
      }
    } catch (e) {
      if (_current) setState(() => _error = businessError(context, e));
    } finally {
      if (_current) setState(() => _busy = false);
    }
  }

  Future<void> _create(List<BusinessMenuItem> menus) async {
    if (_pending == null) {
      final date = DateTime.tryParse(_delivery.text.trim());
      if (date == null ||
          DateFormat('yyyy-MM-dd').format(date) != _delivery.text.trim()) {
        setState(() => _error = bt(context, '납품일을 YYYY-MM-DD로 입력하세요.',
            'Enter delivery as YYYY-MM-DD.'));
        return;
      }
      if (!_confirmed || _preview == null) return;
      _pending = {
        'p_workspace': _workspace,
        'p_id': _token,
        'p_sources': _sources(menus),
        'p_use_stock': _useStock,
        'p_preview': _preview!['fingerprint'],
        'p_delivery': _delivery.text.trim(),
        'p_confirmed': true,
        if (_coupang.isNotEmpty)
          'p_choices': _coupang.map((k, v) => MapEntry(k, v.toJson())),
      };
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final result = await _repo.create(_pending!);
      if (_current) {
        ref.invalidate(businessRecordsProvider);
        setState(() {
          _result = result;
          ref.invalidate(businessMealLinksProvider(_workspace));
          _pending = null;
        });
      }
    } on PostgrestException catch (e) {
      if (_current) {
        setState(() {
          _error = businessError(context, e);
          // Only explicit transactional validation failures clear the retry identity.
          if (RegExp(r'^(FAST_|BUSINESS_|MENU_|MEAL_|SUPPLIER_|INVENTORY_)')
                  .hasMatch(e.message) ||
              ['23514', '22P02', '22003'].contains(e.code)) {
            _pending = null;
            _token = newShoppingId();
            _preview = null;
            _confirmed = false;
          }
        });
      }
    } catch (e) {
      if (_current) {
        setState(() => _error = bt(
            context,
            '응답을 확인하지 못했습니다. 같은 요청 재확인으로 중복 생성을 방지하세요.',
            'Response uncertain. Retry the same request to avoid duplicates.'));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final b = widget.business;
    if (!_current ||
        !b.can('recipes.read') ||
        !b.can('purchasing.read') ||
        !b.can('purchasing.write')) {
      return Scaffold(
          appBar: AppBar(),
          body: Text(businessError(context, StateError('BUSINESS_DENIED'))));
    }
    return WorkspaceEditGuard(
        dirty: _result == null && _selected.isNotEmpty,
        busy: _busy,
        confirmLeave: () => confirmWorkspaceDiscard(context),
        child: Scaffold(
          appBar: AppBar(title: Text(_title)),
          bottomNavigationBar: b.isTest
              ? null
              : CoupangDisclosureFooter(ingredients: [
                  for (final row in _preview?['rows'] as List? ?? [])
                    if ((row['required'] as num) > (row['stock'] as num))
                      row['name'] as String
                ], hasSelection: _coupang.isNotEmpty),
          body: Center(
              child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 980),
                  child: (widget.selection != null
                          ? const AsyncData<List<BusinessMenuItem>>([])
                          : ref.watch(businessMenusProvider(_workspace)))
                      .when(
                    loading: () => const LinearProgressIndicator(),
                    error: (e, _) => _BusinessError(
                        e,
                        () =>
                            ref.invalidate(businessMenusProvider(_workspace))),
                    data: (all) {
                      final menus =
                          all.where((m) => m.status == 'on_sale').toList();
                      final rows = List<Map<String, dynamic>>.from(
                          _preview?['rows'] as List? ?? []);
                      return ListView(
                          padding: const EdgeInsets.all(20),
                          children: [
                            if (b.isTest) const BusinessPracticeNotice(),
                            _BusinessWorkHeader(
                                workspace: b.name,
                                title: _title,
                                subtitle: widget.selection != null
                                    ? bt(context, '선택한 식단의 확정 레시피·인분으로 계산합니다.',
                                        'Calculated from the selected meals’ frozen recipes and servings.')
                                    : bt(
                                        context,
                                        '판매 메뉴와 인분을 선택하면 재료를 합산하고 기본 구매처별 초안을 준비합니다.',
                                        'Choose active menus and servings to combine ingredients and prepare supplier drafts.'),
                                icon: Icons.playlist_add_check),
                            BusinessWorkflowSteps(
                                current: _result != null
                                    ? 2
                                    : _preview != null
                                        ? 1
                                        : 0,
                                labels: [
                                  bt(context, '메뉴·인분 선택', 'Menus & servings'),
                                  bt(context, '구매량 확인', 'Review quantities'),
                                  bt(context, '초안 준비 완료', 'Drafts prepared')
                                ]),
                            if (_result != null) ...[
                              const SizedBox(height: 16),
                              Text(bt(
                                  context,
                                  '구매 준비를 완료했습니다. 단가·납품 조건을 확인하고 승인 절차를 진행하세요.',
                                  'Preparation complete. Review prices and delivery terms, then follow the approval process.')),
                              for (final r in _result!['requests'] as List)
                                ListTile(
                                    enabled: r['deleted'] != true,
                                    subtitle: r['deleted'] == true
                                        ? Text(bt(context, '삭제된 요청서',
                                            'Deleted request'))
                                        : null,
                                    title: Text(r['supplier'] as String),
                                    trailing: const Icon(Icons.chevron_right),
                                    onTap: () => context.push(
                                        '/business-workspaces/$_workspace/edit/${r['id']}')),
                              LocalizedText(
                                  '${(_result!['reservations'] as List).length} ${bt(context, '건의 재고 예약. 조리 후 사용 기록 또는 미사용 예약 해제가 필요합니다.', 'stock reservations. Record actual use after cooking or release unused stock.')}'),
                              OutlinedButton(
                                  onPressed: () => context.push(
                                      '/business-workspaces/$_workspace/inventory'),
                                  child: Text(bt(context, '재고·예약 관리',
                                      'Manage stock / reservations'))),
                              if (widget.selection == null)
                                TextButton(
                                    onPressed: () => setState(() {
                                          _result = null;
                                          _preview = null;
                                          _confirmed = false;
                                          _token = newShoppingId();
                                        }),
                                    child: Text(bt(context, '새 구매 준비',
                                        'Start another plan'))),
                            ] else ...[
                              if (widget.selection != null) ...[
                                for (final meal in widget.selection!.meals)
                                  ListTile(
                                      title: LocalizedText(
                                          '${mealDate(meal.date)} · ${meal.slot} · ${meal.title}'),
                                      subtitle: Text(meal.dishSummary)),
                              ] else ...[
                                Wrap(spacing: 8, children: [
                                  TextButton(
                                      onPressed: _locked
                                          ? null
                                          : () =>
                                              _loadPlan(menus, recent: false),
                                      child: Text(bt(
                                          context, '요일·저장 계획', 'Saved plans'))),
                                  TextButton(
                                      onPressed: _locked
                                          ? null
                                          : () =>
                                              _loadPlan(menus, recent: true),
                                      child: Text(bt(context, '지난 구매 계획',
                                          'Recent plans'))),
                                  TextButton(
                                      onPressed: _locked || _selected.isEmpty
                                          ? null
                                          : () => _template(menus),
                                      child: Text(bt(
                                          context,
                                          _editingPlan == null
                                              ? '계획 저장'
                                              : '변경 저장',
                                          _editingPlan == null
                                              ? 'Save plan'
                                              : 'Save changes'))),
                                ]),
                                if (_editingPlan != null)
                                  Wrap(spacing: 8, children: [
                                    LocalizedText(
                                        '${bt(context, '수정 중', 'Editing')}: ${_editingPlan!['name']}'),
                                    TextButton(
                                        onPressed: _locked
                                            ? null
                                            : () =>
                                                _template(menus, copy: true),
                                        child: Text(bt(context, '다른 계획으로 저장',
                                            'Save as another plan'))),
                                    TextButton(
                                        onPressed: _locked
                                            ? null
                                            : () => setState(
                                                () => _editingPlan = null),
                                        child: Text(bt(context, '수정 연결 해제',
                                            'Stop editing saved plan'))),
                                  ]),
                                if (menus.isEmpty)
                                  Text(bt(
                                      context,
                                      '판매 중인 메뉴가 없습니다. 메뉴판 관리에서 판매 상태를 확인하세요.',
                                      'No active menus. Review their selling state in menu management.')),
                                if (menus.isEmpty)
                                  TextButton(
                                      onPressed: () async {
                                        await context.push(
                                            '/business-workspaces/$_workspace/menus');
                                        if (!mounted) return;
                                        ref.invalidate(
                                            businessMenusProvider(_workspace));
                                      },
                                      child: Text(bt(context, '판매 메뉴 설정',
                                          'Set up selling menus'))),
                                ScoutSectionLabel(
                                    number: '01',
                                    title: bt(
                                        context,
                                        '판매 메뉴 ${_selected.length}개 선택',
                                        '${_selected.length} selling menus selected')),
                                for (final m in menus)
                                  Card(
                                      child: Padding(
                                          padding: const EdgeInsets.all(10),
                                          child: Column(children: [
                                            CheckboxListTile(
                                                contentPadding: EdgeInsets.zero,
                                                title: Text(m.name),
                                                subtitle: LocalizedText(
                                                    '${m.snapshot['title']} v${m.recipeRevision}'),
                                                value: _selected.contains(m.id),
                                                onChanged: _locked
                                                    ? null
                                                    : (v) => setState(() {
                                                          if (v == true) {
                                                            _selected.add(m.id);
                                                          } else {
                                                            _selected
                                                                .remove(m.id);
                                                          }
                                                          _invalidate();
                                                        })),
                                            if (_selected.contains(m.id))
                                              TextField(
                                                  key: ValueKey(
                                                      'fast-servings-${m.id}'),
                                                  enabled: !_locked,
                                                  controller:
                                                      _quantities.putIfAbsent(
                                                          m.id,
                                                          () =>
                                                              TextEditingController(
                                                                  text: '1')),
                                                  keyboardType:
                                                      const TextInputType
                                                          .numberWithOptions(
                                                          decimal: true),
                                                  decoration: InputDecoration(
                                                      labelText: bt(
                                                          context,
                                                          '준비 인분',
                                                          'Servings to prepare')),
                                                  onChanged: (_) =>
                                                      setState(_invalidate)),
                                          ]))),
                              ],
                              ScoutSectionLabel(
                                  number: '02',
                                  title: bt(context, '납품일·재고 반영',
                                      'Delivery date & available stock')),
                              TextField(
                                  controller: _delivery,
                                  enabled: !_locked,
                                  decoration: InputDecoration(
                                      labelText: bt(
                                          context,
                                          '납품 희망일 (YYYY-MM-DD)',
                                          'Requested delivery (YYYY-MM-DD)'))),
                              SwitchListTile(
                                  contentPadding: EdgeInsets.zero,
                                  value: _useStock,
                                  onChanged: _locked
                                      ? null
                                      : (v) => setState(() {
                                            _useStock = v;
                                            _invalidate();
                                          }),
                                  title: Text(bt(
                                      context,
                                      '연결한 재고의 사용 가능량 반영·예약',
                                      'Use and reserve linked available stock'))),
                              Text(bt(
                                  context,
                                  '입고 예정량은 자동 차감하지 않습니다. 진행 중 요청을 확인하고 중복 계획은 조정하세요. 재고 연결이 없으면 재고를 차감하지 않습니다.',
                                  'Incoming quantities are not automatically deducted. Check open requests and adjust overlapping plans. Unlinked stock is not deducted.')),
                              FilledButton(
                                  onPressed: _locked || _selected.isEmpty
                                      ? null
                                      : () => _calculate(menus),
                                  child: Text(bt(context, '재료·구매량 계산',
                                      'Calculate ingredients and purchases'))),
                              if (rows.isNotEmpty)
                                ScoutSectionLabel(
                                    number: '03',
                                    title: bt(context, '구매 기준·수량 확인',
                                        'Review purchase defaults & quantities')),
                              if (rows.isNotEmpty)
                                BusinessIngredientReview<Map<String, dynamic>>(
                                    items: rows,
                                    name: (row) => row['name'] as String,
                                    needsReview: (row) =>
                                        row['ready'] != true &&
                                        !_coupang.containsKey(row['key']),
                                    builder: (row) => Card(
                                        key: ValueKey(
                                            'fast-ingredient-${row['key']}'),
                                        child: Padding(
                                            padding: const EdgeInsets.all(14),
                                            child: Column(
                                                crossAxisAlignment:
                                                    CrossAxisAlignment.start,
                                                children: [
                                                  LocalizedText(
                                                      '${row['name']} ${row['spec']}',
                                                      style: Theme.of(context)
                                                          .textTheme
                                                          .titleMedium),
                                                  LocalizedText(
                                                      '${bt(context, '필요량', 'Required')}: ${menuNumber(row['required'] as num)} ${row['unit']} · ${bt(context, '재고 사용', 'From stock')}: ${menuNumber(row['stock'] as num)} ${row['unit']}'),
                                                  LocalizedText(
                                                      '${bt(context, '부족량', 'Shortfall')}: ${menuNumber(((row['required'] as num) - (row['stock'] as num)).clamp(0, double.infinity))} ${row['unit']}'),
                                                  if (row['ready'] == true &&
                                                      !_coupang.containsKey(
                                                          row['key']))
                                                    LocalizedText(
                                                        '${row['supplier']['data']['name']} · ${row['product']['data']['name']}\n${menuNumber(row['pack_size'] as num)} ${row['unit']} / ${row['product']['data']['pack_unit']} → ${row['packs']} ${row['product']['data']['pack_unit']}\n${bt(context, '포장 올림 여유량', 'Pack rounding surplus')}: ${menuNumber(((row['pack_size'] as num) * (row['packs'] as num) - ((row['required'] as num) - (row['stock'] as num)).clamp(0, double.infinity)).clamp(0, double.infinity))} ${row['unit']}')
                                                  else if (!_coupang
                                                      .containsKey(row['key']))
                                                    Text(
                                                        bt(
                                                            context,
                                                            '구매 기준 미설정 또는 상품 변경 — 확인이 필요합니다.',
                                                            'Missing defaults or changed product — review required.'),
                                                        style: TextStyle(
                                                            color: Theme.of(
                                                                    context)
                                                                .colorScheme
                                                                .error)),
                                                  if (!b.isTest &&
                                                      (row['required'] as num) >
                                                          (row['stock'] as num))
                                                    CoupangPurchasePlanner(
                                                        key: ValueKey(
                                                            'fast-coupang-${row['key']}'),
                                                        ingredient: row['name']
                                                            as String,
                                                        unit: row['unit']
                                                            as String,
                                                        needed: ((row['required']
                                                                    as num) -
                                                                (row['stock']
                                                                    as num))
                                                            .toDouble(),
                                                        value: _coupang[
                                                            row['key']],
                                                        enabled: !_locked,
                                                        allowOpen: false,
                                                        onChanged: (plan) =>
                                                            setState(() {
                                                              if (plan ==
                                                                  null) {
                                                                _coupang.remove(
                                                                    row['key']);
                                                              } else {
                                                                _coupang[row[
                                                                        'key']
                                                                    as String] = plan;
                                                              }
                                                              _confirmed =
                                                                  false;
                                                            })),
                                                  if ((row['open_requests']
                                                          as num) >
                                                      0)
                                                    LocalizedText(
                                                        '${bt(context, '같은 재료의 진행 중 요청', 'Open requests for this ingredient')}: ${row['open_requests']}'),
                                                  TextButton(
                                                      onPressed: _locked
                                                          ? null
                                                          : () => _mapping(
                                                              row, menus),
                                                      child: Text(bt(
                                                          context,
                                                          '공통 구매 기준 설정·확인',
                                                          'Set / confirm purchasing defaults'))),
                                                ])))),
                              if (rows.isNotEmpty) ...[
                                TextButton(
                                    onPressed: () => context.push(
                                        '/business-workspaces/$_workspace?section=purchasing'),
                                    child: Text(bt(context, '진행 중 구매요청 확인',
                                        'Review open purchases'))),
                                CheckboxListTile(
                                    contentPadding: EdgeInsets.zero,
                                    value: _confirmed,
                                    onChanged: _locked
                                        ? null
                                        : (v) => setState(
                                            () => _confirmed = v == true),
                                    title: Text(bt(
                                        context,
                                        '구매처·규격·환산·중복 요청·재고 예약을 확인했습니다.',
                                        'I checked suppliers, packs, conversions, open requests and stock reservations.'))),
                                FilledButton(
                                    onPressed: _busy ||
                                            _pending == null &&
                                                (!_confirmed ||
                                                    rows.any((r) =>
                                                        r['ready'] != true &&
                                                        !_coupang.containsKey(
                                                            r['key'])))
                                        ? null
                                        : () => _create(menus),
                                    child: Text(_pending != null
                                        ? bt(context, '같은 요청 재확인',
                                            'Retry the same request')
                                        : bt(context, '업체별 초안 생성·재고 예약',
                                            'Create supplier drafts and reserve stock'))),
                              ],
                            ],
                            if (_busy) const LinearProgressIndicator(),
                            if (_error != null)
                              Padding(
                                  padding: const EdgeInsets.all(12),
                                  child: Text(_error!,
                                      style: TextStyle(
                                          color: Theme.of(context)
                                              .colorScheme
                                              .error))),
                          ]);
                    },
                  ))),
        ));
  }
}

class _MenuDefaultEditor extends ConsumerStatefulWidget {
  const _MenuDefaultEditor({required this.workspace, required this.row});
  final String workspace;
  final Map<String, dynamic> row;
  @override
  ConsumerState<_MenuDefaultEditor> createState() => _MenuDefaultEditorState();
}

class _MenuDefaultEditorState extends ConsumerState<_MenuDefaultEditor> {
  BusinessSupplier? _supplier;
  BusinessSupplierProduct? _product;
  String? _stock, _error;
  final _factor = TextEditingController(text: '1');
  bool _busy = false, _confirmed = false;
  bool get _validFactor {
    final n = parseUserNumber(_factor.text.trim());
    final product = _product;
    if (product == null || n == null || !menuQuantityValid(n) || n <= 0) {
      return false;
    }
    final size = businessConvertQuantity(product.contentQuantity * n,
        widget.row['unit'] as String, widget.row['unit'] as String);
    return size != null && size > 0;
  }

  late final _account = ref.read(activeAccountIdProvider);
  bool get _current => mounted && _account == ref.read(activeAccountIdProvider);
  late Future<List<BusinessStockItem>> _items =
      ref.read(businessInventoryRepositoryProvider).items(widget.workspace);
  @override
  void initState() {
    super.initState();
    final r = widget.row;
    if (r['supplier'] != null) {
      _supplier = BusinessSupplier.fromJson(
          Map<String, dynamic>.from(r['supplier'] as Map));
    }
    if (r['product'] != null) {
      _product = BusinessSupplierProduct.fromJson(
          Map<String, dynamic>.from(r['product'] as Map));
    }
    if (r['default'] != null) {
      _factor.text = menuNumber(r['default']['factor'] as num);
      _stock = r['default']['stock_id'] as String?;
    }
    if (_product != null) {
      final standard =
          businessUnitFactor(_product!.contentUnit, r['unit'] as String);
      if (standard != null) _factor.text = menuNumber(standard);
    }
  }

  @override
  void dispose() {
    _factor.dispose();
    super.dispose();
  }

  Future<void> _chooseSupplier() async {
    final s = await showDialog<BusinessSupplier>(
        context: context,
        builder: (_) => ShoppingAccountGuard(
                child: BusinessSupplierChoice<BusinessSupplier>(
              title: bt(context, '기본 구매처', 'Default supplier'),
              load: () => ref
                  .read(businessSupplierRepositoryProvider)
                  .suppliers(widget.workspace)
                  .then((v) => v.where((s) => s.active).toList()),
              onCreate: () => _createBusinessChoice<BusinessSupplier>(
                  context, ref, widget.workspace),
              createLabel: bt(context, '거래처 추가', 'Add supplier'),
              label: (s) => s.name,
              detail: (s) => '${s.data['address']}',
            )));
    if (_current && s != null) {
      setState(() {
        _supplier = s;
        _product = null;
        _confirmed = false;
      });
    }
  }

  Future<void> _chooseProduct() async {
    final p = await showDialog<BusinessSupplierProduct>(
        context: context,
        builder: (_) => ShoppingAccountGuard(
                child: BusinessSupplierChoice<BusinessSupplierProduct>(
              title: bt(context, '기본 상품·포장', 'Default product / pack'),
              load: () => ref
                  .read(businessSupplierRepositoryProvider)
                  .products(widget.workspace, _supplier!.id)
                  .then((v) => v.where((p) => p.active).toList()),
              onCreate: () => _createBusinessChoice<BusinessSupplierProduct>(
                  context, ref, widget.workspace,
                  parent: _supplier!),
              createLabel: bt(context, '상품·규격 추가', 'Add product / pack'),
              label: (p) => p.name,
              detail: (p) =>
                  '${p.spec} · ${menuNumber(p.contentQuantity)} ${p.contentUnit} / ${p.packUnit}',
            )));
    if (_current && p != null) {
      setState(() {
        _product = p;
        final factor =
            businessUnitFactor(p.contentUnit, widget.row['unit'] as String);
        _factor.text = factor == null ? '' : menuNumber(factor);
        _confirmed = false;
      });
    }
  }

  Future<void> _save() async {
    final n = parseUserNumber(_factor.text.trim());
    if (_busy ||
        !_current ||
        !_validFactor ||
        n == null ||
        !_confirmed ||
        _supplier == null) {
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final currentItems = await _items;
      if (!_current) return;
      if (_stock != null &&
          !currentItems.any((item) =>
              item.id == _stock &&
              businessUnitFactor(widget.row['unit'] as String, item.unit) !=
                  null)) {
        setState(() => _error =
            bt(context, '재고 연결을 다시 선택해 주세요.', 'Select the stock link again.'));
        return;
      }
      await ref.read(businessMenuFastRepositoryProvider).saveDefault(
          widget.workspace,
          (widget.row['default']?['revision'] as num?)?.toInt() ?? 0, {
        'ingredient': {
          for (final k in ['name', 'spec', 'unit']) k: widget.row[k]
        },
        'supplier': _supplier!.id,
        'supplier_revision': _supplier!.revision,
        'product': _product!.id,
        'product_revision': _product!.revision,
        'factor': n,
        'stock': _stock,
        'confirmed': true
      });
      if (mounted && _current) Navigator.pop(context, true);
    } catch (e) {
      if (_current) setState(() => _error = businessError(context, e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
      canPop: !_busy,
      child: AlertDialog(
          scrollable: true,
          title: LocalizedText(
              '${widget.row['name']} · ${bt(context, '공통 구매 기준', 'Purchasing defaults')}'),
          content: SizedBox(
              width: 550,
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(bt(context, '같은 재료명·규격·단위의 모든 메뉴에 재사용됩니다.',
                        'Reused by menus with the same ingredient name, specification and unit.')),
                    OutlinedButton(
                        onPressed: _busy ? null : _chooseSupplier,
                        child: Text(_supplier?.name ??
                            bt(context, '구매처 선택', 'Choose supplier'))),
                    OutlinedButton(
                        onPressed:
                            _busy || _supplier == null ? null : _chooseProduct,
                        child: Text(_product?.name ??
                            bt(context, '상품 선택', 'Choose product'))),
                    if (_product != null) ...[
                      LocalizedText(
                          '${menuNumber(_product!.contentQuantity)} ${_product!.contentUnit} / ${_product!.packUnit}'),
                      TextField(
                          controller: _factor,
                          enabled: !_busy &&
                              businessUnitFactor(_product!.contentUnit,
                                      widget.row['unit'] as String) ==
                                  null,
                          keyboardType: const TextInputType.numberWithOptions(
                              decimal: true),
                          decoration: InputDecoration(
                              labelText:
                                  '1 ${_product!.contentUnit} = ? ${widget.row['unit']}'),
                          onChanged: (_) => setState(() => _confirmed = false)),
                      Text(bt(
                          context,
                          'g↔kg, mL↔L은 표준 환산합니다. 무게↔부피·개수·포장은 실제 상품 기준을 확인해 입력하세요.',
                          'g↔kg and mL↔L use standard conversion. For weight↔volume, counts or packs, enter a verified product-specific basis.')),
                      if (parseUserNumber(_factor.text.trim())
                          case final double factor)
                        if (businessConvertQuantity(
                                _product!.contentQuantity * factor,
                                widget.row['unit'] as String,
                                widget.row['unit'] as String)
                            case final double pack)
                          LocalizedText(
                              '${bt(context, '포장 환산', 'Converted pack')}: 1 ${_product!.packUnit} = ${menuNumber(pack)} ${widget.row['unit']}'),
                    ],
                    TextButton.icon(
                        onPressed: _busy
                            ? null
                            : () async {
                                final created = await _stockDialog(
                                    context, ref, widget.workspace, 'item',
                                    source: widget.row);
                                if (!mounted || !_current || created == null) {
                                  return;
                                }
                                setState(() {
                                  _items = ref
                                      .read(businessInventoryRepositoryProvider)
                                      .items(widget.workspace);
                                  _stock = businessUnitFactor(
                                              widget.row['unit'] as String,
                                              created.unit) ==
                                          null
                                      ? null
                                      : created.id;
                                  _confirmed = false;
                                });
                              },
                        icon: const Icon(Icons.add),
                        label: Text(bt(context, '재고 품목 추가', 'Add stock item'))),
                    FutureBuilder<List<BusinessStockItem>>(
                        future: _items,
                        builder: (c, s) {
                          if (s.hasError) {
                            return TextButton(
                                onPressed: () => setState(() {
                                      _items = ref
                                          .read(
                                              businessInventoryRepositoryProvider)
                                          .items(widget.workspace);
                                    }),
                                child:
                                    Text(bt(c, '재고 다시 불러오기', 'Reload stock')));
                          }
                          if (!s.hasData) {
                            return const LinearProgressIndicator();
                          }
                          final items = s.data!
                              .where((i) =>
                                  businessUnitFactor(
                                      widget.row['unit'] as String, i.unit) !=
                                  null)
                              .toList();
                          return DropdownButtonFormField<String>(
                              isExpanded: true,
                              key: ValueKey(
                                  '${_stock}_${items.map((i) => i.id).join(',')}'),
                              initialValue: items.any((i) => i.id == _stock)
                                  ? _stock
                                  : '',
                              decoration: InputDecoration(
                                  labelText: bt(c, '재고 연결 (선택)',
                                      'Stock link (optional)')),
                              items: [
                                DropdownMenuItem(
                                    value: '',
                                    child: Text(bt(c, '연결 안 함 · 차감 없음',
                                        'No link / no stock deduction'))),
                                for (final i in items)
                                  DropdownMenuItem(
                                      value: i.id,
                                      child: LocalizedText(
                                          "${i.name} ${i.spec} · 1 ${widget.row['unit']} = ${menuNumber(businessUnitFactor(widget.row['unit'] as String, i.unit)!)} ${i.unit}",
                                          overflow: TextOverflow.ellipsis))
                              ],
                              onChanged: _busy
                                  ? null
                                  : (v) => setState(() {
                                        _stock = v == '' ? null : v;
                                        _confirmed = false;
                                      }));
                        }),
                    CheckboxListTile(
                        contentPadding: EdgeInsets.zero,
                        value: _confirmed,
                        onChanged: _busy
                            ? null
                            : (v) => setState(() => _confirmed = v == true),
                        title: Text(bt(context, '상품·재료·단위 환산과 재고 연결이 맞습니다.',
                            'Product, ingredient, conversion and stock link are correct.'))),
                    if (_error != null)
                      Text(_error!,
                          style: TextStyle(
                              color: Theme.of(context).colorScheme.error)),
                  ])),
          actions: [
            TextButton(
                onPressed: _busy ? null : () => Navigator.pop(context),
                child: Text(bt(context, '취소', 'Cancel'))),
            FilledButton(
                onPressed: _busy || !_confirmed || !_validFactor ? null : _save,
                child: Text(bt(context, '저장', 'Save'))),
          ]));
}

Future<String?> _menuPlanName(BuildContext context, String title,
    {String initial = ''}) async {
  String value = initial;
  return showDialog<String>(
      context: context,
      builder: (ctx) => ShoppingAccountGuard(
              child: AlertDialog(
                  title: Text(title),
                  content: TextFormField(
                      initialValue: initial,
                      autofocus: true,
                      maxLength: 80,
                      onChanged: (v) => value = v),
                  actions: [
                TextButton(
                    onPressed: () => Navigator.pop(ctx),
                    child: Text(bt(ctx, '취소', 'Cancel'))),
                FilledButton(
                    onPressed: () => Navigator.pop(ctx, value.trim()),
                    child: Text(bt(ctx, '저장', 'Save')))
              ])));
}
