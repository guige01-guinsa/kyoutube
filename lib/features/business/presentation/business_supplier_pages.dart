part of 'business_pages.dart';

class BusinessSuppliersPage extends ConsumerStatefulWidget {
  const BusinessSuppliersPage({super.key, required this.workspace});
  final String workspace;
  @override
  ConsumerState<BusinessSuppliersPage> createState() =>
      _BusinessSuppliersPageState();
}

class _BusinessSuppliersPageState extends ConsumerState<BusinessSuppliersPage> {
  String _query = '';
  bool _inactive = false;
  Future<void> _edit(BusinessSupplier? supplier,
      {Map<String, dynamic>? seed}) async {
    final account = ref.read(activeAccountIdProvider);
    await showDialog<void>(
        context: context,
        builder: (_) => ShoppingAccountGuard(
            child: _BusinessSupplierForm(
                workspace: widget.workspace, supplier: supplier, seed: seed)));
    if (mounted && account == ref.read(activeAccountIdProvider)) {
      ref.invalidate(businessSuppliersProvider(widget.workspace));
    }
  }

  Future<void> _import() async {
    final account = ref.read(activeAccountIdProvider);
    final pending = ref.read(shoppingSuppliersProvider.future);
    final chosen = await showDialog<ShoppingSupplier>(
        context: context,
        builder: (ctx) => ShoppingAccountGuard(
                child: AlertDialog(
                    title: Text(
                        bt(ctx, '개인 거래처에서 선택', 'Choose a personal supplier')),
                    content: SizedBox(
                        width: 500,
                        height: 400,
                        child: FutureBuilder(
                            future: pending,
                            builder: (ctx, s) {
                              if (s.hasError) {
                                return Text(businessError(ctx, s.error!));
                              }
                              if (!s.hasData) {
                                return const Center(
                                    child: CircularProgressIndicator());
                              }
                              return ListView(children: [
                                Text(bt(
                                    ctx,
                                    '다음 화면에서 공유할 항목을 고릅니다. 개인 메모는 가져오지 않습니다.',
                                    'Choose which fields to share next. Personal notes are not imported.')),
                                if (s.data!.isEmpty)
                                  Text(bt(ctx, '등록한 개인 거래처가 없습니다.',
                                      'No saved personal suppliers.')),
                                for (final s in s.data!)
                                  ListTile(
                                      title: Text(s.name),
                                      onTap: () => Navigator.pop(ctx, s)),
                              ]);
                            })),
                    actions: [
                  TextButton(
                      onPressed: () => Navigator.pop(ctx),
                      child: Text(bt(ctx, '취소', 'Cancel')))
                ])));
    if (!mounted ||
        chosen == null ||
        account != ref.read(activeAccountIdProvider)) {
      return;
    }
    final fields = <String>{};
    final accept = await showDialog<bool>(
        context: context,
        builder: (ctx) => ShoppingAccountGuard(
            child: StatefulBuilder(
                builder: (ctx, set) => AlertDialog(
                        title: Text(chosen.name),
                        content: SingleChildScrollView(
                            child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                              Text(bt(ctx, '업체명과 체크한 항목의 사본만 업소 직원에게 공유합니다.',
                                  'Share a copy of the name and checked fields with business staff.')),
                              for (final k in [
                                'contact',
                                'phone',
                                'address',
                                'website'
                              ])
                                CheckboxListTile(
                                    contentPadding: EdgeInsets.zero,
                                    value: fields.contains(k),
                                    title: Text(supplierFieldLabel(ctx, k)),
                                    subtitle: Text(
                                        chosen.toJson()[k] as String? ?? ''),
                                    onChanged: (v) => set(() {
                                          if (v == true) {
                                            fields.add(k);
                                          } else {
                                            fields.remove(k);
                                          }
                                        })),
                            ])),
                        actions: [
                          TextButton(
                              onPressed: () => Navigator.pop(ctx, false),
                              child: Text(bt(ctx, '취소', 'Cancel'))),
                          FilledButton(
                              onPressed: () => Navigator.pop(ctx, true),
                              child: Text(
                                  bt(ctx, '공유할 사본 확인', 'Review shared copy')))
                        ]))));
    if (!mounted ||
        accept != true ||
        account != ref.read(activeAccountIdProvider)) {
      return;
    }
    await _edit(null, seed: sharedSupplierCopy(chosen, fields));
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
          data: (b) => Scaffold(
              appBar: AppBar(
                  title: Text(bt(
                      context, '업소 거래처·상품', 'Business suppliers & products'))),
              body: !b.can('purchasing.read')
                  ? Text(businessError(context, StateError('BUSINESS_DENIED')))
                  : Center(
                      child: ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 900),
                          child: ListView(
                              padding: const EdgeInsets.all(20),
                              children: [
                                _BusinessWorkHeader(
                                    workspace: b.name,
                                    title: bt(
                                        context, '공동 거래처', 'Shared suppliers'),
                                    subtitle: bt(
                                        context,
                                        '이 업소의 구매 권한이 있는 직원들이 사용하는 공동 거래처입니다. 상품 규격을 등록하면 메뉴 구매에 연결할 수 있습니다.',
                                        'Shared suppliers for staff with purchasing access in this business. Register pack specifications to use in menu purchases.'),
                                    icon: Icons.local_shipping_outlined),
                                const SizedBox(height: 12),
                                if (b.can('purchasing.write'))
                                  Wrap(spacing: 8, runSpacing: 8, children: [
                                    FilledButton.icon(
                                        onPressed: () => _edit(null),
                                        icon: const Icon(Icons.add),
                                        label: Text(bt(context, '거래처 등록',
                                            'Add supplier'))),
                                    OutlinedButton(
                                        onPressed: _import,
                                        child: Text(bt(context, '개인 거래처에서 가져오기',
                                            'Import from personal suppliers'))),
                                  ]),
                                TextField(
                                    decoration: InputDecoration(
                                        labelText: bt(context, '업체명·연락처·위치 검색',
                                            'Search name, contact or location'),
                                        prefixIcon: const Icon(Icons.search)),
                                    onChanged: (v) =>
                                        setState(() => _query = v)),
                                SwitchListTile(
                                    contentPadding: EdgeInsets.zero,
                                    title: Text(bt(context, '사용 중지 거래처 포함',
                                        'Include inactive suppliers')),
                                    value: _inactive,
                                    onChanged: (v) =>
                                        setState(() => _inactive = v)),
                                ref
                                    .watch(businessSuppliersProvider(
                                        widget.workspace))
                                    .when(
                                        loading: () =>
                                            const LinearProgressIndicator(),
                                        error: (e, _) => _BusinessError(
                                            e,
                                            () => ref.invalidate(
                                                businessSuppliersProvider(
                                                    widget.workspace))),
                                        data: (rows) {
                                          final filtered =
                                              findBusinessSuppliers(
                                                  rows, _query,
                                                  includeInactive: _inactive);
                                          return Column(children: [
                                            if (filtered.isEmpty)
                                              Padding(
                                                  padding:
                                                      const EdgeInsets.all(20),
                                                  child: Text(bt(
                                                      context,
                                                      '조건에 맞는 공동 거래처가 없습니다.',
                                                      'No matching shared suppliers.'))),
                                            for (final s in filtered)
                                              Card(
                                                  child: ListTile(
                                                      title: Text(s.name),
                                                      subtitle: Text([
                                                        if (!s.active)
                                                          bt(context, '사용 중지',
                                                              'Inactive'),
                                                        s.data['phone'],
                                                        s.data['address']
                                                      ]
                                                          .where((v) =>
                                                              v != null &&
                                                              v != '')
                                                          .join(' · ')),
                                                      onTap: () => context.push(
                                                          '/business-workspaces/${widget.workspace}/suppliers/${s.id}'),
                                                      trailing: const Icon(Icons
                                                          .chevron_right))),
                                          ]);
                                        }),
                              ])))));
}

