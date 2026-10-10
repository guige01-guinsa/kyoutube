part of 'business_pages.dart';

class BusinessRecordEditorPage extends ConsumerWidget {
  const BusinessRecordEditorPage(
      {super.key, required this.workspace, this.kind, this.recordId});
  final String workspace;
  final String? kind, recordId;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final account = ref.watch(activeAccountIdProvider);
    Widget form(BusinessContext business, BusinessRecord? record) =>
        BusinessRecordEditor(
            key: ValueKey('$account:$workspace:${record?.id ?? kind}'),
            business: business,
            kind: record?.kind ?? kind ?? 'recipe',
            original: record);
    return ref.watch(businessContextProvider(workspace)).when(
        data: (business) => recordId == null
            ? form(business, null)
            : ref.watch(businessRecordProvider((workspace: workspace, id: recordId!))).when(
                data: (record) => form(business, record),
                loading: () => const Scaffold(
                    body: Center(child: CircularProgressIndicator())),
                error: (e, _) => Scaffold(
                    appBar: AppBar(),
                    body: _BusinessError(
                        e,
                        () => ref.invalidate(businessRecordProvider(
                            (workspace: workspace, id: recordId!)))))),
        loading: () =>
            const Scaffold(body: Center(child: CircularProgressIndicator())),
        error: (e, _) => Scaffold(
            appBar: AppBar(),
            body: _BusinessError(
                e, () => ref.invalidate(businessContextProvider(workspace)))));
  }
}

class BusinessRecordEditor extends ConsumerStatefulWidget {
  const BusinessRecordEditor(
      {super.key, required this.business, required this.kind, this.original});
  final BusinessContext business;
  final String kind;
  final BusinessRecord? original;
  @override
  ConsumerState<BusinessRecordEditor> createState() =>
      _BusinessRecordEditorState();
}

class _BusinessRecordEditorState extends ConsumerState<BusinessRecordEditor> {
  final _form = GlobalKey<FormState>();
  final _fields = <String, TextEditingController>{};
  late final String _id = widget.original?.id ?? newShoppingId();
  late final String? _account = ref.read(activeAccountIdProvider);
  final _selected = <String, String>{};
  final _lines = <Map<String, dynamic>>[];
  final _ingredients = <MenuIngredient>[];
  bool _dirty = false, _busy = false;
  String? _error;
  String _currency = 'KRW';
  TextEditingController field(String key) =>
      _fields.putIfAbsent(key, () => TextEditingController());
  @override
  void initState() {
    super.initState();
    final d = widget.original?.data ?? {};
    field('title').text = widget.original?.title ?? '';
    for (final k in [
      'ingredients',
      'steps',
      'notes',
      'servings',
      'date',
      'supplier',
      'buyer',
      'phone',
      'address',
      'delivery_date',
      'unit_cost',
      'unit_price',
      'quantity'
    ]) {
      field(k).text = d[k]?.toString() ?? '';
    }
    if (field('servings').text.isEmpty) field('servings').text = '1';
    if (field('date').text.isEmpty) {
      field('date').text = DateTime.now().toIso8601String().substring(0, 10);
    }
    if (field('buyer').text.isEmpty) field('buyer').text = widget.business.name;
    _currency = d['currency'] as String? ?? 'KRW';
    for (final v in d['recipe_ids'] as List? ?? []) {
      _selected[v as String] = v;
    }
    for (final k in ['recipe_id', 'cost_id']) {
      if (d[k] != null) _selected[d[k] as String] = d[k] as String;
    }
    for (final v in d['lines'] as List? ?? []) {
      _lines.add(Map<String, dynamic>.from(v as Map));
    }
    _ingredients.addAll((d['ingredient_lines'] as List? ?? []).map(
        (v) => MenuIngredient.fromJson(Map<String, dynamic>.from(v as Map))));
    if (widget.kind == 'purchase' && _lines.isEmpty) _addLine();
    for (final c in _fields.values) {
      c.addListener(_changed);
    }
  }

  void _changed() {
    if (mounted && !_dirty) setState(() => _dirty = true);
  }

