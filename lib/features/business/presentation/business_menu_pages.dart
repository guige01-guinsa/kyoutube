part of 'business_pages.dart';

String menuStageLabel(BuildContext c, String s) => switch (s) {
      'candidate' => bt(c, '메뉴 후보', 'Menu candidate'),
      'development' => bt(c, '개발 중', 'In development'),
      'testing' => bt(c, '시험 조리·승인 대기', 'Trial cooking / awaiting approval'),
      'approved' => bt(c, '출시 승인', 'Approved for launch'),
      'preparing' => bt(c, '출시 준비', 'Preparing launch'),
      'on_sale' => bt(c, '판매 중', 'On sale'),
      'stopped' => bt(c, '판매 중지', 'Stopped'),
      'launch' => bt(c, '출시 준비용 구매', 'Launch purchase'),
      'operations' => bt(c, '판매 메뉴 준비', 'Prepare active menus'),
      _ => s
    };

class BusinessMenuPage extends ConsumerStatefulWidget {
  const BusinessMenuPage({super.key, required this.workspace});
  final String workspace;
  @override
  ConsumerState<BusinessMenuPage> createState() => _BusinessMenuPageState();
}

class _BusinessMenuPageState extends ConsumerState<BusinessMenuPage> {
  String _query = '', _status = 'all';
  bool _preview = false;
  Future<void> _edit(BusinessContext b, [BusinessMenuItem? original]) async {
    await showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (_) => ShoppingAccountGuard(
            child: BusinessMenuEditor(business: b, original: original)));
  }

  Future<void> _history(BusinessMenuItem m) async {
    final pending = ref
        .read(businessMenuRepositoryProvider)
        .history(widget.workspace, m.id);
    await showDialog<void>(
        context: context,
        builder: (ctx) => ShoppingAccountGuard(
                child: AlertDialog(
                    title: Text(bt(ctx, '메뉴 변경 이력', 'Menu history')),
                    scrollable: true,
                    content: SizedBox(
                        width: 550,
                        child: FutureBuilder(
                            future: pending,
                            builder: (ctx, s) {
                              if (s.hasError) {
                                return Text(businessError(ctx, s.error!));
                              }
                              if (!s.hasData) {
                                return const LinearProgressIndicator();
                              }
                              return Column(children: [
                                for (final row in s.data!)
                                  ListTile(
                                      title: LocalizedText(
                                          'v${row['revision']} · ${row['snapshot']['name']}'),
                                      subtitle: LocalizedText(
                                          '${menuStageLabel(ctx, row['snapshot']['is_candidate'] == true ? 'candidate' : row['snapshot']['status'] as String)} · ${row['snapshot']['price_confirmed'] == false ? bt(ctx, '가격 미정', 'Price pending') : row['snapshot']['price']} ${row['snapshot']['currency']}\n${bt(ctx, '레시피 버전', 'Recipe revision')} ${row['snapshot']['recipe_revision']} · ${_businessDate(ctx, row['created_at'])}'))
                              ]);
                            })),
                    actions: [
                  TextButton(
                      onPressed: () => Navigator.pop(ctx),
                      child: Text(bt(ctx, '닫기', 'Close')))
                ])));
  }

  @override
  Widget build(BuildContext context) =>
      ref.watch(businessContextProvider(widget.workspace)).when(
          loading: () =>
              const Scaffold(body: Center(child: CircularProgressIndicator())),
          error: (e, _) => Scaffold(
              appBar: AppBar(),
              body: _BusinessError(
                  e,
                  () => ref
                      .invalidate(businessContextProvider(widget.workspace)))),
          data: (b) {
            if (!b.can('recipes.read')) {
              return Scaffold(
                  appBar: AppBar(),
                  body: Text(
                      businessError(context, StateError('BUSINESS_DENIED'))));
            }
            return Scaffold(
                appBar: AppBar(
                    title: Text(bt(context, '메뉴판 관리', 'Menu management')),
                    actions: [
                      IconButton(
                          tooltip: bt(context, '새로고침', 'Refresh'),
                          onPressed: () => ref.invalidate(
                              businessMenusProvider(widget.workspace)),
                          icon: const Icon(Icons.refresh))
                    ]),
                body: Center(
                    child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 1000),
                        child: ListView(
                            padding: const EdgeInsets.all(20),
                            children: [
                              if (b.isTest) const BusinessPracticeNotice(),
                              _BusinessWorkHeader(
                                  workspace: b.name,
                                  title:
                                      bt(context, '메뉴판 관리', 'Menu management'),
                                  subtitle: bt(
                                      context,
                                      '후보는 개발 중에도 등록할 수 있습니다. 출시 준비·판매 전에는 승인된 레시피 버전과 판매가를 확인합니다.',
                                      'Add candidates during development. Launch requires an approved revision and a selling price.'),
                                  icon: Icons.restaurant_menu),
                              const SizedBox(height: 12),
                              Wrap(spacing: 8, runSpacing: 8, children: [
                                if ((b.can('menus.approve') ||
                                    b.can('recipes.write')))
                                  FilledButton.icon(
                                      onPressed: () => _edit(b),
                                      icon: const Icon(Icons.add),
                                      label: Text(bt(
                                          context, '메뉴 등록', 'Add menu item'))),
                                if (b.can('purchasing.write') &&
                                    b.can('purchasing.read'))
                                  FilledButton.icon(
                                      onPressed: () => context.push(
                                          '/business-workspaces/${b.id}/menu-fast'),
                                      icon:
                                          const Icon(Icons.playlist_add_check),
                                      label: Text(bt(context, '판매 메뉴로 빠른 구매',
                                          'Quick purchase from menus'))),
                                OutlinedButton.icon(
                                    onPressed: () =>
                                        setState(() => _preview = !_preview),
                                    icon: const Icon(Icons.restaurant_menu),
                                    label: Text(_preview
                                        ? bt(context, '관리 화면', 'Manage')
                                        : bt(context, '판매 메뉴판 미리보기',
                                            'Preview selling menu'))),
                                if (b.can('purchasing.write'))
                                  OutlinedButton.icon(
                                      onPressed: () => context.push(
                                          '/business-workspaces/${b.id}/menu-purchase'),
                                      icon: const Icon(
                                          Icons.shopping_cart_outlined),
                                      label: Text(bt(context, '메뉴·레시피에서 구매',
                                          'Buy from menus / recipes')))
                              ]),
                              const SizedBox(height: 12),
                              TextField(
                                  decoration: InputDecoration(
                                      labelText: bt(context, '메뉴명·분류 검색',
                                          'Search menu names / categories')),
                                  onChanged: (v) => setState(
                                      () => _query = v.trim().toLowerCase())),
                              if (!_preview)
                                BusinessWorkflowSteps(labels: [
                                  bt(context, '후보 등록', 'Candidate'),
                                  bt(context, '출시 준비', 'Prepare launch'),
                                  bt(context, '판매 중', 'On sale')
                                ]),
                              if (!_preview)
                                Wrap(spacing: 8, children: [
                                  for (final s in [
                                    'all',
                                    'candidate',
                                    'preparing',
                                    'on_sale',
                                    'stopped'
                                  ])
                                    ChoiceChip(
                                        label: Text(s == 'all'
                                            ? bt(context, '전체', 'All')
                                            : menuStageLabel(context, s)),
                                        selected: _status == s,
                                        onSelected: (_) =>
                                            setState(() => _status = s))
                                ]),
                              ref.watch(businessMenusProvider(b.id)).when(
                                  loading: () =>
                                      const LinearProgressIndicator(),
                                  error: (e, _) => _BusinessError(
                                      e,
                                      () => ref.invalidate(
                                          businessMenusProvider(b.id))),
                                  data: (rows) {
                                    final items = rows
                                        .where((m) =>
                                            (_preview
                                                ? m.status == 'on_sale'
                                                : _status == 'all' ||
                                                    m.status == _status) &&
                                            '${m.name} ${m.category}'
                                                .toLowerCase()
                                                .contains(_query))
                                        .toList();
                                    return Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.stretch,
                                        children: [
                                          ScoutSectionLabel(
                                              title: bt(
                                                  context,
                                                  '메뉴 ${items.length}개',
                                                  '${items.length} menu items'),
                                              subtitle: _preview
                                                  ? bt(
                                                      context,
                                                      '판매 중인 메뉴만 표시합니다.',
                                                      'Only active selling menus are shown.')
                                                  : bt(
                                                      context,
                                                      '선택한 상태와 검색어에 맞는 메뉴입니다.',
                                                      'Menus matching your status and search.')),
                                          if (items.isEmpty)
                                            Padding(
                                                padding:
                                                    const EdgeInsets.all(24),
                                                child: Text(bt(
                                                    context,
                                                    '표시할 메뉴가 없습니다.',
                                                    'No matching menu items.'))),
                                          for (final m in items)
                                            Card(
                                                margin: const EdgeInsets.only(
                                                    bottom: 12),
                                                child: Padding(
                                                    padding:
                                                        const EdgeInsets.all(
                                                            16),
                                                    child: Column(
                                                        crossAxisAlignment:
                                                            CrossAxisAlignment
                                                                .start,
                                                        children: [
                                                          if (m.category
                                                              .isNotEmpty)
                                                            Text(m.category,
                                                                style: Theme.of(
                                                                        context)
                                                                    .textTheme
                                                                    .labelLarge),
                                                          Text(m.name,
                                                              style: Theme.of(
                                                                      context)
                                                                  .textTheme
                                                                  .titleLarge),
                                                          LocalizedText(
                                                              '${m.price == null ? bt(context, '가격 미정', 'Price pending') : menuNumber(m.price!)} ${m.currency}'),
                                                          if (m.description
                                                              .isNotEmpty)
                                                            Text(m.description),
                                                          if (!_preview) ...[
                                                            const SizedBox(
                                                                height: 8),
                                                            LocalizedText(
                                                                '${menuStageLabel(context, m.status)} · ${m.snapshot['title']} v${m.recipeRevision}'),
                                                            ref.watch(businessMenuRevisionsProvider(b.id)).maybeWhen(
                                                                data: (versions) => (versions[m.id] as num? ?? m.recipeRevision) > m.recipeRevision
                                                                    ? TextButton(
                                                                        onPressed: () =>
                                                                            context.push(
                                                                                '/business-workspaces/${b.id}/records/${m.recipeId}'),
                                                                        child: Text(bt(
                                                                            context,
                                                                            '새 레시피 버전 검토 · 현재 메뉴는 기존 버전 유지',
                                                                            'Review newer recipe · current menu keeps its pinned revision')))
                                                                    : const SizedBox
                                                                        .shrink(),
                                                                orElse: () =>
                                                                    const SizedBox
                                                                        .shrink()),
                                                            Wrap(
                                                                spacing: 8,
                                                                children: [
                                                                  if (b.can(
                                                                          'menus.approve') ||
                                                                      (b.can('recipes.write') &&
                                                                          m.status ==
                                                                              'candidate'))
                                                                    TextButton(
                                                                        onPressed: () => _edit(
                                                                            b,
                                                                            m),
                                                                        child: Text(bt(
                                                                            context,
                                                                            '수정·출시·판매 중지',
                                                                            'Edit / launch / stop'))),
                                                                  TextButton(
                                                                      onPressed: () =>
                                                                          _history(
                                                                              m),
                                                                      child: Text(bt(
                                                                          context,
                                                                          '변경 이력',
                                                                          'History')))
                                                                ])
                                                          ]
                                                        ])))
                                        ]);
                                  }),
                              if (_preview)
                                Text(bt(
                                    context,
                                    '업소 내부 미리보기입니다. 고객용 공개 링크나 QR은 생성되지 않습니다.',
                                    'Internal preview. No public customer link or QR is created.'))
                            ]))));
          });
}

