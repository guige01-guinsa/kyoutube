part of 'business_pages.dart';

String _mealStatus(BuildContext c, String s) => switch (s) {
      'confirmed' => bt(c, '식단 확정', 'Confirmed'),
      'cooked' => bt(c, '조리 완료', 'Cooked'),
      _ => businessStatusLabel(c, s),
    };

class BusinessMealsPage extends ConsumerWidget {
  const BusinessMealsPage({super.key, required this.workspace});
  final String workspace;
  @override
  Widget build(BuildContext context, WidgetRef ref) =>
      ref.watch(businessContextProvider(workspace)).when(
          loading: () =>
              const Scaffold(body: Center(child: CircularProgressIndicator())),
          error: (e, _) => Scaffold(
              appBar: AppBar(),
              body: _BusinessError(
                  e, () => ref.invalidate(businessContextProvider(workspace)))),
          data: (b) => _MealCalendar(
              key: ValueKey('${ref.watch(activeAccountIdProvider)}:$workspace'),
              business: b));
}

class _MealCalendar extends ConsumerStatefulWidget {
  const _MealCalendar({super.key, required this.business});
  final BusinessContext business;
  @override
  ConsumerState<_MealCalendar> createState() => _MealCalendarState();
}

class _MealCalendarState extends ConsumerState<_MealCalendar> {
  DateTime _focus = mealDay(DateTime.now());
  String _view = 'week';
  bool _busy = false, _cancelled = false;
  String? _error;
  final _selected = <String>{};
  late final String? _account = ref.read(activeAccountIdProvider);
  bool get _current =>
      mounted &&
      _account != null &&
      _account == ref.read(activeAccountIdProvider);
  DateTime get _start => _view == 'month'
      ? DateTime(_focus.year, _focus.month)
      : _view == 'week'
          ? mealWeek(_focus)
          : _focus;
  DateTime get _end => _view == 'month'
      ? DateTime(_focus.year, _focus.month + 1, 0)
      : _view == 'week'
          ? DateTime(_start.year, _start.month, _start.day + 6)
          : _start;
  String get _workspace => widget.business.id;
  BusinessMealRepository get _repo => ref.read(businessMealRepositoryProvider);
  void _refresh() {
    ref.invalidate(businessMealsProvider);
    ref.invalidate(businessMealLinksProvider(_workspace));
    _selected.clear();
  }