String supplierFieldLabel(BuildContext c, String k) => switch (k) {
      'name' => bt(c, '업체명', 'Supplier name'),
      'contact' => bt(c, '담당자', 'Contact person'),
      'phone' => bt(c, '연락처', 'Phone'),
      'address' => bt(c, '주소·지역', 'Address / region'),
      'website' => bt(c, '홈페이지', 'Website'),
      'product_name' => bt(c, '상품명', 'Product name'),
      'spec' => bt(c, '규격·원산지 등', 'Specification / origin'),
      'content_quantity' => bt(c, '포장 1개당 내용량', 'Content quantity per pack'),
      'content_unit' =>
        bt(c, '내용량 단위 (재료와 같게)', 'Content unit (same as ingredient)'),
      'pack_unit' => bt(c, '구매 단위 (봉·박스 등)', 'Purchase unit (bag / box etc.)'),
      _ => k,
    };

class _BusinessSupplierForm extends ConsumerStatefulWidget {
  const _BusinessSupplierForm(
      {required this.workspace,
      this.supplier,
      this.seed,
      this.parent,
      this.product,
      this.onSaved});
  final String workspace;
  final void Function(String)? onSaved;
  final BusinessSupplier? supplier, parent;
  final BusinessSupplierProduct? product;
  final Map<String, dynamic>? seed;
  @override
  ConsumerState<_BusinessSupplierForm> createState() =>
      _BusinessSupplierFormState();
}