class BusinessMenuEditor extends ConsumerStatefulWidget {
  const BusinessMenuEditor(
      {super.key, required this.business, this.original, this.initialRecipe});
  final BusinessContext business;
  final BusinessMenuItem? original;
  final BusinessRecord? initialRecipe;
  @override
  ConsumerState<BusinessMenuEditor> createState() => _BusinessMenuEditorState();
}

class _BusinessMenuEditorState extends ConsumerState<BusinessMenuEditor> {
  final _form = GlobalKey<FormState>();
  final _name = TextEditingController(),
      _category = TextEditingController(),
      _description = TextEditingController(),
      _price = TextEditingController();
  late final String? _account = ref.read(activeAccountIdProvider);
  late final String _id = widget.original?.id ?? newShoppingId();
  String _currency = 'KRW', _status = 'candidate';
  String? _recipe;
  int? _version;
  String _recipeTitle = '';
  bool _busy = false;
  String? _error;
  @override
  void initState() {
    super.initState();
    final initial = widget.initialRecipe;
    if (initial != null) {
      _recipe = initial.id;
      _version = initial.revision;
      _recipeTitle = initial.title;
      _name.text = initial.title;
    }
    final m = widget.original;
    if (m != null) {
      _name.text = m.name;
      _category.text = m.category;
      _description.text = m.description;
      _price.text = m.price == null ? '' : '${m.price}';
      _currency = m.currency;
      _status = m.status;
      _recipe = m.recipeId;
      _version = m.recipeRevision;
      _recipeTitle = m.snapshot['title'] as String;
    }
  }

