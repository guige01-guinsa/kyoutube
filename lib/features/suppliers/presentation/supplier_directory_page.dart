import '../../../core/localization/localized_text.dart';
import '../../../core/auth/auth_return.dart';
import '../../guide/presentation/guide_help_button.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../auth/application/auth_providers.dart';
import '../../shopping/data/supplier_request_repository.dart';
import '../../shopping/domain/shopping_assistant.dart';
import '../../shopping/domain/supplier_request.dart';
import '../data/supplier_catalog_repository.dart';
import '../domain/supplier_catalog.dart';
import '../domain/public_supplier.dart';
import 'public_supplier_card.dart';
import '../../membership/application/membership_providers.dart';
import 'supplier_business_page.dart';

class SupplierDirectoryPage extends ConsumerWidget {
  const SupplierDirectoryPage(
      {super.key, this.selectMode = false, this.query = '', this.onSelected});
  final bool selectMode;
  final String query;
  final ValueChanged<ShoppingSupplier>? onSelected;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final owner = ref.watch(activeAccountIdProvider);
    if (owner == null) {
      return Scaffold(
          appBar: AppBar(
              title: Text(catalogText(context, '공급업체 찾기', 'Find suppliers'))),
          body: Center(
              child: FilledButton(
                  onPressed: () => context.push(loginFor(
                      GoRouterState.of(context).uri.toString(),
                      resume: true)),
                  child: Text(catalogText(context, '로그인', 'Sign in')))));
    }
    return _Directory(
        key: ValueKey(owner),
        selectMode: selectMode,
        query: query,
        onSelected: onSelected);
  }
}

class _Directory extends ConsumerStatefulWidget {
  const _Directory(
      {super.key,
      required this.selectMode,
      required this.query,
      this.onSelected});
  final bool selectMode;
  final String query;
  final ValueChanged<ShoppingSupplier>? onSelected;
  @override
  ConsumerState<_Directory> createState() => _DirectoryState();
}