class _BusinessSupplierFormState extends ConsumerState<_BusinessSupplierForm> {
  late final String? _account = ref.read(activeAccountIdProvider);
  late final String _id =
      widget.product?.id ?? widget.supplier?.id ?? newShoppingId();
  final _form = GlobalKey<FormState>();
  late final Map<String, TextEditingController> _fields;
  bool _busy = false, _active = true;
  String? _error;
  bool get _product => widget.parent != null;
  @override
  void initState() {
    super.initState();
    final d =
        widget.product?.data ?? widget.supplier?.data ?? widget.seed ?? {};
    _active = d['active'] != false;
    _fields = {
      for (final k in _product
          ? ['name', 'spec', 'content_quantity', 'content_unit', 'pack_unit']
          : ['name', 'contact', 'phone', 'address', 'website'])
        k: TextEditingController(text: d[k]?.toString() ?? '')
    };
  }

  @override
  void dispose() {
    for (final c in _fields.values) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    if (_busy ||
        _account == null ||
        _account != ref.read(activeAccountIdProvider) ||
        !_form.currentState!.validate()) {
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final data = <String, dynamic>{
        for (final e in _fields.entries) e.key: e.value.text.trim(),
        'active': _active
      };
      final repo = ref.read(businessSupplierRepositoryProvider);
      if (_product) {
        data['content_quantity'] =
            double.parse(_fields['content_quantity']!.text.trim());
        await repo.saveProduct(widget.workspace, widget.parent!.id, _id,
            widget.product?.revision ?? 0, data);
      } else {
        await repo.saveSupplier(
            widget.workspace, _id, widget.supplier?.revision ?? 0, data);
      }
      if (mounted && _account == ref.read(activeAccountIdProvider)) {
        widget.onSaved?.call(_id);
        Navigator.pop(context);
      }
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
          title: Text(bt(
              context,
              _product ? '공동 상품 규격' : '공동 거래처 정보',
              _product
                  ? 'Shared product specification'
                  : 'Shared supplier information')),
          content: SizedBox(
              width: 520,
              child: SingleChildScrollView(
                  child: Form(
                      key: _form,
                      child: Column(mainAxisSize: MainAxisSize.min, children: [
                        Text(bt(context, '저장하면 이 업소의 구매 권한이 있는 직원에게 공유됩니다.',
                            'Saving shares these fields with staff who have purchasing access in this business.')),
                        for (final e in _fields.entries)
                          Padding(
                              padding: const EdgeInsets.only(top: 12),
                              child: Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.stretch,
                                  children: [
                                    if (e.key == 'name')
                                      ScoutSectionLabel(
                                          number: '01',
                                          title: _product
                                              ? bt(context, '상품 정보',
                                                  'Product details')
                                              : bt(context, '거래처 이름',
                                                  'Supplier name')),
                                    if (e.key == 'contact')
                                      ScoutSectionLabel(
                                          number: '02',
                                          title: bt(context, '담당자·연락처',
                                              'Contact details')),
                                    if (e.key == 'content_quantity')
                                      ScoutSectionLabel(
                                          number: '02',
                                          title: bt(context, '내용량·구매 단위',
                                              'Contents & purchase unit'),
                                          subtitle: bt(
                                              context,
                                              '레시피 재료와 같은 단위로 내용량을 입력하세요.',
                                              'Enter contents in the same unit as the recipe ingredient.')),
                                    TextFormField(
                                        controller: e.value,
                                        enabled: !_busy,
                                        maxLength: switch (e.key) {
                                          'website' => 500,
                                          'address' => 300,
                                          'phone' => 80,
                                          'content_unit' || 'pack_unit' => 30,
                                          'content_quantity' => 20,
                                          _ => 120
                                        },
                                        decoration: InputDecoration(
                                            labelText: supplierFieldLabel(
                                                context,
                                                e.key == 'name' && _product
                                                    ? 'product_name'
                                                    : e.key)),
                                        keyboardType:
                                            e.key == 'content_quantity'
                                                ? const TextInputType
                                                    .numberWithOptions(
                                                    decimal: true)
                                                : TextInputType.text,
                                        validator: (v) {
                                          final text = v?.trim() ?? '';
                                          if ([
                                                'name',
                                                'content_quantity',
                                                'content_unit',
                                                'pack_unit'
                                              ].contains(e.key) &&
                                              text.isEmpty) {
                                            return bt(context, '필수 항목입니다.',
                                                'Required.');
                                          }
                                          if (e.key == 'content_quantity') {
                                            final n = parseUserNumber(text);
                                            if (n == null ||
                                                !menuQuantityValid(n) ||
                                                n <= 0) {
                                              return bt(
                                                  context,
                                                  '0보다 큰 수량을 입력하세요 (소수 6자리까지).',
                                                  'Enter a positive quantity (up to 6 decimals).');
                                            }
                                          }
                                          if (e.key == 'website' &&
                                              text.isNotEmpty) {
                                            final uri = Uri.tryParse(text);
                                            if (uri == null ||
                                                !['https', 'http']
                                                    .contains(uri.scheme) ||
                                                uri.host.isEmpty ||
                                                text.contains(RegExp(r'\s'))) {
                                              return bt(
                                                  context,
                                                  'https://로 시작하는 홈페이지 주소를 입력하세요.',
                                                  'Enter a website URL starting with https://.');
                                            }
                                          }
                                          return null;
                                        })
                                  ])),
                        ScoutSectionLabel(
                            number: '03',
                            title: bt(context, '사용 상태', 'Availability')),
                        SwitchListTile(
                            contentPadding: EdgeInsets.zero,
                            title: Text(bt(context, '사용 중', 'Active')),
                            value: _active,
                            onChanged: _busy
                                ? null
                                : (v) => setState(() => _active = v)),
                        if (_product)
                          Text(bt(
                              context,
                              '가격·최소 주문량·배송 조건은 구매요청서 작성 시 공급업체와 별도로 확인하세요.',
                              'Confirm price, minimum order and delivery terms with the supplier when preparing the request.')),
                        if (_error != null)
                          Text(_error!,
                              style: TextStyle(
                                  color: Theme.of(context).colorScheme.error)),
                        if (_busy) const LinearProgressIndicator(),
                      ])))),
          actions: [
            TextButton(
                onPressed: _busy ? null : () => Navigator.pop(context),
                child: Text(bt(context, '취소', 'Cancel'))),
            FilledButton(
                onPressed: _busy ? null : _save,
                child: Text(bt(context, '공동 자료로 저장', 'Save shared data')))
          ]));
}