  @override
  void dispose() {
    for (final c in [_name, _category, _description, _price]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _choose() async {
    final chosen = await chooseMenuRecipe(context, ref, widget.business.id,
        approvedOnly: _status != 'candidate');
    if (!mounted ||
        _account != ref.read(activeAccountIdProvider) ||
        chosen == null) {
      return;
    }
    setState(() {
      _recipe = chosen.id;
      _version = chosen.revision;
      _recipeTitle = chosen.title;
      if (_name.text.isEmpty) _name.text = chosen.title;
    });
  }

  Future<void> _save() async {
    if (!_form.currentState!.validate() ||
        _recipe == null ||
        _version == null ||
        _busy) {
      return;
    }
    if (!await businessConfirm(
            context,
            bt(context, '이 메뉴의 이름·가격·레시피 버전과 판매 상태를 저장할까요?',
                'Save this menu name, price, recipe revision and selling state?')) ||
        !mounted) {
      return;
    }
    if (_account != ref.read(activeAccountIdProvider)) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref
          .read(businessMenuRepositoryProvider)
          .save(widget.business.id, _id, widget.original?.revision ?? 0, {
        'name': _name.text.trim(),
        'category': _category.text.trim(),
        'description': _description.text.trim(),
        'price': num.tryParse(_price.text.trim()),
        'currency': _currency,
        'recipe_id': _recipe,
        'recipe_revision': _version,
        'status': _status
      });
      if (!mounted || _account != ref.read(activeAccountIdProvider)) return;
      ref.invalidate(businessMenusProvider(widget.business.id));
      Navigator.pop(context);
    } catch (e) {
      if (mounted && _account == ref.read(activeAccountIdProvider)) {
        setState(() => _error = businessError(context, e));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
      canPop: !_busy,
      child: AlertDialog(
          scrollable: true,
          title: Text(bt(context, '메뉴 등록·수정', 'Menu item')),
          content: SizedBox(
              width: 520,
              child: Form(
                  key: _form,
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                    ScoutSectionLabel(
                        number: '01',
                        title: bt(context, '메뉴 기본 정보', 'Menu details')),
                    TextFormField(
                        controller: _name,
                        enabled: !_busy,
                        maxLength: 120,
                        decoration: InputDecoration(
                            labelText: bt(context, '판매 메뉴명', 'Menu name')),
                        validator: (v) => (v ?? '').trim().isEmpty
                            ? bt(context, '입력해 주세요.', 'Required.')
                            : null),
                    TextFormField(
                        controller: _category,
                        enabled: !_busy,
                        maxLength: 80,
                        decoration: InputDecoration(
                            labelText: bt(context, '분류', 'Category'))),
                    TextFormField(
                        controller: _description,
                        enabled: !_busy,
                        maxLength: 1000,
                        maxLines: 3,
                        decoration: InputDecoration(
                            labelText:
                                bt(context, '메뉴 설명', 'Menu description'))),
                    ScoutSectionLabel(
                        number: '02',
                        title: bt(context, '판매 가격', 'Selling price')),
                    TextFormField(
                        controller: _price,
                        enabled: !_busy,
                        keyboardType: const TextInputType.numberWithOptions(
                            decimal: true),
                        decoration: InputDecoration(
                            labelText: bt(context, '판매가', 'Selling price')),
                        validator: (v) {
                          if (_status == 'candidate' &&
                              (v ?? '').trim().isEmpty) {
                            return null;
                          }
                          final n = parseUserNumber(v ?? '');
                          return n == null || !n.isFinite || n < 0 || n > 1e12
                              ? bt(context, '올바른 수를 입력해 주세요.',
                                  'Enter a valid number.')
                              : null;
                        }),
                    DropdownButtonFormField<String>(
                        isExpanded: true,
                        initialValue: _currency,
                        decoration: InputDecoration(
                            labelText: bt(context, '통화', 'Currency')),
                        items: [
                          for (final s in ['KRW', 'USD'])
                            DropdownMenuItem(value: s, child: Text(s))
                        ],
                        onChanged: _busy
                            ? null
                            : (v) => setState(() => _currency = v!)),
                    const SizedBox(height: 16),
                    ScoutSectionLabel(
                        number: '03',
                        title: bt(context, '레시피 버전·판매 상태',
                            'Recipe revision & selling state')),
                    LocalizedText(_recipe == null
                        ? bt(context, '후보는 개발 버전, 판매 메뉴는 승인 버전을 선택하세요.',
                            'Use a development revision for candidates; an approved revision for launch.')
                        : '$_recipeTitle v$_version'),
                    OutlinedButton(
                        onPressed: _busy ? null : _choose,
                        child: Text(bt(
                            context, '레시피 버전 선택', 'Choose recipe revision'))),
                    DropdownButtonFormField<String>(
                        isExpanded: true,
                        initialValue: _status,
                        decoration: InputDecoration(
                            labelText: bt(context, '판매 상태', 'Selling state')),
                        items: [
                          for (final s in [
                            'candidate',
                            if (widget.business.can('menus.approve')) ...[
                              'preparing',
                              'on_sale',
                              'stopped'
                            ]
                          ])
                            DropdownMenuItem(
                                value: s,
                                child: Text(menuStageLabel(context, s)))
                        ],
                        onChanged:
                            _busy ? null : (v) => setState(() => _status = v!)),
                    if (_error != null)
                      Text(_error!,
                          style: TextStyle(
                              color: Theme.of(context).colorScheme.error))
                  ]))),
          actions: [
            TextButton(
                onPressed: _busy ? null : () => Navigator.pop(context),
                child: Text(bt(context, '취소', 'Cancel'))),
            FilledButton(
                onPressed: _busy || _recipe == null ? null : _save,
                child: Text(bt(context, '저장', 'Save')))
          ]));
}

Future<BusinessRecord?> chooseMenuRecipe(
    BuildContext context, WidgetRef ref, String workspace,
    {bool approvedOnly = false}) async {
  final account = ref.read(activeAccountIdProvider);
  final recipe = await showDialog<BusinessRecord>(
      context: context,
      builder: (_) => ShoppingAccountGuard(
          child: _BusinessRecordPicker(workspace: workspace, kind: 'recipe')));
  if (recipe == null ||
      !context.mounted ||
      account != ref.read(activeAccountIdProvider)) {
    return null;
  }
  Future<List<List<Map<String, dynamic>>>> load() => Future.wait([
        ref.read(businessRepositoryProvider).versions(workspace, recipe.id),
        ref.read(businessMenuRepositoryProvider).reviews(workspace, recipe.id)
      ]);
  var future = load();
  return showDialog<BusinessRecord>(
      context: context,
      builder: (ctx) => ShoppingAccountGuard(
          child: StatefulBuilder(
              builder: (ctx, update) => AlertDialog(
                      title:
                          Text(bt(ctx, '참조할 레시피 버전', 'Recipe revision to use')),
                      content: SizedBox(
                          width: 620,
                          height: 440,
                          child: FutureBuilder(
                              future: future,
                              builder: (ctx, s) {
                                if (s.hasError) {
                                  return TextButton(
                                      onPressed: () => update(() {
                                            future = load();
                                          }),
                                      child:
                                          Text(bt(ctx, '다시 불러오기', 'Reload')));
                                }
                                if (!s.hasData) {
                                  return const Center(
                                      child: CircularProgressIndicator());
                                }
                                final approvals = s.data![1]
                                    .where((r) => r['stage'] == 'approved')
                                    .map((r) => r['recipe_revision'])
                                    .toSet();
                                final versions = s.data![0]
                                    .where((v) =>
                                        v['status'] == 'draft' &&
                                        (!approvedOnly ||
                                            approvals.contains(v['revision'])))
                                    .toList();
                                return ListView(children: [
                                  Text(bt(
                                      ctx,
                                      '최근 30개 버전입니다. 재료·기준 인분을 확인한 뒤 선택하세요.',
                                      'Latest 30 revisions. Check ingredients and base servings before selecting.')),
                                  if (versions.isEmpty)
                                    Text(bt(
                                        ctx,
                                        '출시 승인된 버전이 없습니다. 시험 조리 후 출시 승인을 먼저 진행하세요.',
                                        'No approved revision. Complete trial cooking and launch approval first.')),
                                  if (versions.isEmpty)
                                    TextButton(
                                        onPressed: () async {
                                          await ctx.push(
                                              '/business-workspaces/$workspace/records/${recipe.id}');
                                          if (ctx.mounted) {
                                            update(() {
                                              future = load();
                                            });
                                          }
                                        },
                                        child: Text(bt(ctx, '레시피 시험 조리·승인 확인',
                                            'Review recipe trial & approval'))),
                                  for (final v in versions)
                                    ExpansionTile(
                                        title: LocalizedText(
                                            'v${v['revision']} · ${v['title']}'),
                                        subtitle: LocalizedText(
                                            '${v['data']['servings']} ${bt(ctx, '인분', 'servings')} · ${approvals.contains(v['revision']) ? menuStageLabel(ctx, 'approved') : menuStageLabel(ctx, 'development')}'),
                                        children: [
                                          Padding(
                                              padding: const EdgeInsets.all(12),
                                              child: LocalizedText(
                                                  '${v['data']['ingredients']}\n\n${v['data']['steps']}')),
                                          TextButton(
                                              onPressed: () => Navigator.pop(
                                                  ctx,
                                                  BusinessRecord(
                                                      id: recipe.id,
                                                      workspace: workspace,
                                                      kind: 'recipe',
                                                      title:
                                                          v['title'] as String,
                                                      data: Map<String,
                                                              dynamic>.from(
                                                          v['data'] as Map),
                                                      revision:
                                                          (v['revision'] as num)
                                                              .toInt())),
                                              child: Text(bt(ctx, '이 버전 참조',
                                                  'Use this revision')))
                                        ])
                                ]);
                              })),
                      actions: [
                        TextButton(
                            onPressed: () => Navigator.pop(ctx),
                            child: Text(bt(ctx, '취소', 'Cancel')))
                      ]))));
}

class BusinessRecipeLifecycle extends ConsumerWidget {
  const BusinessRecipeLifecycle(
      {super.key, required this.business, required this.recipe});
  final BusinessContext business;
  final BusinessRecord recipe;
  Future<void> _transition(BuildContext c, WidgetRef ref,
      Map<String, dynamic>? prior, String stage) async {
    final account = ref.read(activeAccountIdProvider);
    final note = TextEditingController();
    final text = await showDialog<String>(
        context: c,
        builder: (ctx) => ShoppingAccountGuard(
                child: AlertDialog(
                    scrollable: true,
                    title: Text(menuStageLabel(ctx, stage)),
                    content: TextField(
                        controller: note,
                        maxLength: 2000,
                        maxLines: 4,
                        decoration: InputDecoration(
                            labelText: bt(ctx, '시험 조리 결과·변경 사유 (필수)',
                                'Trial result / reason (required)'))),
                    actions: [
                  TextButton(
                      onPressed: () => Navigator.pop(ctx),
                      child: Text(bt(ctx, '취소', 'Cancel'))),
                  FilledButton(
                      onPressed: () {
                        if (note.text.trim().isNotEmpty) {
                          Navigator.pop(ctx, note.text.trim());
                        }
                      },
                      child: Text(bt(ctx, '기록', 'Record')))
                ])));
    // Controllers remain alive until the dialog's closing animation finishes.
    Future<void>.delayed(const Duration(seconds: 1), note.dispose);
    if (text == null ||
        !c.mounted ||
        account != ref.read(activeAccountIdProvider)) {
      return;
    }
    try {
      await ref
          .read(businessMenuRepositoryProvider)
          .review(recipe, (prior?['id'] as num?)?.toInt() ?? 0, stage, text);
      if (c.mounted && account == ref.read(activeAccountIdProvider)) {
        ref.invalidate(businessRecipeReviewsProvider(
            (workspace: recipe.workspace, id: recipe.id)));
      }
    } catch (e) {
      if (c.mounted && account == ref.read(activeAccountIdProvider)) {
        ScaffoldMessenger.of(c)
            .showSnackBar(SnackBar(content: Text(businessError(c, e))));
      }
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) => Card(
      child: Padding(
          padding: const EdgeInsets.all(16),
          child: ref
              .watch(businessRecipeReviewsProvider(
                  (workspace: recipe.workspace, id: recipe.id)))
              .when(
                  loading: () => const LinearProgressIndicator(),
                  error: (e, _) => _BusinessError(
                      e,
                      () => ref.invalidate(businessRecipeReviewsProvider(
                          (workspace: recipe.workspace, id: recipe.id)))),
                  data: (reviews) {
                    final prior = reviews
                        .where((r) => r['recipe_revision'] == recipe.revision)
                        .firstOrNull;
                    final stage = prior?['stage'] as String? ?? 'development';
                    return Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          LocalizedText(
                              '${bt(context, '개발·출시 관리', 'Development & launch')} · v${recipe.revision}',
                              style: Theme.of(context).textTheme.titleMedium),
                          Text(menuStageLabel(context, stage)),
                          Text(bt(
                              context,
                              '새 내용을 저장하면 새 버전으로 개발을 이어갑니다. 판매 메뉴는 기존 승인 버전을 유지합니다.',
                              'Saving edits continues development as a new revision. Selling menus keep their approved revision.')),
                          if (recipe.data['ingredient_lines'] == null)
                            Text(bt(
                                context,
                                '구매 기준 재료의 수량·단위를 등록해야 시험 조리와 출시 승인을 진행할 수 있습니다.',
                                'Register ingredient quantities and units before trial cooking and approval.')),
                          if (recipe.status == 'draft')
                            Wrap(spacing: 8, children: [
                              if (business.can('recipes.write') ||
                                  business.can('menus.approve'))
                                TextButton(
                                    onPressed: () => showDialog<void>(
                                        context: context,
                                        barrierDismissible: false,
                                        builder: (_) => ShoppingAccountGuard(
                                            child: BusinessMenuEditor(
                                                business: business,
                                                initialRecipe: recipe))),
                                    child: Text(bt(context, '이 버전을 메뉴 후보로 담기',
                                        'Add this revision as a menu candidate'))),
                              if (stage == 'development' &&
                                  business.can('recipes.write'))
                                TextButton(
                                    onPressed: () => _transition(
                                        context, ref, prior, 'testing'),
                                    child: Text(bt(context, '시험 조리 결과 등록',
                                        'Record trial cooking'))),
                              if (stage == 'testing' &&
                                  business.can('recipes.write'))
                                TextButton(
                                    onPressed: () => _transition(
                                        context, ref, prior, 'development'),
                                    child: Text(bt(context, '개발 단계로 돌리기',
                                        'Return to development'))),
                              if (stage == 'testing' &&
                                  business.can('menus.approve'))
                                FilledButton(
                                    onPressed: () => _transition(
                                        context, ref, prior, 'approved'),
                                    child: Text(bt(context, '이 버전 출시 승인',
                                        'Approve this revision'))),
                              if (stage == 'approved')
                                TextButton(
                                    onPressed: () => context.push(
                                        '/business-workspaces/${business.id}/menus'),
                                    child: Text(
                                        bt(context, '메뉴판에 연결', 'Link to menu')))
                            ]),
                          if (reviews.isNotEmpty)
                            ExpansionTile(
                                title: Text(bt(context, '시험 조리·승인 이력',
                                    'Trial and approval history')),
                                children: [
                                  for (final r in reviews)
                                    ListTile(
                                        title: LocalizedText(
                                            'v${r['recipe_revision']} · ${menuStageLabel(context, r['stage'] as String)}'),
                                        subtitle: LocalizedText(
                                            '${r['note']}\n${_businessDate(context, r['created_at'])}'))
                                ])
                        ]);
                  })));
}