  Future<void> _run(Future<void> Function() action) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await action();
      if (_current) setState(_refresh);
    } catch (e) {
      if (_current) setState(() => _error = businessError(context, e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _edit(DateTime date, [BusinessMeal? meal]) async {
    final saved = await showDialog<bool>(
        context: context,
        barrierDismissible: false,
        builder: (_) => ShoppingAccountGuard(
            child: _MealEditor(workspace: _workspace, date: date, meal: meal)));
    if (_current && saved == true) setState(_refresh);
  }

  Future<void> _transition(BusinessMeal meal, String status) async {
    final yes = await showDialog<bool>(
        context: context,
        builder: (c) => AlertDialog(
                title: Text(_mealStatus(c, status)),
                content: Text(status == 'confirmed'
                    ? bt(
                        c,
                        '표시된 레시피 버전과 인분을 확정합니다. 이후에는 직접 수정할 수 없으며, 변경이 필요하면 복사하여 새 초안으로 작성하세요.',
                        'Confirm the displayed recipe revisions and servings. To change them later, copy to a new draft.')
                    : status == 'cooked'
                        ? bt(
                            c,
                            '조리 완료로 표시합니다. 실제 재고 사용량은 재고·예약 관리에서 별도로 기록하세요.',
                            'Mark as cooked. Record actual stock usage separately in inventory.')
                        : bt(c, '이 식단을 취소할까요? 기록과 변경 이력은 보관됩니다.',
                            'Cancel this meal? Its records and history are retained.')),
                actions: [
                  TextButton(
                      onPressed: () => Navigator.pop(c, false),
                      child: Text(bt(c, '돌아가기', 'Back'))),
                  FilledButton(
                      onPressed: () => Navigator.pop(c, true),
                      child: Text(bt(c, '확인', 'Confirm')))
                ]));
    if (_current && yes == true) {
      await _run(() => _repo.transition(_workspace, meal, status));
      if (_current && status == 'cooked' && _error == null) {
        await _openBatchForMeal(meal);
      }
    }
  }

  Future<void> _openBatchForMeal(BusinessMeal meal) async {
    if (!widget.business.can('purchasing.read')) return;
    try {
      final links =
          await ref.read(businessMealRepositoryProvider).links(_workspace);
      if (!mounted || !_current) return;
      final batch = links
          .where((r) => r['meal_id'] == meal.id)
          .firstOrNull?['batch_id'] as String?;
      if (batch != null) await _openBatch(batch);
    } catch (_) {
      if (_current) {
        setState(() => _error = bt(
            context,
            '조리 완료는 저장되었습니다. 구매 준비 내역에서 예약을 다시 확인해 주세요.',
            'Cooking completion saved. Reopen preparation details to review reservations.'));
      }
    }
  }

  Future<void> _copy(DateTime from, DateTime to) async {
    final saved = await showDialog<bool>(
        context: context,
        barrierDismissible: false,
        builder: (_) => ShoppingAccountGuard(
            child: _MealCopyDialog(workspace: _workspace, from: from, to: to)));
    if (_current && saved == true) setState(_refresh);
  }

  Future<void> _details(BusinessMeal meal) async {
    final history = _repo.history(_workspace, meal.id);
    await showDialog<void>(
        context: context,
        builder: (c) => ShoppingAccountGuard(
                child: AlertDialog(
                    title: Text(meal.title),
                    content: SizedBox(
                        width: 650,
                        height: 500,
                        child: ListView(children: [
                          LocalizedText(
                              '${mealDate(meal.date)} · ${meal.slot} · ${_mealStatus(c, meal.status)}'),
                          if (meal.notes.isNotEmpty)
                            Padding(
                                padding:
                                    const EdgeInsets.symmetric(vertical: 12),
                                child: Text(meal.notes)),
                          for (final d in meal.dishes)
                            ExpansionTile(
                                title: LocalizedText(
                                    '${d['title']} · ${menuNumber(d['servings'] as num)} ${bt(c, '인분', 'servings')}'),
                                subtitle: LocalizedText(
                                    '${bt(c, '레시피 버전', 'Recipe revision')} ${d['recipe_revision']}'),
                                children: [
                                  Padding(
                                      padding: const EdgeInsets.all(12),
                                      child: LocalizedText(
                                          '${d['recipe']['data']['steps'] ?? ''}'))
                                ]),
                          const Divider(),
                          Text(bt(c, '필요 식재료', 'Required ingredients'),
                              style: Theme.of(c).textTheme.titleMedium),
                          for (final r in meal.requirements)
                            ListTile(
                                dense: true,
                                title: LocalizedText('${r['name']} ${r['spec']}'),
                                trailing: LocalizedText(
                                    '${menuNumber(r['required'] as num)} ${r['unit']}')),
                          const Divider(),
                          Text(bt(c, '변경 이력', 'Change history'),
                              style: Theme.of(c).textTheme.titleMedium),
                          FutureBuilder<List<Map<String, dynamic>>>(
                              future: history,
                              builder: (c, s) {
                                if (s.hasError) {
                                  return Text(businessError(c, s.error!));
                                }
                                if (!s.hasData) {
                                  return const LinearProgressIndicator();
                                }
                                return Column(children: [
                                  for (final h in s.data!)
                                    ExpansionTile(
                                        title: LocalizedText(
                                            'v${h['revision']} · ${_mealStatus(c, h['snapshot']['status'] as String)}'),
                                        subtitle: Text(
                                            _businessDate(c, h['created_at'])),
                                        children: [
                                          Padding(
                                              padding: const EdgeInsets.all(12),
                                              child: LocalizedText(
                                                  '${h['snapshot']['meal_date']} · ${h['snapshot']['slot']}\n${BusinessMeal(Map<String, dynamic>.from(h['snapshot'] as Map)).dishSummary}\n${h['snapshot']['notes']}'))
                                        ])
                                ]);
                              })
                        ])),
                    actions: [
                  TextButton(
                      onPressed: () => Navigator.pop(c),
                      child: Text(bt(c, '닫기', 'Close')))
                ])));
  }

  void _move(int direction) => setState(() {
        _selected.clear();
        _focus = _view == 'month'
            ? DateTime(_focus.year, _focus.month + direction)
            : DateTime(_focus.year, _focus.month,
                _focus.day + direction * (_view == 'week' ? 7 : 1));
      });
  @override
  Widget build(BuildContext context) {
    final b = widget.business;
    if (!_current || !b.can('recipes.read')) {
      return Scaffold(
          appBar: AppBar(),
          body: Text(businessError(context, StateError('BUSINESS_DENIED'))));
    }
    final meals = ref.watch(businessMealsProvider(
        (workspace: _workspace, start: _start, end: _end)));
    final canBuy = b.can('purchasing.write') && b.can('purchasing.read');
    final links = canBuy
        ? ref.watch(businessMealLinksProvider(_workspace))
        : const AsyncData<List<Map<String, dynamic>>>([]);
    final linked = {
      for (final r in links.asData?.value ?? <Map<String, dynamic>>[])
        r['meal_id'] as String: r['batch_id'] as String
    };
    return Scaffold(
        appBar: AppBar(
            title: Text(bt(context, '식단 달력', 'Meal calendar')),
            actions: [
              IconButton(
                  tooltip: bt(context, '새로고침', 'Refresh'),
                  onPressed: _busy ? null : () => setState(_refresh),
                  icon: const Icon(Icons.refresh))
            ]),
        body: Center(
            child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 1440),
                child: ListView(padding: const EdgeInsets.all(20), children: [
                  if (b.isTest) const BusinessPracticeNotice(),
                  _MealCalendarHeading(workspace: b.name),
                  const SizedBox(height: 16),
                  Wrap(
                      spacing: 8,
                      runSpacing: 10,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        for (final v in [
                          ('day', '일간', 'Day'),
                          ('week', '주간', 'Week'),
                          ('month', '월간', 'Month')
                        ])
                          ChoiceChip(
                              label: Text(bt(context, v.$2, v.$3)),
                              selected: _view == v.$1,
                              onSelected: _busy
                                  ? null
                                  : (_) => setState(() {
                                        _view = v.$1;
                                        _selected.clear();
                                      })),
                        SizedBox(
                            width: MediaQuery.sizeOf(context).width < 440
                                ? MediaQuery.sizeOf(context).width - 40
                                : 390,
                            child: Row(children: [
                              IconButton(
                                  tooltip: bt(context, '이전', 'Previous'),
                                  onPressed: _busy ? null : () => _move(-1),
                                  icon: const Icon(Icons.chevron_left)),
                              Expanded(
                                  child: OutlinedButton(
                                      onPressed: _busy
                                          ? null
                                          : () async {
                                              final d = await showDatePicker(
                                                  context: context,
                                                  initialDate: _focus,
                                                  firstDate: DateTime(2000),
                                                  lastDate:
                                                      DateTime(2100, 12, 31));
                                              if (_current && d != null) {
                                                setState(() {
                                                  _focus = d;
                                                  _selected.clear();
                                                });
                                              }
                                            },
                                      child: LocalizedText(
                                          '${mealDate(_start)} — ${mealDate(_end)}'))),
                              IconButton(
                                  tooltip: bt(context, '다음', 'Next'),
                                  onPressed: _busy ? null : () => _move(1),
                                  icon: const Icon(Icons.chevron_right)),
                            ])),
                        TextButton(
                            onPressed: _busy
                                ? null
                                : () => setState(() {
                                      _focus = mealDay(DateTime.now());
                                      _selected.clear();
                                    }),
                            child: Text(bt(context, '오늘', 'Today'))),
                        if (b.can('recipes.write'))
                          FilledButton.icon(
                              onPressed: _busy ? null : () => _edit(_focus),
                              icon: const Icon(Icons.add),
                              label: Text(bt(context, '식단 추가', 'Add meal'))),
                        if (b.can('recipes.write') && _view != 'month')
                          OutlinedButton.icon(
                              onPressed:
                                  _busy ? null : () => _copy(_start, _end),
                              icon: const Icon(Icons.copy_outlined),
                              label: Text(
                                  bt(context, '이 기간 복사', 'Copy this period'))),
                        if (b.can('recipes.write') && _view == 'week')
                          TextButton(
                              onPressed: _busy
                                  ? null
                                  : () => _copy(
                                      DateTime(_start.year, _start.month,
                                          _start.day - 7),
                                      DateTime(_start.year, _start.month,
                                          _start.day - 1)),
                              child: Text(bt(
                                  context, '지난주에서 복사', 'Copy from last week'))),
                        FilterChip(
                            label:
                                Text(bt(context, '취소 포함', 'Include cancelled')),
                            selected: _cancelled,
                            onSelected: (v) => setState(() => _cancelled = v)),
                      ]),
                  if (_busy) const LinearProgressIndicator(),
                  if (_error != null)
                    Padding(
                        padding: const EdgeInsets.all(12),
                        child: Text(_error!,
                            style: TextStyle(
                                color: Theme.of(context).colorScheme.error))),
                  if (links.hasError)
                    _BusinessError(
                        links.error!,
                        () => ref
                            .invalidate(businessMealLinksProvider(_workspace))),
                  if (canBuy)
                    Padding(
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        child: Wrap(
                            spacing: 12,
                            runSpacing: 8,
                            crossAxisAlignment: WrapCrossAlignment.center,
                            children: [
                              FilledButton.tonalIcon(
                                  onPressed: _busy ||
                                          _selected.isEmpty ||
                                          _selected.length > 20 ||
                                          !links.hasValue
                                      ? null
                                      : () {
                                          final selected =
                                              (meals.asData?.value ?? [])
                                                  .where((m) =>
                                                      _selected
                                                          .contains(m.id) &&
                                                      m.status == 'confirmed' &&
                                                      !linked.containsKey(m.id))
                                                  .toList();
                                          if (selected.length !=
                                              _selected.length) {
                                            setState(_refresh);
                                            return;
                                          }
                                          context.push(
                                              '/business-workspaces/$_workspace/menu-fast',
                                              extra: MealPurchaseSelection(
                                                  selected));
                                        },
                                  icon: const Icon(
                                      Icons.shopping_basket_outlined),
                                  label: LocalizedText(
                                      '${bt(context, '선택 식단 구매 준비', 'Prepare selected meals')} (${_selected.length}/20)')),
                              Text(bt(
                                  context,
                                  '확정된 식단을 최대 20개 선택하세요. 요청서는 검토 후 초안으로 생성됩니다.',
                                  'Select up to 20 confirmed meals. Requests are created as drafts after review.')),
                            ])),
                  meals.when(
                      loading: () =>
                          const Center(child: CircularProgressIndicator()),
                      error: (e, _) => _BusinessError(
                          e, () => ref.invalidate(businessMealsProvider)),
                      data: (all) {
                        final rows = all
                            .where((m) => _cancelled || m.status != 'cancelled')
                            .toList();
                        final days = [
                          for (var d = _start;
                              !d.isAfter(_end);
                              d = DateTime(d.year, d.month, d.day + 1))
                            d
                        ];
                        return LayoutBuilder(builder: (c, constraints) {
                          final columns = _view == 'day' ||
                                  MediaQuery.textScalerOf(c).scale(1) > 1.3
                              ? 1
                              : constraints.maxWidth >= 1200
                                  ? 4
                                  : constraints.maxWidth >= 800
                                      ? 3
                                      : constraints.maxWidth >= 520
                                          ? 2
                                          : 1;
                          final width =
                              (constraints.maxWidth - (columns - 1) * 12) /
                                  columns;
                          return Wrap(spacing: 12, runSpacing: 12, children: [
                            for (final day in days)
                              SizedBox(
                                  width: width,
                                  child: Card(
                                      shape: RoundedRectangleBorder(
                                          borderRadius:
                                              BorderRadius.circular(24),
                                          side: BorderSide(
                                              color:
                                                  day == mealDay(DateTime.now())
                                                      ? ScoutStyle.plum
                                                      : ScoutStyle.line,
                                              width:
                                                  day == mealDay(DateTime.now())
                                                      ? 1.5
                                                      : 1)),
                                      margin: EdgeInsets.zero,
                                      child: Padding(
                                          padding: const EdgeInsets.all(14),
                                          child: Column(
                                              crossAxisAlignment:
                                                  CrossAxisAlignment.start,
                                              children: [
                                                Row(children: [
                                                  Container(
                                                      width: 48,
                                                      height: 56,
                                                      alignment:
                                                          Alignment.center,
                                                      decoration: BoxDecoration(
                                                          color: day ==
                                                                  mealDay(DateTime
                                                                      .now())
                                                              ? ScoutStyle.plum
                                                              : ScoutStyle
                                                                  .peach,
                                                          borderRadius:
                                                              BorderRadius.circular(
                                                                  16)),
                                                      child: LocalizedText('${day.day}',
                                                          style: Theme.of(context)
                                                              .textTheme
                                                              .headlineSmall
                                                              ?.copyWith(
                                                                  color: day ==
                                                                          mealDay(DateTime.now())
                                                                      ? Colors.white
                                                                      : ScoutStyle.ink))),
                                                  const SizedBox(width: 12),
                                                  Expanded(
                                                      child: Text(
                                                          DateFormat.MMMEd(Localizations
                                                                      .localeOf(
                                                                          context)
                                                                  .languageCode)
                                                              .format(day),
                                                          style: Theme.of(
                                                                  context)
                                                              .textTheme
                                                              .titleMedium)),
                                                  if (b.can('recipes.write'))
                                                    IconButton(
                                                        tooltip: bt(
                                                            context,
                                                            '식단 추가',
                                                            'Add meal'),
                                                        onPressed: _busy
                                                            ? null
                                                            : () => _edit(day),
                                                        icon: const Icon(Icons
                                                            .add_circle_outline))
                                                ]),
                                                if (!rows
                                                    .any((m) => m.date == day))
                                                  Padding(
                                                      padding: const EdgeInsets
                                                          .symmetric(
                                                          vertical: 24),
                                                      child: Text(bt(
                                                          context,
                                                          '아직 식단이 없어요',
                                                          'No meals planned yet'))),
                                                for (final m in rows.where(
                                                    (m) => m.date == day)) ...[
                                                  const Divider(),
                                                  _MealStateLabel(meal: m),
                                                  const SizedBox(height: 8),
                                                  Text(m.title,
                                                      style: Theme.of(context)
                                                          .textTheme
                                                          .titleMedium),
                                                  const SizedBox(height: 6),
                                                  for (final dish in m.dishes)
                                                    Padding(
                                                        padding:
                                                            const EdgeInsets
                                                                .only(
                                                                bottom: 4),
                                                        child: LocalizedText(
                                                            '${dish['title']} · ${menuNumber(dish['servings'] as num)} ${bt(context, '인분', 'servings')}',
                                                            style: Theme.of(
                                                                    context)
                                                                .textTheme
                                                                .bodyMedium
                                                                ?.copyWith(
                                                                    color: ScoutStyle
                                                                        .muted))),
                                                  if (canBuy &&
                                                      m.status == 'confirmed' &&
                                                      !linked.containsKey(m.id))
                                                    CheckboxListTile(
                                                        contentPadding:
                                                            EdgeInsets.zero,
                                                        title: Text(bt(
                                                            context,
                                                            '구매 준비에 포함',
                                                            'Include in purchase')),
                                                        value: _selected
                                                            .contains(m.id),
                                                        onChanged: _busy ||
                                                                !links.hasValue
                                                            ? null
                                                            : (v) =>
                                                                setState(() {
                                                                  if (v ==
                                                                      true) {
                                                                    _selected
                                                                        .add(m
                                                                            .id);
                                                                  } else {
                                                                    _selected
                                                                        .remove(
                                                                            m.id);
                                                                  }
                                                                })),
                                                  if (linked.containsKey(m.id))
                                                    TextButton.icon(
                                                        onPressed: _busy
                                                            ? null
                                                            : () => _openBatch(
                                                                linked[m.id]!),
                                                        icon: const Icon(Icons
                                                            .receipt_long_outlined),
                                                        label: Text(bt(
                                                            context,
                                                            '구매 준비 내역',
                                                            'Purchase preparation'))),
                                                  Wrap(
                                                      spacing: 4,
                                                      runSpacing: 4,
                                                      children: [
                                                        TextButton(
                                                            onPressed: () =>
                                                                _details(m),
                                                            child: Text(bt(
                                                                context,
                                                                '상세·이력',
                                                                'Details & history'))),
                                                        if (m.status ==
                                                                'draft' &&
                                                            b.can(
                                                                'recipes.write'))
                                                          TextButton(
                                                              onPressed: _busy
                                                                  ? null
                                                                  : () => _edit(
                                                                      m.date,
                                                                      m),
                                                              child: Text(bt(
                                                                  context,
                                                                  '수정',
                                                                  'Edit'))),
                                                        if (m.status ==
                                                                'draft' &&
                                                            b.can(
                                                                'menus.approve'))
                                                          TextButton(
                                                              onPressed: _busy
                                                                  ? null
                                                                  : () => _transition(
                                                                      m,
                                                                      'confirmed'),
                                                              child: Text(bt(
                                                                  context,
                                                                  '식단 확정',
                                                                  'Confirmed'))),
                                                        if (m.status ==
                                                                'confirmed' &&
                                                            b.can(
                                                                'recipes.write'))
                                                          TextButton(
                                                              onPressed: _busy
                                                                  ? null
                                                                  : () => _transition(
                                                                      m,
                                                                      'cooked'),
                                                              child: Text(bt(
                                                                  context,
                                                                  '조리 완료',
                                                                  'Cooked'))),
                                                        if ((m.status ==
                                                                    'draft' &&
                                                                b.can(
                                                                    'recipes.write')) ||
                                                            (m.status ==
                                                                    'confirmed' &&
                                                                b.can(
                                                                    'menus.approve') &&
                                                                !linked
                                                                    .containsKey(
                                                                        m.id)))
                                                          TextButton(
                                                              onPressed: _busy
                                                                  ? null
                                                                  : () => _transition(
                                                                      m,
                                                                      'cancelled'),
                                                              child: Text(bt(
                                                                  context,
                                                                  '취소',
                                                                  'Cancel'))),
                                                      ]),
                                                ]
                                              ]))))
                          ]);
                        });
                      }),
                  const SizedBox(height: 20),
                  TextButton(
                      onPressed: () => context.push(
                          '/business-workspaces/$_workspace?section=recipes'),
                      child: Text(bt(context, '기존 식단 기록·공동 레시피',
                          'Previous meal records & team recipes'))),
                ]))));
  }

  Future<void> _openBatch(String id) async {
    await _run(() async {
      final rows = await ref
          .read(businessMenuFastRepositoryProvider)
          .batch(_workspace, id);
      final stock =
          await ref.read(businessInventoryRepositoryProvider).items(_workspace);
      if (!mounted || !_current) return;
      await showDialog<void>(
          context: context,
          builder: (c) => ShoppingAccountGuard(
                  child: AlertDialog(
                      title: Text(bt(c, '구매 준비 내역', 'Purchase preparation')),
                      content: SizedBox(
                          width: 500,
                          child: SingleChildScrollView(
                              child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                for (final r in rows['requests'] as List)
                                  ListTile(
                                      enabled: r['deleted'] != true,
                                      subtitle: r['deleted'] == true
                                          ? Text(bt(context, '삭제된 요청서',
                                              'Deleted request'))
                                          : null,
                                      title: Text(r['supplier'] as String),
                                      trailing: const Icon(Icons.chevron_right),
                                      onTap: () {
                                        Navigator.pop(c);
                                        context.push(
                                            '/business-workspaces/$_workspace/edit/${r['id']}');
                                      }),
                                for (final reservation
                                    in rows['reservations'] as List? ?? [])
                                  ListTile(
                                      title: Text(stock
                                              .where((i) =>
                                                  i.id == reservation['item'])
                                              .firstOrNull
                                              ?.label ??
                                          bt(c, '재고 품목', 'Stock item')),
                                      subtitle: Text(bt(c, '실제 사용 기록·남은 예약 해제',
                                          'Record actual use / release remaining reservation')),
                                      onTap: () async {
                                        await c.push(
                                            '/business-workspaces/$_workspace/inventory/${reservation['item']}');
                                      }),
                                Text(bt(c, '재고 예약과 실제 사용량은 재고·예약 관리에서 확인하세요.',
                                    'Review reservations and actual usage in inventory.')),
                                TextButton(
                                    onPressed: () {
                                      Navigator.pop(c);
                                      context.push(
                                          '/business-workspaces/$_workspace/inventory');
                                    },
                                    child: Text(bt(c, '재고·예약 관리',
                                        'Manage stock / reservations')))
                              ]))),
                      actions: [
                    TextButton(
                        onPressed: () => Navigator.pop(c),
                        child: Text(bt(c, '닫기', 'Close')))
                  ])));
    });
  }
}