class BusinessSupplierProductsPage extends ConsumerStatefulWidget {
  const BusinessSupplierProductsPage(
      {super.key, required this.workspace, required this.supplierId});
  final String workspace, supplierId;
  @override
  ConsumerState<BusinessSupplierProductsPage> createState() =>
      _BusinessSupplierProductsState();
}

class _BusinessSupplierProductsState
    extends ConsumerState<BusinessSupplierProductsPage> {
  String _query = '';
  bool _includeInactive = true;
  String get workspace => widget.workspace;
  String get supplierId => widget.supplierId;
  @override
  Widget build(BuildContext context) {
    final q = (workspace: workspace, supplier: supplierId);
    Future<void> edit(BusinessSupplier s,
        {BusinessSupplierProduct? product,
        bool info = false,
        bool copy = false}) async {
      final account = ref.read(activeAccountIdProvider);
      await showDialog<void>(
          context: context,
          builder: (_) => ShoppingAccountGuard(
              child: _BusinessSupplierForm(
                  workspace: workspace,
                  supplier: info ? s : null,
                  parent: info ? null : s,
                  product: copy ? null : product,
                  seed: copy && product != null
                      ? {...product.data, 'active': false}
                      : null)));
      if (mounted && account == ref.read(activeAccountIdProvider)) {
        ref.invalidate(businessSuppliersProvider(workspace));
        ref.invalidate(businessSupplierProductsProvider(q));
      }
    }

    return ref.watch(businessContextProvider(workspace)).when(
        loading: () =>
            const Scaffold(body: Center(child: CircularProgressIndicator())),
        error: (e, _) => Scaffold(
            appBar: AppBar(),
            body: _BusinessError(
                e, () => ref.invalidate(businessContextProvider(workspace)))),
        data: (b) => Scaffold(
            appBar: AppBar(
                title: Text(bt(context, '공동 거래처·상품 규격',
                    'Shared supplier & pack specifications'))),
            body: !b.can('purchasing.read')
                ? Text(businessError(context, StateError('BUSINESS_DENIED')))
                : ref.watch(businessSuppliersProvider(workspace)).when(
                    loading: () => const LinearProgressIndicator(),
                    error: (e, _) => _BusinessError(
                        e,
                        () => ref
                            .invalidate(businessSuppliersProvider(workspace))),
                    data: (rows) {
                      final matches = rows.where((s) => s.id == supplierId);
                      if (matches.isEmpty) {
                        return Text(bt(context, '이 업소에서 거래처를 찾을 수 없습니다.',
                            'Supplier not found in this business.'));
                      }
                      final s = matches.first;
                      return Center(
                          child: ConstrainedBox(
                              constraints: const BoxConstraints(maxWidth: 900),
                              child: ListView(
                                  padding: const EdgeInsets.all(20),
                                  children: [
                                    _BusinessWorkHeader(
                                        workspace: b.name,
                                        title: s.name,
                                        subtitle: bt(
                                            context,
                                            '거래처 정보와 구매에 사용할 상품 규격을 관리하세요.',
                                            'Manage contact details and pack specifications for purchasing.'),
                                        icon: Icons.storefront_outlined),
                                    ScoutSectionLabel(
                                        title: bt(context, '거래처 연락 정보',
                                            'Supplier contact details')),
                                    for (final k in [
                                      'contact',
                                      'phone',
                                      'address',
                                      'website'
                                    ])
                                      if (s.data[k] != '')
                                        SelectableText(
                                            '${supplierFieldLabel(context, k)}: ${s.data[k]}'),
                                    if (!s.active)
                                      Text(bt(
                                          context,
                                          '사용 중지된 거래처입니다. 기존 구매 기록은 보존됩니다.',
                                          'This supplier is inactive. Existing purchase records are preserved.')),
                                    if (b.can('purchasing.write'))
                                      Wrap(
                                          spacing: 8,
                                          runSpacing: 8,
                                          children: [
                                            OutlinedButton(
                                                onPressed: () =>
                                                    edit(s, info: true),
                                                child: Text(bt(
                                                    context,
                                                    '거래처 정보 수정',
                                                    'Edit supplier'))),
                                            RecordManagementMenu(
                                                onError: (e) =>
                                                    businessError(context, e),
                                                actions: [
                                                  if (b.owner)
                                                    RecordManagementAction(
                                                        'erase',
                                                        bt(context, '영구 삭제',
                                                            'Delete permanently'),
                                                        Icons.delete_forever,
                                                        () async {
                                                      if (await _eraseBusinessRecord(
                                                              context,
                                                              ref,
                                                              workspace,
                                                              'supplier',
                                                              s.id) &&
                                                          context.mounted) {
                                                        context.go(
                                                            '/business-workspaces/$workspace/suppliers');
                                                      }
                                                    }),
                                                  RecordManagementAction(
                                                      'availability',
                                                      bt(
                                                          context,
                                                          s.active
                                                              ? '사용 중지'
                                                              : '다시 사용',
                                                          s.active
                                                              ? 'Deactivate'
                                                              : 'Reactivate'),
                                                      s.active
                                                          ? Icons
                                                              .pause_circle_outline
                                                          : Icons
                                                              .play_circle_outline,
                                                      () =>
                                                          _changeSharedSupplierState(
                                                              context,
                                                              ref,
                                                              workspace,
                                                              s)),
                                                ]),
                                            if (s.active)
                                              FilledButton.icon(
                                                  onPressed: () => edit(s),
                                                  icon: const Icon(Icons.add),
                                                  label: Text(bt(
                                                      context,
                                                      '상품 규격 등록',
                                                      'Add pack specification'))),
                                          ]),
                                    const SizedBox(height: 16),
                                    Text(bt(
                                        context,
                                        '내용량 단위는 연결할 레시피 재료와 같게 등록하세요. 예: 양파 2,000 g / 봉. 자동 단위 변환은 하지 않습니다.',
                                        'Use the same content unit as the recipe ingredient, e.g. onion 2,000 g / bag. Units are not automatically converted.')),
                                    ScoutSectionLabel(
                                        title: bt(context, '구매 상품·포장 규격',
                                            'Purchase products & packs')),
                                    TextField(
                                        decoration: InputDecoration(
                                            labelText: bt(context, '상품명·규격 검색',
                                                'Search product or specification'),
                                            prefixIcon:
                                                const Icon(Icons.search)),
                                        onChanged: (v) => setState(() =>
                                            _query = v.trim().toLowerCase())),
                                    SwitchListTile(
                                        contentPadding: EdgeInsets.zero,
                                        title: Text(bt(context, '사용 중지 상품 포함',
                                            'Include inactive products')),
                                        value: _includeInactive,
                                        onChanged: (v) => setState(
                                            () => _includeInactive = v)),
                                    ref
                                        .watch(
                                            businessSupplierProductsProvider(q))
                                        .when(
                                            loading: () =>
                                                const LinearProgressIndicator(),
                                            error: (e, _) => _BusinessError(
                                                e,
                                                () => ref.invalidate(
                                                    businessSupplierProductsProvider(
                                                        q))),
                                            data: (products) =>
                                                Column(children: [
                                                  if (products.isEmpty)
                                                    Padding(
                                                        padding:
                                                            const EdgeInsets
                                                                .all(20),
                                                        child: Text(bt(
                                                            context,
                                                            '등록된 상품 규격이 없습니다.',
                                                            'No registered pack specifications.'))),
                                                  for (final p in products.where((p) =>
                                                      (_includeInactive || p.active) &&
                                                      productSearchMatches(
                                                          '${p.name} ${p.spec} ${p.contentUnit} ${p.packUnit}', _query)))
                                                    Card(
                                                        child: ListTile(
                                                            title: Text(p.name),
                                                            subtitle: LocalizedText(
                                                                '${p.spec}\n${menuNumber(p.contentQuantity)} ${p.contentUnit} / ${p.packUnit}${p.active ? '' : ' · ${bt(context, '사용 중지', 'Inactive')}'}'),
                                                            trailing:
                                                                b.can('purchasing.write') &&
                                                                        (s.active ||
                                                                            b
                                                                                .owner)
                                                                    ? RecordManagementMenu(
                                                                        onError: (e) => businessError(
                                                                            context,
                                                                            e),
                                                                        actions: [
                                                                            if (b.owner)
                                                                              RecordManagementAction('erase', bt(context, '영구 삭제', 'Delete permanently'), Icons.delete_forever, () async {
                                                                                await _eraseBusinessRecord(context, ref, workspace, 'product', p.id);
                                                                              }),
                                                                            if (s.active)
                                                                              RecordManagementAction('edit', bt(context, '수정', 'Edit'), Icons.edit_outlined, () => edit(s, product: p)),
                                                                            if (s.active)
                                                                              RecordManagementAction('copy', bt(context, '규격 복제', 'Copy specification'), Icons.copy, () => edit(s, product: p, copy: true)),
                                                                            if (s.active)
                                                                              RecordManagementAction('availability', bt(context, p.active ? '사용 중지' : '다시 사용', p.active ? 'Deactivate' : 'Reactivate'), Icons.pause_circle_outline, () => _changeSharedSupplierState(context, ref, workspace, s, product: p)),
                                                                          ])
                                                                    : null,
                                                            onTap:
                                                                b.can('purchasing.write') &&
                                                                        s.active
                                                                    ? () => edit(
                                                                        s,
                                                                        product:
                                                                            p)
                                                                    : null)),
                                                ])),
                                  ])));
                    })));
  }
}