class _DirectoryState extends ConsumerState<_Directory> {
  late final _query = TextEditingController(text: widget.query);
  final _brand = TextEditingController();
  String _category = '', _subcategory = '', _region = '', _origin = '';
  List<SupplierOffer> _offers = [];
  List<PublicSupplier> _references = [];
  bool _loading = true, _more = false, _saving = false;
  bool _priced = false, _verified = false, _rated = false;
  String? _error;
  int _generation = 0;
  String t(String ko, String en) => catalogText(context, ko, en);
  bool get en => Localizations.localeOf(context).languageCode != 'ko';
  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _query.dispose();
    _brand.dispose();
    super.dispose();
  }

  Future<void> _load({bool more = false}) async {
    final generation = ++_generation;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final repository = ref.read(supplierCatalogRepositoryProvider);
      final results = await Future.wait([
        repository.search(
            query: _query.text.trim(),
            category: _category,
            subcategory: _subcategory,
            region: _region,
            origin: _origin,
            brand: _brand.text.trim(),
            priced: _priced,
            verified: _verified,
            rated: _rated,
            offset: more ? _offers.length : 0),
        // References have no verified rating, live price, origin or SKU/brand.
        if (!_priced &&
            !_rated &&
            !_verified &&
            _origin.isEmpty &&
            _subcategory.isEmpty &&
            _brand.text.trim().isEmpty)
          repository.publicReferences(
              query: _query.text.trim(),
              category: _category,
              region: _region,
              offset: more ? _references.length : 0)
        else
          Future.value(<PublicSupplier>[]),
      ]);
      final rows = results[0].cast<SupplierOffer>();
      final references = results[1].cast<PublicSupplier>();
      if (mounted && generation == _generation) {
        setState(() {
          _offers = more ? [..._offers, ...rows] : rows;
          _references = more ? [..._references, ...references] : references;
          _more = rows.length == 30 || references.length == 30;
        });
      }
    } catch (_) {
      if (mounted && generation == _generation) {
        setState(() => _error = t('목록을 불러오지 못했습니다. 다시 시도해 주세요.',
            'Could not load suppliers. Try again.'));
      }
    } finally {
      if (mounted && generation == _generation) {
        setState(() => _loading = false);
      }
    }
  }

  Future<void> _select(SupplierOffer offer) async {
    await _selectSupplier(() => ref
        .read(supplierCatalogRepositoryProvider)
        .selectSupplier(offer.supplier.id));
  }

  Future<void> _selectSupplier(
      Future<ShoppingSupplier> Function() action) async {
    if (_saving) return;
    setState(() => _saving = true);
    final owner = ref.read(activeAccountIdProvider);
    try {
      final selected = await action();
      ref.invalidate(shoppingSuppliersProvider);
      if (!mounted || owner != ref.read(activeAccountIdProvider)) return;
      if (widget.selectMode) {
        if (widget.onSelected != null) {
          widget.onSelected!(selected);
        } else {
          context.pop<ShoppingSupplier>(selected);
        }
      } else {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(t('내 거래처에 등록했습니다. 다음 선택부터 먼저 표시합니다.',
                'Added to your suppliers. It will appear first next time.'))));
        _load();
      }
    } catch (_) {
      if (mounted) {
        setState(() => _error = t('등록하지 못했습니다. 내 거래처 한도와 연결 상태를 확인해 주세요.',
            'Could not add. Check your supplier limit and connection.'));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Widget filter(String value, String label, Map<String, String> values,
          void Function(String) changed) =>
      _field(
          label,
          Semantics(
              label: label,
              child: DropdownButtonFormField<String>(
                  initialValue: value,
                  isExpanded: true,
                  items: [
                    DropdownMenuItem(value: '', child: Text(t('전체', 'All'))),
                    for (final e in values.entries)
                      DropdownMenuItem(
                          value: e.key,
                          child: Text(e.value,
                              maxLines: 1, overflow: TextOverflow.ellipsis))
                  ],
                  onChanged: _loading
                      ? null
                      : (v) {
                          setState(() => changed(v!));
                          _load();
                        })));

  Widget _field(String label, Widget input) =>
      Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text(label, style: Theme.of(context).textTheme.labelMedium),
        const SizedBox(height: 8),
        input,
      ]);

  Future<void> _openBusiness() async {
    final owner = ref.read(activeAccountIdProvider);
    await context.push('/supplier-business');
    if (!mounted || owner != ref.read(activeAccountIdProvider)) return;
    ref.invalidate(mySupplierBusinessProvider);
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    final business = ref.watch(mySupplierBusinessProvider).valueOrNull;
    final colors = Theme.of(context).colorScheme;
    final admin =
        ref.watch(membershipInfoProvider).valueOrNull?.isAdmin ?? false;
    final myReferences =
        (ref.watch(shoppingSuppliersProvider).valueOrNull ?? [])
            .map((s) => s.publicListingId)
            .whereType<String>()
            .toSet();
    final mine = (ref.watch(shoppingSuppliersProvider).valueOrNull ?? [])
        .map((s) => s.catalogSupplierId)
        .whereType<String>()
        .toSet();
    return Scaffold(
        appBar: AppBar(
            title: Text(t('공급업체 찾기', 'Find suppliers')),
            actions: const [GuideHelpButton(lesson: 'buy-suppliers')]),
        body: Center(
            child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 1100),
                child: ListView(padding: const EdgeInsets.all(20), children: [
                  Text(
                      t('익숙한 거래처부터, 새로운 공급업체까지',
                          'Your suppliers first. New connections next.'),
                      style: Theme.of(context).textTheme.headlineSmall),
                  const SizedBox(height: 8),
                  Text(t('선택하면 내 거래처로 등록됩니다. 내 거래처 → 다른 공개 업체 순서로 표시합니다.',
                      'Selecting a business adds it to your suppliers. Your suppliers appear before other listings.')),
                  const SizedBox(height: 16),
                  if (admin)
                    Align(
                        alignment: Alignment.centerLeft,
                        child: TextButton.icon(
                            onPressed: () => context
                                .push('/membership/admin/public-suppliers'),
                            icon: const Icon(Icons.manage_search),
                            label: Text(t('공개 업체 자료 관리',
                                'Manage public supplier listings')))),
                  Semantics(
                      button: true,
                      child: Material(
                          color: colors.primaryContainer,
                          borderRadius: BorderRadius.circular(18),
                          clipBehavior: Clip.antiAlias,
                          child: InkWell(
                              key: const ValueKey('supplier-business-entry'),
                              onTap: _openBusiness,
                              child: Padding(
                                  padding: const EdgeInsets.all(16),
                                  child: Row(children: [
                                    Icon(Icons.storefront_outlined,
                                        color: colors.onPrimaryContainer),
                                    const SizedBox(width: 12),
                                    Expanded(
                                        child: Column(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            children: [
                                          Text(
                                              business == null
                                                  ? t('업체·상품 등록',
                                                      'Register business & products')
                                                  : t('내 업체·상품 관리',
                                                      'Manage my business & products'),
                                              style: Theme.of(context)
                                                  .textTheme
                                                  .titleSmall
                                                  ?.copyWith(
                                                      color: colors
                                                          .onPrimaryContainer)),
                                          const SizedBox(height: 4),
                                          Text(
                                              business == null
                                                  ? t('식자재 공급업체이신가요? 업체 정보와 상품 사진을 등록하세요.',
                                                      'Supply ingredients? Add your business details and product photos.')
                                                  : t('등록한 업체 정보, 취급 상품과 사진을 수정할 수 있습니다.',
                                                      'Update your business details, products and photos.'),
                                              style: Theme.of(context)
                                                  .textTheme
                                                  .bodySmall
                                                  ?.copyWith(
                                                      color: colors
                                                          .onPrimaryContainer)),
                                        ])),
                                    const SizedBox(width: 8),
                                    Icon(Icons.arrow_forward,
                                        color: colors.onPrimaryContainer),
                                  ]))))),
                  const SizedBox(height: 20),
                  TextField(
                      controller: _query,
                      onSubmitted: (_) => _load(),
                      decoration: InputDecoration(
                          labelText: t(
                              '재료·상품·업체 이름', 'Ingredient, product or business'),
                          prefixIcon: const Icon(Icons.search),
                          suffixIcon: IconButton(
                              onPressed: _loading ? null : () => _load(),
                              icon: const Icon(Icons.arrow_forward)))),
                  const SizedBox(height: 20),
                  ExpansionTile(
                      initiallyExpanded: true,
                      tilePadding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 4),
                      childrenPadding: const EdgeInsets.fromLTRB(12, 8, 12, 20),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(18),
                          side: BorderSide(color: colors.outlineVariant)),
                      collapsedShape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(18),
                          side: BorderSide(color: colors.outlineVariant)),
                      backgroundColor: Colors.transparent,
                      leading: const Icon(Icons.tune),
                      title: Text(t(
                          '분류·지역·브랜드 조건', 'Category, region & brand filters')),
                      subtitle: [
                        _category,
                        _subcategory,
                        _region,
                        _origin,
                        _brand.text
                      ].every((v) => v.isEmpty)
                          ? null
                          : Text([
                              if (_category.isNotEmpty)
                                supplierCategoryLabel(_category, en),
                              if (_subcategory.isNotEmpty)
                                supplierCategoryLabel(_subcategory, en),
                              if (_region.isNotEmpty)
                                supplierRegionLabel(_region, en),
                              if (_origin.isNotEmpty) t('원산지', 'Origin'),
                              if (_brand.text.isNotEmpty) _brand.text,
                            ].join(' · ')),
                      children: [
                        LayoutBuilder(builder: (context, constraints) {
                          final columns =
                              MediaQuery.textScalerOf(context).scale(16) > 21
                                  ? 1
                                  : constraints.maxWidth >= 720
                                      ? 3
                                      : constraints.maxWidth >= 300
                                          ? 2
                                          : 1;
                          final width =
                              (constraints.maxWidth - (columns - 1) * 12) /
                                  columns;
                          final fields = <Widget>[
                            filter(_category, t('품목 대분류', 'Category'), {
                              for (final c in supplierCategories.keys)
                                c: supplierCategoryLabel(c, en)
                            }, (v) {
                              _category = v;
                              _subcategory = '';
                            }),
                            KeyedSubtree(
                                key: ValueKey(_category),
                                child: filter(
                                    _subcategory,
                                    t('소분류', 'Subcategory'),
                                    {
                                      for (final c
                                          in supplierCategories[_category]
                                                  ?.$3 ??
                                              <String>[])
                                        c: supplierCategoryLabel(c, en)
                                    },
                                    (v) => _subcategory = v)),
                            filter(
                                _region,
                                t('배송 지역', 'Delivery region'),
                                {
                                  for (final r in supplierRegions
                                      .where((r) => r != '전국'))
                                    r: supplierRegionLabel(r, en)
                                },
                                (v) => _region = v),
                            filter(
                                _origin,
                                t('원산지', 'Origin'),
                                {
                                  'domestic': t('국산', 'Domestic (Korea)'),
                                  'imported': t('수입', 'Imported'),
                                  'mixed': t('혼합', 'Mixed'),
                                  'unknown': t('확인 필요', 'To confirm')
                                },
                                (v) => _origin = v),
                            _field(
                                t('브랜드', 'Brand'),
                                TextField(
                                    controller: _brand,
                                    onSubmitted: (_) => _load(),
                                    decoration: InputDecoration(
                                        hintText: t('브랜드 이름', 'Brand name'),
                                        suffixIcon: IconButton(
                                            onPressed:
                                                _loading ? null : () => _load(),
                                            icon: const Icon(Icons.search))))),
                          ];
                          return Wrap(spacing: 12, runSpacing: 20, children: [
                            for (var i = 0; i < fields.length; i++)
                              SizedBox(
                                  width: columns == 2 && i == fields.length - 1
                                      ? constraints.maxWidth
                                      : width,
                                  child: fields[i]),
                          ]);
                        })
                      ]),
                  const SizedBox(height: 16),
                  Wrap(spacing: 8, runSpacing: 4, children: [
                    FilterChip(
                        label: Text(t('가격 공개', 'Listed price')),
                        selected: _priced,
                        onSelected: _loading
                            ? null
                            : (v) {
                                setState(() => _priced = v);
                                _load();
                              }),
                    FilterChip(
                        label: Text(t('평점 4 이상', 'Rating 4+')),
                        selected: _rated,
                        onSelected: _loading
                            ? null
                            : (v) {
                                setState(() => _rated = v);
                                _load();
                              }),
                    FilterChip(
                        label: Text(t('사업자 확인됨', 'Verified business')),
                        selected: _verified,
                        onSelected: _loading
                            ? null
                            : (v) {
                                setState(() => _verified = v);
                                _load();
                              }),
                  ]),
                  if (_loading) const LinearProgressIndicator(),
                  if (_error != null) Text(_error!),
                  if (!_loading && _offers.isEmpty && _references.isEmpty)
                    Padding(
                        padding: const EdgeInsets.all(24),
                        child: Text(t(
                            '조건에 맞는 상품이 없습니다. 별칭을 검색하거나 분류·지역 조건을 넓혀 보세요.',
                            'No matching products. Try an alias or broader category and region.'))),
                  for (final o in _offers)
                    SupplierOfferCard(
                        offer: o,
                        isMine: mine.contains(o.supplier.id),
                        action: TextButton.icon(
                            onPressed: _saving ? null : () => _select(o),
                            icon: Icon(mine.contains(o.supplier.id)
                                ? Icons.check_circle_outline
                                : Icons.add_business_outlined),
                            label: Text(widget.selectMode
                                ? t('이 업체 선택', 'Select supplier')
                                : mine.contains(o.supplier.id)
                                    ? t('내 거래처', 'My supplier')
                                    : t('내 거래처로 선택', 'Add to my suppliers')))),
                  if (_more)
                    TextButton(
                        onPressed: _loading ? null : () => _load(more: true),
                        child: Text(t('더 보기', 'Load more'))),
                  if (_references.isNotEmpty) ...[
                    const SizedBox(height: 24),
                    Text(t('공개 자료로 찾은 공급업체', 'Suppliers from public sources'),
                        style: Theme.of(context).textTheme.titleLarge),
                    Text(t('취급 상품과 배송 조건을 확인한 후 내 거래처로 추가하세요.',
                        'Check product and delivery terms before adding a supplier.')),
                    for (final s in _references)
                      PublicSupplierCard(
                          supplier: s,
                          action: TextButton.icon(
                              onPressed: _saving
                                  ? null
                                  : () => _selectSupplier(() => ref
                                      .read(supplierCatalogRepositoryProvider)
                                      .selectPublicReference(s.id)),
                              icon: Icon(myReferences.contains(s.id)
                                  ? Icons.check_circle_outline
                                  : Icons.add_business_outlined),
                              label: Text(widget.selectMode
                                  ? t('이 업체 선택', 'Select supplier')
                                  : myReferences.contains(s.id)
                                      ? t('내 거래처', 'My supplier')
                                      : t('내 거래처로 선택',
                                          'Add to my suppliers')))),
                  ],
                ]))));
  }
}