class BusinessPurchaseBasis extends ConsumerWidget {
  const BusinessPurchaseBasis({super.key, required this.record});
  final BusinessRecord record;
  @override
  Widget build(BuildContext context, WidgetRef ref) => ref
      .watch(businessPurchaseBasisProvider(
          (workspace: record.workspace, id: record.id)))
      .when(
          loading: () => const LinearProgressIndicator(),
          error: (e, _) => _BusinessError(
              e,
              () => ref.invalidate(businessPurchaseBasisProvider(
                  (workspace: record.workspace, id: record.id)))),
          data: (basis) {
            if (basis == null) return const SizedBox.shrink();
            return Card(
                child: ExpansionTile(
                    title: Text(bt(context, '구매 작성 기준 · 메뉴·레시피 버전',
                        'Purchase basis · menu / recipe revisions')),
                    subtitle: Text(
                        menuStageLabel(context, basis['purpose'] as String)),
                    children: [
                  Padding(
                      padding: const EdgeInsets.all(12),
                      child: Text(bt(
                          context,
                          '초안 생성 당시 기준입니다. 이후 요청 품목을 수동 수정하면 현재 구매량과 다를 수 있습니다.',
                          'Basis at draft creation. Later manual edits may differ from these quantities.'))),
                  for (final s in basis['sources'] as List)
                    ListTile(
                        title: LocalizedText(
                            '${s['menu_name'] ?? s['title']} · v${s['recipe_revision']}'),
                        subtitle: LocalizedText(s['kind'] == 'meal'
                            ? '${s['date']} · ${s['slot']}\n${(s['snapshot']['sources'] as List).map((d) => "${d['title']} · ${d['servings']} ${bt(context, '인분', 'servings')} · v${d['recipe_revision']}").join(' / ')}'
                            : '${s['servings']} ${bt(context, '인분', 'servings')}')),
                  for (final r in basis['requirements'] as List)
                    ListTile(
                        title: LocalizedText('${r['name']} · ${r['spec']}'),
                        subtitle: Text(purchaseBasisLine(
                            context, r as Map, basis['adjustments'] as List)))
                ]));
          });
}