Future<void> _changeSharedSupplierState(BuildContext context, WidgetRef ref,
    String workspace, BusinessSupplier supplier,
    {BusinessSupplierProduct? product}) async {
  final account = ref.read(activeAccountIdProvider);
  if (account == null) return;
  final active = product?.active ?? supplier.active;
  final yes = await confirmRecordManagement(
      context,
      bt(context, active ? '사용 중지' : '다시 사용',
          active ? 'Deactivate' : 'Reactivate'),
      bt(context, '앞으로 구매할 때의 선택 상태를 변경합니다. 이미 작성한 요청서와 입고 기록은 유지됩니다.',
          'Change availability for future purchases. Existing requests and receipts are preserved.'));
  if (!yes ||
      !context.mounted ||
      account != ref.read(activeAccountIdProvider)) {
    return;
  }
  final repo = ref.read(businessSupplierRepositoryProvider);
  if (product == null) {
    await repo.saveSupplier(workspace, supplier.id, supplier.revision,
        {...supplier.data, 'active': !active});
  } else {
    await repo.saveProduct(workspace, supplier.id, product.id, product.revision,
        {...product.data, 'active': !active});
  }
  if (!context.mounted || account != ref.read(activeAccountIdProvider)) return;
  ref.invalidate(businessSuppliersProvider(workspace));
  ref.invalidate(businessSupplierProductsProvider(
      (workspace: workspace, supplier: supplier.id)));
}