class SupplierOfferCard extends StatelessWidget {
  const SupplierOfferCard(
      {super.key,
      required this.offer,
      required this.isMine,
      required this.action});
  final SupplierOffer offer;
  final bool isMine;
  final Widget action;
  @override
  Widget build(BuildContext context) {
    String t(String ko, String en) => catalogText(context, ko, en);
    final en = Localizations.localeOf(context).languageCode != 'ko';
    final p = offer.product, s = offer.supplier;
    return Card(
        margin: const EdgeInsets.symmetric(vertical: 8),
        child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    SupplierProductImage(p.imagePath),
                    const SizedBox(width: 12),
                    Expanded(
                        child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                          Text(p.name,
                              style: Theme.of(context).textTheme.titleMedium),
                          LocalizedText(
                              '${s.name} · ${supplierRegionLabel(s.region, en)}'),
                          if (isMine)
                            Text(
                                t('내 거래처 · 우선 표시', 'My supplier · shown first'),
                                style: TextStyle(
                                    color:
                                        Theme.of(context).colorScheme.primary,
                                    fontWeight: FontWeight.bold)),
                          LocalizedText(
                              '${shoppingNumber(p.contentQuantity)} ${p.contentUnit}/${p.saleUnit} · ${p.brand}'),
                        ]))
                  ]),
                  const SizedBox(height: 10),
                  LocalizedText(p.priceCurrent(DateTime.now()) && p.tax != 'unknown'
                      ? '${shoppingNumber(p.price)} ${s.currency}/${p.saleUnit} · ${t('가격 유효일', 'Valid until')} ${p.priceValidUntil!.toIso8601String().substring(0, 10)}'
                      : t('가격·세금 견적 필요', 'Price/tax quote needed')),
                  LocalizedText(
                      '${t('배송비', 'Delivery')}: ${shoppingNumber(s.shippingFee)} ${s.currency} · ${t('최소 주문', 'Minimum order')}: ${shoppingNumber(s.minimumOrder)} ${s.currency}'),
                  LocalizedText(s.rating == null
                      ? t('평가 없음', 'No ratings')
                      : '★ ${s.rating!.toStringAsFixed(1)} · ${s.reviewCount}${t('명 구매자 입고 확인 평가', ' buyer-confirmed receipt ratings')}'),
                  Text(
                      s.verified
                          ? t('사업자 확인됨', 'Business verified')
                          : t('업체 직접 등록 · 사업자 미확인',
                              'Self-registered · business unverified'),
                      style: Theme.of(context).textTheme.bodySmall),
                  Align(alignment: Alignment.centerRight, child: action),
                ])));
  }
}