  void _addLine() {
    _lines.add({
      'id': newShoppingId(),
      'name': '',
      'quantity': null,
      'unit': '',
      'spec': '',
      'price': null
    });
  }

  void _selectCoupang(Map<String, dynamic> line, CoupangPurchasePlan? plan) {
    final previous = CoupangPurchasePlan.parse(line['coupang']);
    setState(() {
      if (plan == null) {
        line.remove('coupang');
        if (previous != null) {
          line['quantity'] = previous.needed;
          line['unit'] = previous.unit;
        }
      } else {
        line['coupang'] = plan.toJson();
        line['quantity'] = plan.count;
        line['unit'] = plan.pack.label;
      }
      line['price'] = null;
      _dirty = true;
      if (_lines.every((l) => l.containsKey('coupang'))) {
        field('supplier').text = '쿠팡';
      }
    });
  }

  @override
  void dispose() {
    for (final c in _fields.values) {
      c.dispose();
    }
    super.dispose();
  }

  String? _number(String? value,
      {bool optional = false, bool integer = false, bool zero = false}) {
    if (optional && (value ?? '').trim().isEmpty) return null;
    final n = parseUserNumber((value ?? '').trim());
    if (n == null ||
        !n.isFinite ||
        (zero ? n < 0 : n <= 0) ||
        n > 1e12 ||
        (integer && n != n.truncateToDouble())) {
      return bt(context, '올바른 수를 입력해 주세요.', 'Enter a valid number.');
    }
    return null;
  }

  Widget _text(String key, String ko, String en,
          {bool required = false, int lines = 1, int max = 4000}) =>
      Padding(
          padding: const EdgeInsets.only(bottom: 14),
          child: TextFormField(
              key: ValueKey('business-field-$key'),
              controller: field(key),
              readOnly: key == 'ingredients' && _ingredients.isNotEmpty,
              enabled: !_busy,
              maxLines: lines,
              maxLength: max,
              decoration: InputDecoration(labelText: bt(context, ko, en)),
              validator: (v) => required && (v ?? '').trim().isEmpty
                  ? bt(context, '입력해 주세요.', 'Required.')
                  : null));
  Widget _numeric(String key, String ko, String en,
          {bool integer = false, bool zero = false}) =>
      Padding(
          padding: const EdgeInsets.only(bottom: 14),
          child: TextFormField(
              key: ValueKey('business-field-$key'),
              controller: field(key),
              enabled: !_busy,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              decoration: InputDecoration(labelText: bt(context, ko, en)),
              validator: (v) => _number(v, integer: integer, zero: zero)));
  Future<void> _pick(String kind) async {
    final chosen = await showDialog<BusinessRecord>(
        context: context,
        builder: (ctx) => ShoppingAccountGuard(
            child: _BusinessRecordPicker(
                workspace: widget.business.id, kind: kind)));
    if (chosen == null ||
        !mounted ||
        _account != ref.read(activeAccountIdProvider)) {
      return;
    }
    setState(() {
      if (widget.kind != 'meal') _selected.clear();
      _selected[chosen.id] = chosen.title;
      _dirty = true;
      if (widget.kind == 'sale') {
        _currency = chosen.data['currency'] as String;
        field('unit_cost').text = '${chosen.data['unit_cost']}';
        field('unit_price').text = '${chosen.data['unit_price']}';
        if (field('title').text.isEmpty) field('title').text = chosen.title;
      }
    });
  }

  Map<String, dynamic> _data() {
    String text(String k) => field(k).text.trim();
    num number(String k) => num.parse(text(k));
    return switch (widget.kind) {
      'recipe' => {
          'ingredients': text('ingredients'),
          'steps': text('steps'),
          'notes': text('notes'),
          'servings': number('servings'),
          if (_ingredients.isNotEmpty)
            'ingredient_lines': _ingredients.map((v) => v.toJson()).toList()
        },
      'meal' => {
          'date': text('date'),
          'servings': number('servings'),
          'recipe_ids': _selected.keys.toList(),
          'notes': text('notes')
        },
      'purchase' => {
          'supplier': text('supplier'),
          'buyer': text('buyer'),
          'phone': text('phone'),
          'address': text('address'),
          'delivery_date': text('delivery_date'),
          'notes': text('notes'),
          'currency': _currency,
          'lines': _lines
        },
      'cost' => {
          'recipe_id': _selected.keys.firstOrNull,
          'unit_cost': number('unit_cost'),
          'unit_price': number('unit_price'),
          'currency': _currency,
          'notes': text('notes')
        },
      'sale' => {
          'cost_id': _selected.keys.first,
          'date': text('date'),
          'quantity': number('quantity')
        },
      _ => {},
    };
  }

