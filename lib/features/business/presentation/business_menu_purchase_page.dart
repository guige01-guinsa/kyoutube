part of 'business_pages.dart';

class BusinessMenuPurchasePage extends ConsumerWidget {
  const BusinessMenuPurchasePage({super.key, required this.workspace});
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
          data: (b) => BusinessMenuPurchaseEditor(
              key: ValueKey('${ref.watch(activeAccountIdProvider)}:$workspace'),
              business: b));
}

class BusinessMenuPurchaseEditor extends ConsumerStatefulWidget {
  const BusinessMenuPurchaseEditor({super.key, required this.business});
  final BusinessContext business;
  @override
  ConsumerState<BusinessMenuPurchaseEditor> createState() =>
      _BusinessMenuPurchaseEditorState();
}

class _BusinessMenuPurchaseEditorState
    extends ConsumerState<BusinessMenuPurchaseEditor> {
  late final String? _account = ref.read(activeAccountIdProvider);
  late final String _request = newShoppingId();
  final _supplier = TextEditingController();
  final _sources = <MenuPurchaseSource>[];
  BusinessSupplier? _sharedSupplier;
  final _products = <String, BusinessSupplierProduct>{};
  List<MenuPurchaseAdjustment> _adjustments = [];
  String _purpose = 'operations';
  String? _error;
  bool _busy = false, _saved = false;
  bool get _current =>
      mounted &&
      _account != null &&
      _account == ref.read(activeAccountIdProvider);
  @override
  void dispose() {
    _supplier.dispose();
    super.dispose();
  }

  Future<void> _add() async {
    String? id, title, kind;
    int? revision;
    if (_purpose == 'operations') {
      final chosen = await showDialog<BusinessMenuItem>(
          context: context,
          builder: (_) => ShoppingAccountGuard(
              child: BusinessSupplierChoice<BusinessMenuItem>(
                  title: bt(context, '판매 중 메뉴 선택', 'Choose a selling menu'),
                  load: () => ref
                      .read(businessMenuRepositoryProvider)
                      .menus(widget.business.id)
                      .then((rows) =>
                          rows.where((m) => m.status == 'on_sale').toList()),
                  label: (m) => m.name,
                  detail: (m) => '${m.snapshot['title']} v${m.recipeRevision}',
                  createLabel: bt(context, '판매 메뉴 설정', 'Set up selling menus'),
                  onCreate: () async {
                    await context.push(
                        '/business-workspaces/${widget.business.id}/menus');
                    return null;
                  })));
      if (chosen == null || !_current) return;
      id = chosen.id;
      title =
          '${chosen.name} · ${chosen.snapshot['title']} v${chosen.recipeRevision}';
      revision = chosen.revision;
      kind = 'menu';
    } else {
      final chosen = await chooseMenuRecipe(context, ref, widget.business.id,
          approvedOnly: _purpose == 'launch');
      if (chosen == null || !_current) return;
      id = chosen.id;
      title = '${chosen.title} v${chosen.revision}';
      revision = chosen.revision;
      kind = 'recipe';
    }
    if (_sources.any((s) => s.id == id && s.kind == kind)) return;
    if (!mounted) return;
    final servings = TextEditingController();
    final value = await showDialog<double>(
        context: context,
        builder: (ctx) => ShoppingAccountGuard(
                child: AlertDialog(
                    title: Text(title!),
                    content: TextField(
                        controller: servings,
                        keyboardType: const TextInputType.numberWithOptions(
                            decimal: true),
                        decoration: InputDecoration(
                            labelText: bt(ctx, '조리할 인분 (판매·시험 수량)',
                                'Servings to prepare (sales / trial)'))),
                    actions: [
                  TextButton(
                      onPressed: () => Navigator.pop(ctx),
                      child: Text(bt(ctx, '취소', 'Cancel'))),
                  FilledButton(
                      onPressed: () {
                        final n = parseUserNumber(servings.text.trim());
                        if (n != null &&
                            menuQuantityValid(n) &&
                            n >= 0.001 &&
                            n <= 100000) {
                          Navigator.pop(ctx, n);
                        }
                      },
                      child: Text(bt(ctx, '추가', 'Add')))
                ])));
    Future<void>.delayed(const Duration(seconds: 1), servings.dispose);
    if (value == null || !_current) return;
    setState(() {
      _sources.add(MenuPurchaseSource(
          kind: kind!,
          id: id!,
          revision: revision!,
          title: title!,
          servings: value));
      _adjustments = [];
      _error = null;
    });
  }

  Future<void> _plan() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final plan = await ref
          .read(businessMenuRepositoryProvider)
          .plan(widget.business.id, _purpose, _sources);
      if (_current) {
        _products.clear();
        setState(() => _adjustments = (plan['requirements'] as List)
            .map((r) =>
                MenuPurchaseAdjustment(Map<String, dynamic>.from(r as Map)))
            .toList());
      }
    } catch (e) {
      if (_current) setState(() => _error = businessError(context, e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _clearProducts() {
    for (final a in _adjustments) {
      if (_products.containsKey(a.requirement['key'])) {
        a.packSize = null;
        a.packUnit = '';
        a.confirmed = false;
      }
    }
    _products.clear();
  }

  Future<void> _supplierPick() async {
    final result = await showDialog<BusinessSupplier>(
        context: context,
        builder: (_) => ShoppingAccountGuard(
                child: BusinessSupplierChoice<BusinessSupplier>(
              title: bt(
                  context, '업소 공동 거래처 선택', 'Choose a shared business supplier'),
              load: () => ref
                  .read(businessSupplierRepositoryProvider)
                  .suppliers(widget.business.id)
                  .then((v) => v.where((s) => s.active).toList()),
              onCreate: () => _createBusinessChoice<BusinessSupplier>(
                  context, ref, widget.business.id),
              createLabel: bt(context, '거래처 추가', 'Add supplier'),
              label: (s) => s.name,
              detail: (s) => '${s.data['phone']} ${s.data['address']}',
            )));
    if (result != null && _current) {
      setState(() {
        _clearProducts();
        _sharedSupplier = result;
        _supplier.text = result.name;
      });
    }
  }

  Future<void> _productPick(MenuPurchaseAdjustment a) async {
    final supplier = _sharedSupplier;
    if (supplier == null) return;
    final chosen = await showDialog<BusinessSupplierProduct>(
        context: context,
        builder: (_) => ShoppingAccountGuard(
                child: BusinessSupplierChoice<BusinessSupplierProduct>(
              title:
                  '${a.requirement['name']} · ${bt(context, '연결할 상품 선택', 'Choose a matching product')}',
              notice: bt(context, '같은 내용량 단위의 상품만 표시합니다. 재료·규격이 맞는지 직접 확인하세요.',
                  'Only products with the same content unit are shown. Check that the ingredient and specification match.'),
              load: () => ref
                  .read(businessSupplierRepositoryProvider)
                  .products(widget.business.id, supplier.id)
                  .then((v) => v
                      .where(
                          (p) => p.matchesUnit(a.requirement['unit'] as String))
                      .toList()),
              onCreate: () => _createBusinessChoice<BusinessSupplierProduct>(
                  context, ref, widget.business.id, parent: supplier, seed: {
                'name': a.requirement['name'],
                'content_unit': a.requirement['unit']
              }),
              createLabel: bt(context, '상품·규격 추가', 'Add product / pack'),
              label: (p) => p.name,
              detail: (p) =>
                  '${p.spec} / ${menuNumber(p.contentQuantity)} ${p.contentUnit} / ${p.packUnit}',
            )));
    if (chosen != null && _current && _sharedSupplier?.id == supplier.id) {
      if (!chosen.matchesUnit(a.requirement['unit'] as String)) {
        setState(
            () => _error = businessError(context, StateError('SUPPLIER_UNIT')));
        return;
      }
      setState(() {
        _products[a.requirement['key'] as String] = chosen;
        a.packSize = chosen.contentQuantity;
        a.packUnit = chosen.packUnit;
        a.confirmed = false;
      });
    }
  }

  Future<void> _save() async {
    if (_busy ||
        _adjustments.isEmpty ||
        !_adjustments.any((a) => a.include && a.valid && (a.packs ?? 0) > 0) ||
        _adjustments.any((a) => a.include && (!a.valid || !a.confirmed)) ||
        _supplier.text.trim().isEmpty) {
      return;
    }
    if (!await businessConfirm(
            context,
            bt(
                context,
                '표시된 구매량으로 공동 구매 초안을 만들까요? 다음 화면에서 납품일·단가를 확인하고 기존 승인 절차를 진행합니다.',
                'Create a shared purchase draft with these quantities? Confirm delivery and prices on the next screen, then follow the existing approval process.')) ||
        !_current) {
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final saved = _sharedSupplier == null
          ? await ref.read(businessMenuRepositoryProvider).purchase(
              widget.business.id,
              _request,
              _purpose,
              _sources,
              _adjustments,
              _supplier.text.trim())
          : await ref.read(businessSupplierRepositoryProvider).purchase(
              widget.business.id,
              _request,
              _purpose,
              _sources,
              _adjustments,
              _sharedSupplier!,
              _products);
      if (!_current) return;
      ref.invalidate(businessRecordsProvider);
      setState(() {
        _saved = true;
        _busy = false;
      });
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_current) {
          context.go(
              '/business-workspaces/${widget.business.id}/edit/${saved.id}');
        }
      });
    } catch (e) {
      if (_current) setState(() => _error = businessError(context, e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_account == null ||
        _account != ref.watch(activeAccountIdProvider) ||
        !widget.business.can('recipes.read') ||
        !widget.business.can('purchasing.write')) {
      return Scaffold(
          appBar: AppBar(),
          body: Text(businessError(context, StateError('BUSINESS_DENIED'))));
    }
    return WorkspaceEditGuard(
        dirty: !_saved && _sources.isNotEmpty,
        busy: _busy && !_saved,
        confirmLeave: () => confirmWorkspaceDiscard(context),
        child: PopScope(
            canPop: !_busy,
            child: Scaffold(
                appBar: AppBar(
                    title: Text(bt(context, '메뉴·레시피에서 구매요청',
                        'Purchase from menus / recipes'))),
                body: Center(
                    child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 900),
                        child: ListView(
                            padding: const EdgeInsets.all(20),
                            children: [
                              if (widget.business.isTest)
                                const BusinessPracticeNotice(),
                              _BusinessWorkHeader(
                                  workspace: widget.business.name,
                                  title: bt(context, '메뉴·레시피에서 구매',
                                      'Buy from menus / recipes'),
                                  subtitle: bt(
                                      context,
                                      '먼저 구매 목적과 기준 레시피를 선택하세요. 재료량은 서버에서 계산하며 재고를 자동 차감하지 않습니다.',
                                      'Choose the purchase purpose and recipe first. Quantities are calculated on the server; stock is not automatically deducted.'),
                                  icon: Icons.shopping_basket_outlined),
                              const SizedBox(height: 12),
                              TextButton.icon(
                                  onPressed: _busy
                                      ? null
                                      : () => context.push(
                                          '/business-workspaces/${widget.business.id}/new/purchase'),
                                  icon: const Icon(Icons.edit_note),
                                  label: Text(bt(context, '비품·소모품은 직접 작성',
                                      'Write a supplies request manually'))),
                              ScoutSectionLabel(
                                  number: '01',
                                  title: bt(context, '구매 목적·기준 레시피',
                                      'Purpose & source recipes')),
                              DropdownButtonFormField<String>(
                                  isExpanded: true,
                                  initialValue: _purpose,
                                  decoration: InputDecoration(
                                      labelText: bt(context, '구매 목적',
                                          'Purchase purpose')),
                                  items: [
                                    for (final s in [
                                      'operations',
                                      'launch',
                                      'development'
                                    ])
                                      DropdownMenuItem(
                                          value: s,
                                          child: Text(s == 'development'
                                              ? bt(context, '개발·시험 조리용 구매',
                                                  'Development / trial purchase')
                                              : menuStageLabel(context, s)))
                                  ],
                                  onChanged: _busy
                                      ? null
                                      : (v) => setState(() {
                                            _purpose = v!;
                                            _sources.clear();
                                            _adjustments = [];
                                          })),
                              for (final s in _sources)
                                ListTile(
                                    title: Text(s.title),
                                    subtitle: LocalizedText(
                                        '${menuNumber(s.servings)} ${bt(context, '인분', 'servings')}'),
                                    trailing: IconButton(
                                        tooltip: bt(context, '제외', 'Remove'),
                                        onPressed: _busy
                                            ? null
                                            : () => setState(() {
                                                  _sources.remove(s);
                                                  _adjustments = [];
                                                }),
                                        icon: const Icon(Icons.close))),
                              OutlinedButton.icon(
                                  onPressed: _busy || _sources.length >= 20
                                      ? null
                                      : _add,
                                  icon: const Icon(Icons.add),
                                  label: Text(bt(context, '메뉴·레시피와 인분 추가',
                                      'Add menu / recipe and servings'))),
                              FilledButton(
                                  onPressed:
                                      _busy || _sources.isEmpty ? null : _plan,
                                  child: Text(bt(context, '재료 필요량 계산',
                                      'Calculate ingredient requirements'))),
                              if (_adjustments.isNotEmpty) ...[
                                const SizedBox(height: 20),
                                ScoutSectionLabel(
                                    number: '02',
                                    title: bt(context, '재고·입고 예정·포장 규격 확인',
                                        'Review stock, incoming and pack sizes')),
                                Text(bt(
                                    context,
                                    '이름·규격·단위가 같은 재료만 합산합니다. 재고와 입고 예정량은 다른 작업에 배정되지 않은 수량을 입력하세요. 없으면 0을 입력합니다.',
                                    'Only matching names, specifications and units are combined. Enter stock and incoming quantities not allocated to other work. Enter 0 if none.')),
                                TextField(
                                    controller: _supplier,
                                    enabled: !_busy && _sharedSupplier == null,
                                    maxLength: 120,
                                    decoration: InputDecoration(
                                        labelText:
                                            bt(context, '공급업체', 'Supplier')),
                                    onChanged: (_) => setState(() {})),
                                Wrap(spacing: 8, runSpacing: 8, children: [
                                  OutlinedButton(
                                      onPressed: _busy ? null : _supplierPick,
                                      child: Text(bt(context, '업소 공동 거래처 선택',
                                          'Choose a shared business supplier'))),
                                  if (_sharedSupplier != null)
                                    TextButton(
                                        onPressed: _busy
                                            ? null
                                            : () => setState(() {
                                                  _clearProducts();
                                                  _sharedSupplier = null;
                                                  _supplier.clear();
                                                }),
                                        child: Text(bt(context, '직접 입력으로 변경',
                                            'Switch to manual entry'))),
                                  TextButton(
                                      onPressed: _busy
                                          ? null
                                          : () => context.push(
                                              '/business-workspaces/${widget.business.id}/suppliers'),
                                      child: Text(bt(context, '거래처·상품 관리',
                                          'Manage suppliers & products'))),
                                ]),
                                BusinessStockPurchaseHints(
                                    key: ObjectKey(_adjustments),
                                    workspace: widget.business.id,
                                    requirements: _adjustments
                                        .map((a) => a.requirement)
                                        .toList()),
                                BusinessIngredientReview<
                                        MenuPurchaseAdjustment>(
                                    items: _adjustments,
                                    name: (a) =>
                                        a.requirement['name'] as String,
                                    needsReview: (a) =>
                                        a.include && (!a.valid || !a.confirmed),
                                    builder: (a) => Card(
                                        key: ObjectKey(a),
                                        child: Padding(
                                            padding: const EdgeInsets.all(16),
                                            child: Column(
                                                crossAxisAlignment:
                                                    CrossAxisAlignment.start,
                                                children: [
                                                  CheckboxListTile(
                                                      contentPadding:
                                                          EdgeInsets.zero,
                                                      value: a.include,
                                                      onChanged: _busy
                                                          ? null
                                                          : (v) => setState(
                                                              () => a.include =
                                                                  v == true),
                                                      title: Text(bt(
                                                          context,
                                                          '이번 공급업체에 요청',
                                                          'Include for this supplier'))),
                                                  LocalizedText(
                                                      '${a.requirement['name']} · ${a.requirement['spec']}',
                                                      style: Theme.of(context)
                                                          .textTheme
                                                          .titleMedium),
                                                  LocalizedText(
                                                      '${bt(context, '조리 필요량', 'Required for cooking')}: ${menuNumber(a.requiredQuantity)} ${a.requirement['unit']}'),
                                                  if (_sharedSupplier != null)
                                                    Wrap(spacing: 8, children: [
                                                      OutlinedButton(
                                                          onPressed: _busy ||
                                                                  !a.include
                                                              ? null
                                                              : () =>
                                                                  _productPick(
                                                                      a),
                                                          child: Text(_products[
                                                                      a.requirement[
                                                                          'key']]
                                                                  ?.name ??
                                                              bt(
                                                                  context,
                                                                  '공급업체 상품 연결',
                                                                  'Link supplier product'))),
                                                      if (_products.containsKey(
                                                          a.requirement['key']))
                                                        TextButton(
                                                            onPressed: _busy
                                                                ? null
                                                                : () =>
                                                                    setState(
                                                                        () {
                                                                      _products.remove(
                                                                          a.requirement[
                                                                              'key']);
                                                                      a.packSize =
                                                                          null;
                                                                      a.packUnit =
                                                                          '';
                                                                      a.confirmed =
                                                                          false;
                                                                    }),
                                                            child: Text(bt(
                                                                context,
                                                                '연결 해제',
                                                                'Unlink'))),
                                                    ]),
                                                  ScoutAdaptiveGrid(
                                                      minTileWidth: 210,
                                                      gap: 12,
                                                      children: [
                                                        for (final k in [
                                                          'stock',
                                                          'incoming',
                                                          'pack_size'
                                                        ])
                                                          SizedBox(
                                                              width: 210,
                                                              child:
                                                                  BusinessQuantityField(
                                                                      key: ValueKey(
                                                                          '$k-${k == 'pack_size' ? _products[a.requirement['key']]?.id : ''}-${k == 'pack_size' ? _products[a.requirement['key']]?.revision : ''}'),
                                                                      value:
                                                                          switch (
                                                                              k) {
                                                                        'stock' =>
                                                                          a.stock,
                                                                        'incoming' =>
                                                                          a.incoming,
                                                                        _ =>
                                                                          a.packSize,
                                                                      },
                                                                      unit: a.requirement[
                                                                              'unit']
                                                                          as String,
                                                                      enabled: !_busy &&
                                                                          a
                                                                              .include &&
                                                                          (k != 'pack_size' ||
                                                                              !_products.containsKey(a.requirement[
                                                                                  'key'])),
                                                                      label:
                                                                          switch (
                                                                              k) {
                                                                        'stock' => bt(
                                                                            context,
                                                                            '사용 가능 재고',
                                                                            'Available stock'),
                                                                        'incoming' => bt(
                                                                            context,
                                                                            '입고 예정',
                                                                            'Incoming'),
                                                                        _ => bt(
                                                                            context,
                                                                            '포장 1개당 양',
                                                                            'Quantity per pack')
                                                                      },
                                                                      onChanged: (v) =>
                                                                          setState(
                                                                              () {
                                                                            switch (k) {
                                                                              case 'stock':
                                                                                a.stock = v;
                                                                              case 'incoming':
                                                                                a.incoming = v;
                                                                              default:
                                                                                a.packSize = v;
                                                                            }
                                                                            a.confirmed =
                                                                                false;
                                                                          }))),
                                                        SizedBox(
                                                            width: 210,
                                                            child:
                                                                TextFormField(
                                                                    key: ValueKey(
                                                                        'pack-unit-${_products[a.requirement['key']]?.id}-${_products[a.requirement['key']]?.revision}'),
                                                                    initialValue: a
                                                                        .packUnit,
                                                                    enabled: !_busy &&
                                                                        a
                                                                            .include &&
                                                                        !_products.containsKey(a.requirement[
                                                                            'key']),
                                                                    maxLength:
                                                                        30,
                                                                    decoration: InputDecoration(
                                                                        labelText: bt(
                                                                            context,
                                                                            '구매 단위 (봉·박스 등)',
                                                                            'Purchase unit (bag / box etc.)')),
                                                                    onChanged: (v) =>
                                                                        setState(
                                                                            () {
                                                                          a.packUnit =
                                                                              v;
                                                                          a.confirmed =
                                                                              false;
                                                                        })))
                                                      ]),
                                                  if (a.valid)
                                                    LocalizedText(
                                                        '${bt(context, '필요 구매량', 'Net requirement')}: ${menuNumber(a.net)} ${a.requirement['unit']} → ${a.packs} ${a.packUnit}\n${bt(context, '포장 올림 여유량', 'Pack rounding surplus')}: ${menuNumber(a.overage!)} ${a.requirement['unit']}'),
                                                  CheckboxListTile(
                                                      contentPadding: EdgeInsets
                                                          .zero,
                                                      value: a.confirmed,
                                                      onChanged: _busy ||
                                                              !a.valid
                                                          ? null
                                                          : (v) => setState(
                                                              () =>
                                                                  a.confirmed =
                                                                      v ==
                                                                          true),
                                                      title: Text(bt(
                                                          context,
                                                          '재고·입고 예정·포장 규격을 확인했습니다.',
                                                          'I checked stock, incoming quantities and pack size.')))
                                                ])))),
                                ScoutSectionLabel(
                                    number: '03',
                                    title: bt(context, '요청서 초안 만들기',
                                        'Prepare the request draft')),
                                Text(bt(
                                    context,
                                    '이번 업체에 요청할 재료만 선택하세요. 나머지 재료는 다른 업체의 요청서에서 작성합니다.',
                                    'Select only ingredients for this supplier. Use another request for the remaining ingredients.')),
                                if (!_adjustments.any((a) => a.include))
                                  Text(bt(context, '요청할 재료를 하나 이상 선택하세요.',
                                      'Select at least one ingredient.'))
                                else if (_adjustments
                                    .where((a) => a.include)
                                    .every((a) => a.valid && a.packs == 0))
                                  Text(bt(
                                      context,
                                      '재고·입고 예정량으로 충당됩니다. 추가 구매할 수량이 없습니다.',
                                      'Stock and incoming quantities cover this plan. No additional purchase is needed.')),
                                FilledButton.icon(
                                    onPressed: _busy ||
                                            !_adjustments.any((a) =>
                                                a.include &&
                                                a.valid &&
                                                (a.packs ?? 0) > 0) ||
                                            _supplier.text.trim().isEmpty ||
                                            _adjustments.any((a) =>
                                                a.include &&
                                                (!a.valid || !a.confirmed))
                                        ? null
                                        : _save,
                                    icon:
                                        const Icon(Icons.description_outlined),
                                    label: Text(bt(
                                        context,
                                        '확인한 수량으로 구매 초안 만들기',
                                        'Create purchase draft with reviewed quantities')))
                              ],
                              if (_error != null)
                                Padding(
                                    padding: const EdgeInsets.all(12),
                                    child: Text(_error!,
                                        style: TextStyle(
                                            color: Theme.of(context)
                                                .colorScheme
                                                .error))),
                              if (_busy) const LinearProgressIndicator(),
                              const SizedBox(height: 20),
                              TextButton(
                                  onPressed: _busy
                                      ? null
                                      : () => context.push(
                                          '/business-workspaces/${widget.business.id}/new/purchase'),
                                  child: Text(bt(context, '기타 비품·직접 구매요청 작성',
                                      'Other supplies / write a request manually')))
                            ]))))));
  }
}