class BusinessSupplierSnapshot extends ConsumerWidget {
  const BusinessSupplierSnapshot({super.key, required this.record});
  final BusinessRecord record;
  @override
  Widget build(BuildContext context, WidgetRef ref) => ref
      .watch(businessSupplierSnapshotProvider(
          (workspace: record.workspace, request: record.id)))
      .when(
          loading: () => const LinearProgressIndicator(),
          error: (e, _) => _BusinessError(
              e,
              () => ref.invalidate(businessSupplierSnapshotProvider(
                  (workspace: record.workspace, request: record.id)))),
          data: (snapshot) {
            if (snapshot == null) return const SizedBox.shrink();
            final s = snapshot['supplier'] as Map, d = s['data'] as Map;
            return Card(
                child: ExpansionTile(
                    title: Text(bt(context, '작성 당시 거래처·상품',
                        'Supplier & products at creation')),
                    subtitle: LocalizedText('${d['name']} · v${s['revision']}'),
                    childrenPadding: const EdgeInsets.all(16),
                    expandedCrossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                  Text(bt(
                      context,
                      '초안을 만들 때 선택한 정보입니다. 요청서에서 이후 수정한 내용은 위의 현재 요청서를 확인하세요.',
                      'These are the selections when the draft was created. Check the current request above for subsequent edits.')),
                  for (final k in ['contact', 'phone', 'address', 'website'])
                    if (d[k] != '')
                      SelectableText(
                          '${supplierFieldLabel(context, k)}: ${d[k]}'),
                  for (final p in snapshot['products'] as List)
                    ListTile(
                        contentPadding: EdgeInsets.zero,
                        title: LocalizedText('${p['data']['name']} · v${p['revision']}'),
                        subtitle: LocalizedText(
                            '${p['data']['spec']} / ${menuNumber(p['data']['content_quantity'] as num)} ${p['data']['content_unit']} / ${p['data']['pack_unit']}')),
                ]));
          });
}

Future<T?> _createBusinessChoice<T>(
    BuildContext context, WidgetRef ref, String workspace,
    {BusinessSupplier? parent, Map<String, dynamic>? seed}) async {
  final account = ref.read(activeAccountIdProvider);
  final access = await ref.read(businessContextProvider(workspace).future);
  if (!context.mounted || account != ref.read(activeAccountIdProvider)) {
    return null;
  }
  if (!access.can('purchasing.write')) throw StateError('BUSINESS_DENIED');
  String? saved;
  await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => ShoppingAccountGuard(
          child: _BusinessSupplierForm(
              workspace: workspace,
              parent: parent,
              seed: seed,
              onSaved: (id) => saved = id)));
  if (!context.mounted ||
      account != ref.read(activeAccountIdProvider) ||
      saved == null) {
    return null;
  }
  final repo = ref.read(businessSupplierRepositoryProvider);
  ref.invalidate(businessSuppliersProvider(workspace));
  ref.invalidate(businessSupplierProductsProvider);
  final Object row = parent == null
      ? await repo.supplier(workspace, saved!)
      : await repo.product(workspace, parent.id, saved!);
  if (!context.mounted || account != ref.read(activeAccountIdProvider)) {
    return null;
  }
  return row as T;
}