class _MealEditor extends ConsumerStatefulWidget {
  const _MealEditor({required this.workspace, required this.date, this.meal});
  final String workspace;
  final DateTime date;
  final BusinessMeal? meal;
  @override
  ConsumerState<_MealEditor> createState() => _MealEditorState();
}

class _MealEditorState extends ConsumerState<_MealEditor> {
  final _form = GlobalKey<FormState>();
  late final _title = TextEditingController(text: widget.meal?.title ?? '');
  late final _slot = TextEditingController(text: widget.meal?.slot ?? '');
  late final _notes = TextEditingController(text: widget.meal?.notes ?? '');
  late DateTime _date = widget.date;
  late final String _id = widget.meal?.id ?? newShoppingId();
  late final String? _account = ref.read(activeAccountIdProvider);
  late final List<Map<String, dynamic>> _sources = [
    for (final d in widget.meal?.dishes ?? <Map<String, dynamic>>[])
      Map<String, dynamic>.from(d)
  ];
  final _quantities = <String, TextEditingController>{};
  Map<String, dynamic>? _pending;
  bool _busy = false;
  String? _error;
  bool get _current =>
      mounted &&
      _account != null &&
      _account == ref.read(activeAccountIdProvider);
  bool get _locked => _busy || _pending != null;
  String _key(Map<String, dynamic> s) => '${s['kind']}:${s['id']}';
  TextEditingController _quantity(Map<String, dynamic> s) =>
      _quantities.putIfAbsent(_key(s),
          () => TextEditingController(text: menuNumber(s['servings'] as num)));
  @override
  void dispose() {
    _title.dispose();
    _slot.dispose();
    _notes.dispose();
    for (final c in _quantities.values) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _pick(bool menu) async {
    Map<String, dynamic>? source;
    if (menu) {
      final m = await showDialog<BusinessMenuItem>(
          context: context,
          builder: (_) => ShoppingAccountGuard(
              child: BusinessSupplierChoice<BusinessMenuItem>(
                  title: bt(context, '판매 메뉴 선택', 'Select selling menu'),
                  createLabel: bt(context, '판매 메뉴 설정', 'Set up selling menus'),
                  onCreate: () async {
                    await context
                        .push('/business-workspaces/${widget.workspace}/menus');
                    return null;
                  },
                  load: () => ref
                      .read(businessMenuRepositoryProvider)
                      .menus(widget.workspace)
                      .then((v) =>
                          v.where((m) => m.status == 'on_sale').toList()),
                  label: (m) => m.name,
                  detail: (m) =>
                      '${m.snapshot['title']} v${m.recipeRevision}')));
      if (m != null) {
        source = {
          'kind': 'menu',
          'id': m.id,
          'revision': m.revision,
          'title': m.name,
          'servings': 1,
          'recipe_revision': m.recipeRevision
        };
      }
    } else {
      final r = await showDialog<Map<String, dynamic>>(
          context: context,
          builder: (_) => ShoppingAccountGuard(
              child: _MealRecipePicker(workspace: widget.workspace)));
      if (r != null) {
        source = {
          'kind': 'recipe',
          'id': r['id'],
          'revision': r['revision'],
          'title': r['title'],
          'servings': 1,
          'recipe_revision': r['revision']
        };
      }
    }
    if (!_current || source == null) return;
    if (_sources.any((s) => _key(s) == _key(source!))) return;
    setState(() => _sources.add(source!));
  }

  Future<void> _save() async {
    if (_pending == null) {
      if (!_form.currentState!.validate() || _sources.isEmpty) return;
      _pending = {
        'p_workspace': widget.workspace,
        'p_id': _id,
        'p_revision': widget.meal?.revision ?? 0,
        'p_date': mealDate(_date),
        'p_slot': _slot.text.trim(),
        'p_title': _title.text.trim(),
        'p_notes': _notes.text.trim(),
        'p_sources': [
          for (final s in _sources)
            {
              'kind': s['kind'],
              'id': s['id'],
              'revision': s['revision'],
              'servings': double.parse(_quantity(s).text.trim())
            }
        ]
      };
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref.read(businessMealRepositoryProvider).save(_pending!);
      if (mounted && _current) {
        Navigator.pop(context, true);
      }
    } on PostgrestException catch (e) {
      if (_current) {
        setState(() {
          _error = businessError(context, e);
          _pending = null;
        });
      }
    } catch (e) {
      if (_current) {
        setState(() => _error = bt(
            context,
            '응답을 확인하지 못했습니다. 같은 내용으로 다시 저장해 주세요.',
            'Response uncertain. Retry saving the same content.'));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
      canPop: !_locked,
      child: Dialog(
          child: SizedBox(
              width: 700,
              height: MediaQuery.sizeOf(context).height * .9,
              child: Column(children: [
                Padding(
                    padding: const EdgeInsets.all(16),
                    child: Row(children: [
                      Expanded(
                          child: Text(bt(context, '식단 작성', 'Plan a meal'),
                              style: Theme.of(context).textTheme.titleLarge)),
                      IconButton(
                          onPressed:
                              _locked ? null : () => Navigator.pop(context),
                          icon: const Icon(Icons.close),
                          tooltip: bt(context, '닫기', 'Close'))
                    ])),
                Expanded(
                    child: Form(
                        key: _form,
                        child: ListView(
                            padding: const EdgeInsets.symmetric(horizontal: 20),
                            children: [
                              OutlinedButton.icon(
                                  onPressed: _locked
                                      ? null
                                      : () async {
                                          final d = await showDatePicker(
                                              context: context,
                                              initialDate: _date,
                                              firstDate: DateTime(2000),
                                              lastDate: DateTime(2100, 12, 31));
                                          if (_current && d != null) {
                                            setState(() => _date = d);
                                          }
                                        },
                                  icon: const Icon(Icons.event_outlined),
                                  label: Text(mealDate(_date))),
                              const SizedBox(height: 12),
                              Wrap(spacing: 8, children: [
                                for (final s in [
                                  ('아침', 'Breakfast'),
                                  ('점심', 'Lunch'),
                                  ('저녁', 'Dinner'),
                                  ('간식', 'Snack')
                                ])
                                  ActionChip(
                                      label: Text(bt(context, s.$1, s.$2)),
                                      onPressed: _locked
                                          ? null
                                          : () => setState(() => _slot.text =
                                              bt(context, s.$1, s.$2)))
                              ]),
                              TextFormField(
                                  controller: _slot,
                                  enabled: !_locked,
                                  maxLength: 40,
                                  decoration: InputDecoration(
                                      labelText: bt(context, '끼니·구분 (직접 입력 가능)',
                                          'Meal / service (custom allowed)')),
                                  validator: (v) => v == null ||
                                          v.trim().isEmpty
                                      ? bt(context, '필수 항목입니다.', 'Required.')
                                      : null),
                              TextFormField(
                                  controller: _title,
                                  enabled: !_locked,
                                  maxLength: 120,
                                  decoration: InputDecoration(
                                      labelText:
                                          bt(context, '식단 이름', 'Meal name')),
                                  validator: (v) => v == null ||
                                          v.trim().isEmpty
                                      ? bt(context, '필수 항목입니다.', 'Required.')
                                      : null),
                              Text(bt(
                                  context,
                                  '각 요리의 준비 인분을 입력하세요. 선택한 레시피 버전으로 식재료를 계산합니다.',
                                  'Enter servings for each dish. Ingredients use the selected recipe revisions.')),
                              for (final s in _sources)
                                Card(
                                    child: Padding(
                                        padding: const EdgeInsets.all(12),
                                        child: Column(children: [
                                          Row(children: [
                                            Expanded(
                                                child: LocalizedText(
                                                    '${s['title']} · v${s['recipe_revision']}')),
                                            IconButton(
                                                tooltip:
                                                    bt(context, '삭제', 'Remove'),
                                                onPressed: _locked
                                                    ? null
                                                    : () => setState(() =>
                                                        _sources.remove(s)),
                                                icon: const Icon(Icons.close))
                                          ]),
                                          TextFormField(
                                              controller: _quantity(s),
                                              enabled: !_locked,
                                              keyboardType: const TextInputType
                                                  .numberWithOptions(
                                                  decimal: true),
                                              decoration: InputDecoration(
                                                  labelText: bt(
                                                      context,
                                                      '준비 인분',
                                                      'Servings to prepare')),
                                              validator: (v) {
                                                final n =
                                                    parseUserNumber(v ?? '');
                                                return n == null ||
                                                        !menuQuantityValid(n) ||
                                                        n < .001 ||
                                                        n > 100000
                                                    ? bt(
                                                        context,
                                                        '0.001~100000 범위의 인분을 입력하세요.',
                                                        'Enter servings between 0.001 and 100000.')
                                                    : null;
                                              })
                                        ]))),
                              Wrap(spacing: 8, children: [
                                OutlinedButton.icon(
                                    onPressed: _locked || _sources.length >= 20
                                        ? null
                                        : () => _pick(false),
                                    icon: const Icon(Icons.menu_book_outlined),
                                    label: Text(bt(context, '공동 레시피 추가',
                                        'Add team recipe'))),
                                OutlinedButton.icon(
                                    onPressed: _locked || _sources.length >= 20
                                        ? null
                                        : () => _pick(true),
                                    icon: const Icon(Icons.restaurant_menu),
                                    label: Text(bt(context, '판매 메뉴 추가',
                                        'Add selling menu')))
                              ]),
                              const SizedBox(height: 12),
                              TextFormField(
                                  controller: _notes,
                                  enabled: !_locked,
                                  maxLength: 2000,
                                  maxLines: 3,
                                  decoration: InputDecoration(
                                      labelText: bt(context, '메모', 'Notes'))),
                              if (_error != null)
                                Text(_error!,
                                    style: TextStyle(
                                        color: Theme.of(context)
                                            .colorScheme
                                            .error)),
                            ]))),
                Padding(
                    padding: const EdgeInsets.all(16),
                    child: FilledButton(
                        onPressed: _busy || _sources.isEmpty ? null : _save,
                        child: Text(_busy
                            ? bt(context, '저장 중…', 'Saving…')
                            : _pending != null
                                ? bt(context, '같은 요청 재확인', 'Retry same request')
                                : bt(context, '초안 저장', 'Save draft')))),
              ]))));
}

class _MealRecipePicker extends ConsumerStatefulWidget {
  const _MealRecipePicker({required this.workspace});
  final String workspace;
  @override
  ConsumerState<_MealRecipePicker> createState() => _MealRecipePickerState();
}

class _MealRecipePickerState extends ConsumerState<_MealRecipePicker> {
  final _query = TextEditingController();
  List<Map<String, dynamic>> _rows = [];
  bool _busy = false, _more = true;
  String? _error;
  String _search = '';
  @override
  void initState() {
    super.initState();
    _load(true);
  }

  @override
  void dispose() {
    _query.dispose();
    super.dispose();
  }

  Future<void> _load(bool reset) async {
    setState(() {
      _busy = true;
      _error = null;
      if (reset) {
        _search = _query.text.trim();
        _rows = [];
      }
    });
    try {
      final r = await ref
          .read(businessMealRepositoryProvider)
          .recipes(widget.workspace, _search, _rows.length);
      if (mounted) {
        setState(() {
          _rows.addAll(r);
          _more = r.length == 50;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _error = businessError(context, e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
          title: Text(bt(context, '공동 레시피 선택', 'Select team recipe')),
          content: SizedBox(
              width: 600,
              height: 420,
              child: Column(children: [
                TextField(
                    controller: _query,
                    enabled: !_busy,
                    onSubmitted: (_) => _load(true),
                    decoration: InputDecoration(
                        labelText: bt(context, '검색', 'Search'),
                        suffixIcon: IconButton(
                            onPressed: _busy ? null : () => _load(true),
                            icon: const Icon(Icons.search)))),
                if (_busy) const LinearProgressIndicator(),
                if (_error != null) Text(_error!),
                Expanded(
                    child: ListView(children: [
                  for (final r in _rows)
                    ListTile(
                        title: Text(r['title'] as String),
                        subtitle: LocalizedText('v${r['revision']}'),
                        onTap: () => Navigator.pop(context, r)),
                  if (_rows.isEmpty && !_busy)
                    Text(bt(context, '검색 결과가 없습니다.', 'No results.')),
                  if (_more)
                    TextButton(
                        onPressed: _busy ? null : () => _load(false),
                        child: Text(bt(context, '더 보기', 'Load more')))
                ]))
              ])),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(context),
                child: Text(bt(context, '닫기', 'Close')))
          ]);
}

class _MealCopyDialog extends ConsumerStatefulWidget {
  const _MealCopyDialog(
      {required this.workspace, required this.from, required this.to});
  final String workspace;
  final DateTime from, to;
  @override
  ConsumerState<_MealCopyDialog> createState() => _MealCopyDialogState();
}

class _MealCopyDialogState extends ConsumerState<_MealCopyDialog> {
  late DateTime _target =
      DateTime(widget.from.year, widget.from.month, widget.from.day + 7);
  final _id = newShoppingId();
  bool _busy = false;
  Map<String, dynamic>? _pending;
  String? _error;
  late final _account = ref.read(activeAccountIdProvider);
  Future<void> _save() async {
    _pending ??= {
      'p_workspace': widget.workspace,
      'p_id': _id,
      'p_from': mealDate(widget.from),
      'p_to': mealDate(widget.to),
      'p_target': mealDate(_target)
    };
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref.read(businessMealRepositoryProvider).copy(_pending!);
      if (mounted && _account == ref.read(activeAccountIdProvider)) {
        Navigator.pop(context, true);
      }
    } on PostgrestException catch (e) {
      if (mounted) {
        setState(() {
          _error = businessError(context, e);
          _pending = null;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _error = bt(
            context,
            '응답을 확인하지 못했습니다. 같은 내용으로 다시 저장해 주세요.',
            'Response uncertain. Retry saving the same content.'));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
      canPop: !_busy && _pending == null,
      child: AlertDialog(
          title: Text(bt(context, '식단 복사', 'Copy meals')),
          content: SingleChildScrollView(
              child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                LocalizedText('${mealDate(widget.from)} — ${mealDate(widget.to)}'),
                const SizedBox(height: 12),
                Text(bt(
                    context,
                    '같은 요일 간격으로 새 초안을 만듭니다. 원본의 레시피 버전·인분을 유지하며, 복사할 날짜에 같은 끼니가 있으면 전체 복사를 중단합니다.',
                    'Create new drafts with the original day offsets, recipe revisions and servings. If a destination meal already exists, nothing is copied.')),
                OutlinedButton(
                    onPressed: _busy || _pending != null
                        ? null
                        : () async {
                            final d = await showDatePicker(
                                context: context,
                                initialDate: _target,
                                firstDate: DateTime(2000),
                                lastDate: DateTime(2100, 12, 25));
                            if (mounted && d != null) {
                              setState(() => _target = d);
                            }
                          },
                    child: LocalizedText(
                        '${bt(context, '복사 시작일', 'Destination start')} · ${mealDate(_target)}')),
                if (_error != null) Text(_error!)
              ])),
          actions: [
            TextButton(
                onPressed: _busy || _pending != null
                    ? null
                    : () => Navigator.pop(context),
                child: Text(bt(context, '취소', 'Cancel'))),
            FilledButton(
                onPressed: _busy ? null : _save,
                child: Text(bt(context, '복사', 'Copy')))
          ]));
}

class _MealCalendarHeading extends StatelessWidget {
  const _MealCalendarHeading({required this.workspace});
  final String workspace;
  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
            color: ScoutStyle.plum, borderRadius: BorderRadius.circular(28)),
        child: Row(children: [
          Expanded(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                Text(workspace,
                    style: Theme.of(context)
                        .textTheme
                        .labelLarge
                        ?.copyWith(color: ScoutStyle.peach)),
                const SizedBox(height: 10),
                Text(bt(context, '한 주의 식탁을 준비하세요', 'Plan the week’s table'),
                    style: Theme.of(context)
                        .textTheme
                        .headlineSmall
                        ?.copyWith(color: Colors.white)),
                const SizedBox(height: 12),
                Text(
                    bt(context, '식단 작성 → 담당자 확정 → 식재료 구매 준비',
                        'Plan meals → manager confirmation → ingredient purchasing'),
                    style: Theme.of(context)
                        .textTheme
                        .bodyMedium
                        ?.copyWith(color: Colors.white)),
              ])),
          if (MediaQuery.sizeOf(context).width >= 800) ...[
            const SizedBox(width: 32),
            const ExcludeSemantics(
                child: Icon(Icons.calendar_month_outlined,
                    size: 64, color: ScoutStyle.peach)),
          ],
        ]),
      );
}

class _MealStateLabel extends StatelessWidget {
  const _MealStateLabel({required this.meal});
  final BusinessMeal meal;
  @override
  Widget build(BuildContext context) {
    final confirmed = meal.status == 'confirmed';
    final cancelled = meal.status == 'cancelled';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
          color: cancelled
              ? Theme.of(context).colorScheme.errorContainer
              : confirmed
                  ? ScoutStyle.plum
                  : meal.status == 'cooked'
                      ? ScoutStyle.blush
                      : ScoutStyle.peach,
          borderRadius: BorderRadius.circular(10)),
      child: LocalizedText('${meal.slot} · ${_mealStatus(context, meal.status)}',
          style: Theme.of(context).textTheme.labelLarge?.copyWith(
              color: cancelled
                  ? Theme.of(context).colorScheme.onErrorContainer
                  : confirmed
                      ? Colors.white
                      : ScoutStyle.ink)),
    );
  }
}