  Future<void> _save() async {
    if (_busy || !_form.currentState!.validate()) return;
    if (widget.kind == 'purchase' &&
        _lines.any((l) => l.containsKey('coupang')) &&
        (!_lines.every((l) => l.containsKey('coupang')) ||
            field('supplier').text.trim() != '쿠팡')) {
      setState(() => _error = bt(
          context,
          '쿠팡 품목은 공급업체 품목과 별도 요청서로 저장해 주세요. 메뉴 구매 목록에서는 자동으로 나누어 생성합니다.',
          'Save Coupang items in a separate request from supplier items. Menu purchase lists split them automatically.'));
      return;
    }
    if (widget.kind == 'recipe' &&
        widget.original?.data['ingredient_lines'] != null &&
        _ingredients.isEmpty) {
      setState(() => _error = bt(context, '구매 기준 재료를 하나 이상 등록해 주세요.',
          'Register at least one ingredient for purchasing.'));
      return;
    }
    if ((widget.kind == 'meal' || widget.kind == 'sale') && _selected.isEmpty) {
      setState(() =>
          _error = bt(context, '연결할 자료를 선택해 주세요.', 'Select a linked record.'));
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final repo = ref.read(businessRepositoryProvider);
      final current = await repo.context(widget.business.id);
      if (!mounted || _account != ref.read(activeAccountIdProvider)) return;
      if (!current.can(businessPermission(widget.kind, write: true))) {
        throw StateError('BUSINESS_DENIED');
      }
      final saved = await repo.save(BusinessRecord(
          id: _id,
          workspace: widget.business.id,
          kind: widget.kind,
          title: field('title').text.trim(),
          data: _data(),
          revision: widget.original?.revision ?? 0));
      if (!mounted || _account != ref.read(activeAccountIdProvider)) return;
      ref.invalidate(businessRecordsProvider);
      ref.invalidate(businessMenuRevisionsProvider(widget.business.id));
      ref.invalidate(
          businessRecordProvider((workspace: widget.business.id, id: _id)));
      setState(() {
        _dirty = false;
        _busy = false;
      });
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _account == ref.read(activeAccountIdProvider)) {
          context.go(
              '/business-workspaces/${widget.business.id}/records/${saved.id}');
        }
      });
    } catch (e) {
      if (mounted && _account == ref.read(activeAccountIdProvider)) {
        setState(() => _error = businessError(context, e));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_account == null ||
        _account != ref.watch(activeAccountIdProvider) ||
        !widget.business.can(businessPermission(widget.kind, write: true)) ||
        (widget.original != null && widget.original!.status != 'draft')) {
      return Scaffold(
          appBar: AppBar(),
          body: Center(
              child: Text(bt(context, '수정 권한이 없거나 확정된 자료입니다.',
                  'Editing is not allowed for this account or record.'))));
    }
    return WorkspaceEditGuard(
        dirty: _dirty,
        busy: _busy,
        confirmLeave: () => confirmWorkspaceDiscard(context),
        child: PopScope(
            canPop: !_busy,
            child: Scaffold(
                appBar: AppBar(
                    title: Text(businessKindLabel(context, widget.kind))),
                bottomNavigationBar:
                    widget.kind != 'purchase' || widget.business.isTest
                        ? null
                        : CoupangDisclosureFooter(
                            ingredients:
                                _lines.map((line) => line['name'] as String),
                            hasSelection:
                                _lines.any((line) => line['coupang'] != null)),
                body: Center(
                    child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 850),
                        child: Form(
                            key: _form,
                            child: ListView(
                                padding: const EdgeInsets.all(20),
                                children: [
                                  if (widget.business.isTest)
                                    const BusinessPracticeNotice(),
                                  _BusinessWorkHeader(
                                      workspace: widget.business.name,
                                      title: businessKindLabel(
                                          context, widget.kind),
                                      subtitle: bt(
                                          context,
                                          '업무에 필요한 내용을 기록하고 저장하세요. 저장한 내용은 이 업소의 권한 범위에 따라 공유됩니다.',
                                          'Record the details for this task. Saved records are shared according to this business’s permissions.'),
                                      icon: Icons.edit_note),
                                  const SizedBox(height: 16),
                                  _text('title', '제목', 'Title',
                                      required: true, max: 120),
                                  if (widget.kind == 'recipe') ...[
                                    ScoutSectionLabel(
                                        number: '01',
                                        title: bt(context, '기준 인분·재료',
                                            'Base servings & ingredients')),
                                    _numeric(
                                        'servings', '기준 인분', 'Base servings'),
                                    _text('ingredients', '재료·조리 수량 (한 줄에 한 재료)',
                                        'Ingredients & cooking quantities (one per line)',
                                        required: true, lines: 6, max: 30000),
                                    BusinessIngredientEditor(
                                        lines: _ingredients,
                                        enabled: !_busy,
                                        onChanged: (items) {
                                          if (_account !=
                                              ref.read(
                                                  activeAccountIdProvider)) {
                                            return;
                                          }
                                          setState(() {
                                            _ingredients
                                              ..clear()
                                              ..addAll(items);
                                            _dirty = true;
                                            if (items.isNotEmpty) {
                                              field('ingredients').text = items
                                                  .map((v) => v.label)
                                                  .join('\n');
                                            }
                                          });
                                        }),
                                    ScoutSectionLabel(
                                        number: '02',
                                        title: bt(context, '조리 순서·연구 기록',
                                            'Cooking steps & research notes')),
                                    _text('steps', '조리 순서·연구 기록',
                                        'Cooking steps & research notes',
                                        required: true, lines: 6, max: 30000)
                                  ],
                                  if (widget.kind == 'meal') ...[
                                    ScoutSectionLabel(
                                        number: '01',
                                        title: bt(context, '식단 일정·인분',
                                            'Meal date & servings')),
                                    _text('date', '식단 날짜 (YYYY-MM-DD)',
                                        'Meal date (YYYY-MM-DD)',
                                        required: true, max: 10),
                                    _numeric('servings', '예정 인분',
                                        'Planned servings'),
                                    Text(bt(
                                        context,
                                        '여러 공동 레시피를 선택해 식단을 구성하세요. 구매량은 따로 확정합니다.',
                                        'Choose team recipes for this meal. Purchase quantities are confirmed separately.')),
                                    const SizedBox(height: 10)
                                  ],
                                  if (['meal', 'cost', 'sale']
                                      .contains(widget.kind)) ...[
                                    ScoutSectionLabel(
                                        number:
                                            widget.kind == 'meal' ? '02' : '01',
                                        title: bt(context, '참조 자료 연결',
                                            'Link source records')),
                                    Wrap(spacing: 8, runSpacing: 6, children: [
                                      for (final entry in _selected.entries)
                                        InputChip(
                                            label: ref
                                                .watch(businessRecordProvider(
                                                    (workspace: widget.business.id, id: entry.key)))
                                                .when(
                                                    data: (r) => Text(r.title),
                                                    loading: () => Text(bt(
                                                        context,
                                                        '불러오는 중…',
                                                        'Loading…')),
                                                    error: (_, __) => Text(bt(
                                                        context,
                                                        '연결 자료 확인 필요',
                                                        'Check linked record'))),
                                            onDeleted: _busy ||
                                                    (widget.kind == 'sale' &&
                                                        widget.original != null)
                                                ? null
                                                : () => setState(() {
                                                      _selected
                                                          .remove(entry.key);
                                                      _dirty = true;
                                                    }))
                                    ]),
                                    const SizedBox(height: 8),
                                    OutlinedButton.icon(
                                        onPressed: _busy ||
                                                (widget.kind == 'meal' &&
                                                    _selected.length >= 20) ||
                                                (widget.kind == 'sale' &&
                                                    widget.original != null)
                                            ? null
                                            : () => _pick(widget.kind == 'sale'
                                                ? 'cost'
                                                : 'recipe'),
                                        icon: const Icon(Icons.link),
                                        label: Text(widget.kind == 'sale'
                                            ? bt(context, '원가·판매가 기준 선택',
                                                'Select cost & price')
                                            : bt(context, '공동 레시피 연결',
                                                'Link team recipe'))),
                                    const SizedBox(height: 16)
                                  ],
                                  if (widget.kind == 'cost') ...[
                                    ScoutSectionLabel(
                                        number: '02',
                                        title: bt(context, '원가·판매 기준',
                                            'Cost & selling price')),
                                    _numeric('unit_cost', '1인분 원가',
                                        'Cost per serving',
                                        zero: true),
                                    _numeric('unit_price', '1인분 판매가',
                                        'Price per serving',
                                        zero: true)
                                  ],
                                  if (widget.kind == 'sale') ...[
                                    ScoutSectionLabel(
                                        number: '02',
                                        title: bt(context, '판매 날짜·수량',
                                            'Sales date & quantity')),
                                    _text('date', '판매 날짜 (YYYY-MM-DD)',
                                        'Sale date (YYYY-MM-DD)',
                                        required: true, max: 10),
                                    _numeric(
                                        'quantity', '판매 수량', 'Quantity sold',
                                        integer: true),
                                    Text(bt(
                                        context,
                                        '선택한 기준의 판매가·원가를 저장 시점에 기록합니다. 이후 가격 변경은 과거 매출에 반영되지 않습니다.',
                                        'The selected cost and price are recorded at save time. Later price changes do not alter past sales.'))
                                  ],
                                  if (widget.kind == 'purchase') ...[
                                    if (widget.original != null)
                                      BusinessPurchaseBasis(
                                          record: widget.original!),
                                    if (widget.original == null &&
                                        widget.business.can('recipes.read'))
                                      OutlinedButton(
                                          onPressed: _busy
                                              ? null
                                              : () => context.push(
                                                  '/business-workspaces/${widget.business.id}/menu-purchase'),
                                          child: Text(bt(
                                              context,
                                              '메뉴·레시피를 먼저 참조하기',
                                              'Start from a menu or recipe'))),
                                    ScoutSectionLabel(
                                        number: '01',
                                        title: bt(context, '거래처·납품 정보',
                                            'Supplier & delivery')),
                                    _text('supplier', '공급업체', 'Supplier',
                                        max: 120),
                                    _text('buyer', '요청 업소', 'Buyer', max: 120),
                                    _text('phone', '연락처', 'Phone', max: 60),
                                    _text(
                                        'address', '납품 주소', 'Delivery address',
                                        max: 500),
                                    _text(
                                        'delivery_date',
                                        '희망 납품일 (YYYY-MM-DD, 선택)',
                                        'Delivery date (YYYY-MM-DD, optional)',
                                        max: 10),
                                    Text(bt(
                                        context,
                                        '조리 참고 내용을 확인하고 구매 품명·수량·단위를 별도로 확정해 주세요. 단가를 모르면 비워 두세요.',
                                        'Review the cooking reference, then confirm purchase names, quantities and units separately. Leave unknown prices blank.')),
                                    ScoutSectionLabel(
                                        number: '02',
                                        title: bt(
                                            context,
                                            '구매 품목 ${_lines.length}개',
                                            '${_lines.length} purchase items')),
                                    for (final (index, line) in _lines.indexed)
                                      Card(
                                          key: ValueKey(line['id']),
                                          child: Padding(
                                              padding: const EdgeInsets.all(14),
                                              child: Column(children: [
                                                PurchaseNameField(
                                                    workspace:
                                                        widget.business.id,
                                                    initialValue:
                                                        line['name'] as String,
                                                    enabled: !_busy,
                                                    maxLength: 250,
                                                    decoration: InputDecoration(
                                                        labelText: bt(
                                                            context,
                                                            '${index + 1}. 구매 품명',
                                                            '${index + 1}. Purchase item')),
                                                    validator: (v) =>
                                                        (v ?? '').trim().isEmpty
                                                            ? bt(
                                                                context,
                                                                '입력해 주세요.',
                                                                'Required.')
                                                            : null,
                                                    onChanged: (v) {
                                                      if (line.containsKey(
                                                          'coupang')) {
                                                        _selectCoupang(
                                                            line, null);
                                                      }
                                                      line['name'] = v.trim();
                                                      setState(
                                                          () => _dirty = true);
                                                    }),
                                                ScoutAdaptiveGrid(
                                                    minTileWidth: 210,
                                                    gap: 12,
                                                    children: [
                                                      for (final k in [
                                                        'quantity',
                                                        'unit',
                                                        'price'
                                                      ])
                                                        SizedBox(
                                                            width: 180,
                                                            child:
                                                                TextFormField(
                                                                    key: ValueKey(
                                                                        '${line['id']}-$k-${line['coupang']}'),
                                                                    initialValue:
                                                                        line[k]?.toString() ??
                                                                            '',
                                                                    enabled: !_busy &&
                                                                        (line['coupang'] == null ||
                                                                            k ==
                                                                                'price'),
                                                                    decoration:
                                                                        InputDecoration(
                                                                            labelText: switch (
                                                                                k) {
                                                                      'quantity' => bt(
                                                                          context,
                                                                          '구매 수량',
                                                                          'Purchase quantity'),
                                                                      'unit' => bt(
                                                                          context,
                                                                          '구매 단위 (직접 입력)',
                                                                          'Purchase unit (custom)'),
                                                                      _ => bt(
                                                                          context,
                                                                          '단가 (선택)',
                                                                          'Unit price (optional)')
                                                                    }),
                                                                    validator: (v) => k ==
                                                                            'unit'
                                                                        ? ((v?.length ?? 0) > 30
                                                                            ? bt(
                                                                                context,
                                                                                '30자 이내',
                                                                                'Up to 30 characters')
                                                                            : null)
                                                                        : _number(
                                                                            v,
                                                                            optional:
                                                                                true,
                                                                            zero: k ==
                                                                                'price'),
                                                                    onChanged:
                                                                        (v) {
                                                                      line[
                                                                          k] = k ==
                                                                              'unit'
                                                                          ? v
                                                                              .trim()
                                                                          : num.tryParse(
                                                                              v.trim());
                                                                      setState(() =>
                                                                          _dirty =
                                                                              true);
                                                                    }))
                                                    ]),
                                                const SizedBox(height: 12),
                                                TextFormField(
                                                    initialValue: line['spec']
                                                            as String? ??
                                                        '',
                                                    enabled: !_busy,
                                                    maxLength: 300,
                                                    decoration: InputDecoration(
                                                        labelText: bt(
                                                            context,
                                                            '규격·조리 참고',
                                                            'Pack / cooking reference')),
                                                    onChanged: (v) {
                                                      line['spec'] = v.trim();
                                                      _changed();
                                                    }),
                                                if (!widget.business.isTest &&
                                                    (line['name'] as String)
                                                        .trim()
                                                        .isNotEmpty)
                                                  CoupangPurchasePlanner(
                                                      ingredient: line['name']
                                                          as String,
                                                      unit:
                                                          CoupangPurchasePlan.parse(line['coupang'])
                                                                  ?.unit ??
                                                              line['unit']
                                                                  as String,
                                                      needed:
                                                          CoupangPurchasePlan.parse(line['coupang'])
                                                                  ?.needed ??
                                                              (line['quantity']
                                                                      as num?)
                                                                  ?.toDouble(),
                                                      value:
                                                          CoupangPurchasePlan.parse(
                                                              line['coupang']),
                                                      enabled: !_busy,
                                                      allowOpen: false,
                                                      onChanged: (plan) =>
                                                          _selectCoupang(line, plan)),
                                                if (_lines.length > 1)
                                                  TextButton(
                                                      onPressed: _busy
                                                          ? null
                                                          : () => setState(() {
                                                                _lines.removeAt(
                                                                    index);
                                                                _dirty = true;
                                                              }),
                                                      child: Text(bt(
                                                          context,
                                                          '이 품목 삭제',
                                                          'Remove item'))),
                                              ]))),
                                    OutlinedButton.icon(
                                        onPressed: _busy || _lines.length >= 100
                                            ? null
                                            : () => setState(() {
                                                  _addLine();
                                                  _dirty = true;
                                                }),
                                        icon: const Icon(Icons.add),
                                        label: Text(bt(context, '구매 품목 추가',
                                            'Add purchase item')))
                                  ],
                                  if (['purchase', 'cost']
                                      .contains(widget.kind))
                                    Padding(
                                        padding: const EdgeInsets.symmetric(
                                            vertical: 12),
                                        child: DropdownButtonFormField<String>(
                                            initialValue: _currency,
                                            decoration: InputDecoration(
                                                labelText: bt(
                                                    context, '통화', 'Currency')),
                                            items: [
                                              for (final c in ['KRW', 'USD'])
                                                DropdownMenuItem(
                                                    value: c, child: Text(c))
                                            ],
                                            onChanged: _busy
                                                ? null
                                                : (value) => setState(() {
                                                      _currency = value!;
                                                      _dirty = true;
                                                    }))),
                                  if (widget.kind != 'sale')
                                    _text(
                                        'notes', '메모·요청사항', 'Notes / requests',
                                        lines: 3),
                                  if (_error != null)
                                    Padding(
                                        padding: const EdgeInsets.symmetric(
                                            vertical: 12),
                                        child: Text(_error!,
                                            style: TextStyle(
                                                color: Theme.of(context)
                                                    .colorScheme
                                                    .error))),
                                  FilledButton.icon(
                                      key: const Key('business-record-save'),
                                      onPressed: _busy ? null : _save,
                                      icon: _busy
                                          ? const SizedBox(
                                              width: 18,
                                              height: 18,
                                              child: CircularProgressIndicator(
                                                  strokeWidth: 2))
                                          : const Icon(Icons.save_outlined),
                                      label: Text(bt(context, '공동 자료에 저장',
                                          'Save shared record'))),
                                  const SizedBox(height: 20),
                                  Text(bt(
                                      context,
                                      '변경 이력이 남으며, 저장 후에도 실제 발송·입고 상태는 자동 변경되지 않습니다.',
                                      'Changes are recorded in history. Saving does not confirm sharing or receipt.'))
                                ])))))));
  }
}