class BusinessRecipeComparison extends StatelessWidget {
  const BusinessRecipeComparison(
      {super.key, required this.current, required this.old});
  final BusinessRecord current;
  final Map<String, dynamic> old;
  @override
  Widget build(BuildContext context) {
    final before = {
      ...Map<String, dynamic>.from(old['data'] as Map),
      'title': old['title']
    };
    final after = {...current.data, 'title': current.title};
    final fields = changedRecipeFields(before, after);
    String label(String k) => switch (k) {
          'title' => bt(context, '제목', 'Title'),
          'servings' => bt(context, '기준 인분', 'Base servings'),
          'ingredients' => bt(context, '재료·배합', 'Ingredients & quantities'),
          'steps' => bt(context, '조리 순서', 'Cooking steps'),
          _ => bt(context, '메모', 'Notes')
        };
    return Padding(
        padding: const EdgeInsets.all(12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(
              bt(context, '현재 개발 버전과 달라진 내용',
                  'Differences from current development revision'),
              style: Theme.of(context).textTheme.titleMedium),
          if (fields.isEmpty)
            Text(
                bt(context, '레시피 내용이 같습니다.', 'Recipe contents are identical.')),
          for (final k in fields)
            Card(
                child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(label(k),
                              style: Theme.of(context).textTheme.labelLarge),
                          LocalizedText("v${old['revision']}: ${before[k] ?? ''}"),
                          const Divider(),
                          LocalizedText("v${current.revision}: ${after[k] ?? ''}")
                        ])))
        ]));
  }
}

String purchaseBasisLine(
    BuildContext context, Map requirement, List adjustments) {
  final a = adjustments.where((x) => x['key'] == requirement['key']).firstOrNull
      as Map?;
  final unit = requirement['unit'];
  final required =
      '${bt(context, '조리 필요량', 'Required for cooking')}: ${menuNumber(requirement['required'] as num)} $unit';
  if (a == null) return required;
  if (a['include'] == false) {
    return '$required\n${bt(context, '이번 요청에서 제외', 'Excluded from this request')}';
  }
  return '$required\n${bt(context, '재고 / 입고 예정', 'Stock / incoming')}: ${menuNumber(a['stock'] as num)} / ${menuNumber(a['incoming'] as num)} $unit'
      '\n${bt(context, '포장 규격 / 구매 수량', 'Pack size / purchase quantity')}: ${menuNumber(a['pack_size'] as num)} $unit / ${menuNumber(a['purchase_quantity'] as num)} ${a['pack_unit']}'
      '\n${bt(context, '포장 반올림 여유량', 'Pack rounding surplus')}: ${menuNumber(a['overage'] as num)} $unit';
}