class _BusinessRecordPicker extends ConsumerStatefulWidget {
  const _BusinessRecordPicker({required this.workspace, required this.kind});
  final String workspace, kind;
  @override
  ConsumerState<_BusinessRecordPicker> createState() =>
      _BusinessRecordPickerState();
}

class _BusinessRecordPickerState extends ConsumerState<_BusinessRecordPicker> {
  int offset = 0;
  @override
  Widget build(BuildContext context) {
    final q = (workspace: widget.workspace, kind: widget.kind, offset: offset);
    return AlertDialog(
        title: Text(businessKindLabel(context, widget.kind)),
        content: SizedBox(
            width: 500,
            height: 350,
            child: ref.watch(businessRecordsProvider(q)).when(
                data: (rows) => ListView(children: [
                      for (final r in rows.where((r) => r.status == 'draft'))
                        ListTile(
                            title: Text(r.title),
                            onTap: () => Navigator.pop(context, r)),
                      if (rows.isEmpty)
                        Text(bt(context, '먼저 공동 자료를 등록해 주세요.',
                            'Add a shared record first.')),
                      Wrap(children: [
                        if (offset > 0)
                          TextButton(
                              onPressed: () => setState(() => offset -= 50),
                              child: Text(bt(context, '이전', 'Previous'))),
                        if (rows.length == 50)
                          TextButton(
                              onPressed: () => setState(() => offset += 50),
                              child: Text(bt(context, '다음', 'Next')))
                      ])
                    ]),
                loading: () => const Center(child: CircularProgressIndicator()),
                error: (e, _) => _BusinessError(
                    e, () => ref.invalidate(businessRecordsProvider(q))))),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text(bt(context, '취소', 'Cancel')))
        ]);
  }
}
