import '../../../core/localization/localized_text.dart';
import '../../../core/auth/auth_return.dart';
import '../../guide/presentation/guide_help_button.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/scout_page.dart';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import '../../auth/application/auth_providers.dart';
import '../../shopping/domain/shopping_assistant.dart';
import '../../shopping/domain/supplier_request.dart';
import '../../shopping/presentation/shopping_assistant_dialogs.dart';
import '../data/supplier_catalog_repository.dart';
import '../domain/supplier_catalog.dart';
import '../../shopping/presentation/record_management.dart';

String catalogText(BuildContext c, String ko, String en) => shopText(c, ko, en);

class SupplierProductImage extends ConsumerWidget {
  const SupplierProductImage(this.path, {super.key, this.size = 80});
  final String path;
  final double size;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final url = ref.watch(supplierProductImageProvider(path));
    final placeholder = ColoredBox(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        child: const Center(child: Icon(Icons.photo_outlined)));
    return ClipRRect(
        borderRadius: BorderRadius.circular(14),
        child: SizedBox(
            width: size,
            height: size,
            child: url.when(
                data: (value) => Image.network(value,
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => placeholder),
                error: (_, __) => placeholder,
                loading: () => placeholder)));
  }
}

class SupplierBusinessPage extends ConsumerStatefulWidget {
  const SupplierBusinessPage({super.key, this.section = 'overview'});
  final String section;
  @override
  ConsumerState<SupplierBusinessPage> createState() =>
      _SupplierBusinessPageState();
}

class _SupplierBusinessPageState extends ConsumerState<SupplierBusinessPage> {
  String _query = '';
  bool _includeInactive = true;
  String get section => widget.section;
  @override
  Widget build(BuildContext context) {
    String t(String ko, String en) => catalogText(context, ko, en);
    final owner = ref.watch(activeAccountIdProvider);
    if (owner == null) {
      return Scaffold(
          appBar: AppBar(
              title: Text(t('내 업체 등록', 'Register my business')),
              actions: const [GuideHelpButton(lesson: 'supplier-profile')]),
          body: Center(
              child: FilledButton(
                  onPressed: () => context.push(loginFor(
                      GoRouterState.of(context).uri.toString(),
                      resume: true)),
                  child: Text(t('로그인', 'Sign in')))));
    }
    final business = ref.watch(mySupplierBusinessProvider);
    Future<void> edit(CatalogSupplier? b) async {
      await showDialog(
          context: context,
          barrierDismissible: false,
          builder: (_) => ShoppingAccountGuard(child: _BusinessEditor(b)));
      if (context.mounted && ref.read(activeAccountIdProvider) == owner) {
        ref.invalidate(mySupplierBusinessProvider);
      }
    }

    Future<void> editProduct(CatalogSupplier b,
        [CatalogProduct? product]) async {
      await showDialog(
          context: context,
          barrierDismissible: false,
          builder: (_) =>
              ShoppingAccountGuard(child: _ProductEditor(b, product: product)));
      if (context.mounted && ref.read(activeAccountIdProvider) == owner) {
        ref.invalidate(myCatalogProductsProvider(b.id));
      }
    }

    Future<void> changeProductState(CatalogSupplier b, CatalogProduct p) async {
      final yes = await confirmRecordManagement(
          context,
          p.active ? t('판매 중지', 'Inactive') : t('판매 재개', 'Resume selling'),
          p.active
              ? t('새 구매에서 이 상품을 숨깁니다. 기존 구매요청서는 유지됩니다.',
                  'Hide this product from new purchases. Existing requests are preserved.')
              : t('업체가 공개 상태이면 이 상품이 고객에게 다시 표시됩니다. 규격과 가격을 확인해 주세요.',
                  'If the business is published, customers will see this product again. Check its specification and price.'));
      if (!yes ||
          !context.mounted ||
          owner != ref.read(activeAccountIdProvider)) {
        return;
      }
      await ref
          .read(supplierCatalogRepositoryProvider)
          .saveProduct(CatalogProduct.fromJson({
            ...p.toJson(),
            'revision': p.revision,
            'active': !p.active,
          }));
      if (context.mounted && owner == ref.read(activeAccountIdProvider)) {
        ref.invalidate(myCatalogProductsProvider(b.id));
      }
    }

    Future<void> changePublication(CatalogSupplier b) async {
      final yes = await showDialog<bool>(
          context: context,
          builder: (ctx) => ShoppingAccountGuard(
                  child: AlertDialog(
                      scrollable: true,
                      title: Text(b.published
                          ? t('비공개로 전환', 'Unpublish')
                          : t('업체 공개하기', 'Publish business')),
                      content: Text(b.published
                          ? t('업체와 상품이 검색에서 제외됩니다. 기존 구매 요청서는 보존됩니다.',
                              'Hide this business and its products from search. Existing requests remain.')
                          : t('업체명·담당자·연락처·주소와 상품 정보가 로그인한 모든 회원(무료·유료)에게 공개됩니다. 모든 판매 중 상품에 사진을 등록해 주세요.',
                              'Your business, contact, address and products will be visible to all signed-in members on free and paid plans. Every active product needs a photo.')),
                      actions: [
                    TextButton(
                        onPressed: () => Navigator.pop(ctx, false),
                        child: Text(t('취소', 'Cancel'))),
                    FilledButton(
                        onPressed: () => Navigator.pop(ctx, true),
                        child: Text(t('확인', 'Confirm'))),
                  ])));
      if (yes != true ||
          !context.mounted ||
          ref.read(activeAccountIdProvider) != owner) {
        return;
      }
      try {
        await ref.read(supplierCatalogRepositoryProvider).saveBusiness(
                CatalogSupplier.fromJson({
              ...b.toJson(),
              'published': !b.published,
              'revision': b.revision
            }));
        if (context.mounted && ref.read(activeAccountIdProvider) == owner) {
          ref.invalidate(mySupplierBusinessProvider);
        }
      } catch (_) {
        if (context.mounted && ref.read(activeAccountIdProvider) == owner) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
              content: Text(t('저장하지 못했습니다. 상품 사진과 연결 상태를 확인한 뒤 새로고침해 주세요.',
                  'Could not save. Check product photos and connection, then refresh.'))));
        }
      }
    }

    return Scaffold(
        appBar: AppBar(
            title: Text(section == 'products'
                ? t('상품·가격', 'Products & prices')
                : section == 'terms'
                    ? t('거래조건', 'Trade terms')
                    : t('업체 정보', 'Business profile')),
            actions: [
              IconButton(
                  tooltip: t('새로고침', 'Refresh'),
                  onPressed: () {
                    ref.invalidate(mySupplierBusinessProvider);
                    final b = business.valueOrNull;
                    if (b != null) {
                      ref.invalidate(myCatalogProductsProvider(b.id));
                    }
                  },
                  icon: const Icon(Icons.refresh)),
              const GuideHelpButton(lesson: 'supplier-profile')
            ]),
        body: business.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (_, __) => Center(
                child: TextButton(
                    onPressed: () => ref.invalidate(mySupplierBusinessProvider),
                    child: Text(t('다시 불러오기', 'Reload')))),
            data: (b) => Center(
                child: ConstrainedBox(
                    constraints: const BoxConstraints(
                        maxWidth: ScoutStyle.workspaceWidth),
                    child:
                        ListView(padding: const EdgeInsets.all(20), children: [
                      ScoutPageHeading(
                        title: section == 'products'
                            ? t('구매자가 찾는 상품 목록', 'Products for your buyers')
                            : section == 'terms'
                                ? t('배송과 주문 기준',
                                    'Delivery and order conditions')
                                : t('내 업체 관리', 'Manage your business'),
                        eyebrow: t('공급업체 작업공간', 'SUPPLIER WORKSPACE'),
                        subtitle: section == 'products'
                            ? t('사진과 판매 단위, 가격을 최신 정보로 관리하세요.',
                                'Keep photos, sale units and prices up to date.')
                            : section == 'terms'
                                ? t('배송 지역과 비용을 명확히 안내하면 거래가 편해집니다.',
                                    'Clear delivery regions and costs help buyers plan their orders.')
                                : t('업체 정보와 상품, 거래조건을 한곳에서 관리하세요.',
                                    'Maintain your business, products and trade terms in one place.'),
                        icon: Icons.storefront_outlined,
                      ),
                      const SizedBox(height: 24),
                      if (b == null) ...[
                        Container(
                            padding: const EdgeInsets.all(24),
                            decoration: BoxDecoration(
                                color: ScoutStyle.mint,
                                borderRadius: BorderRadius.circular(24)),
                            child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Icon(Icons.storefront_outlined,
                                      size: 36, color: ScoutStyle.forest),
                                  const SizedBox(height: 16),
                                  Text(
                                      t('구매자가 찾고, 다시 거래하는 업체로',
                                          'Help buyers find your business'),
                                      style: Theme.of(context)
                                          .textTheme
                                          .headlineSmall),
                                  const SizedBox(height: 12),
                                  Text(t(
                                      '필수 항목부터 입력하세요. 배송비와 상품 가격은 나중에 추가해도 됩니다.',
                                      'Start with required details. Delivery fees and product prices can be added later.')),
                                  const SizedBox(height: 20),
                                  FilledButton.icon(
                                      onPressed: () => edit(null),
                                      icon: const Icon(
                                          Icons.add_business_outlined),
                                      label: Text(t(
                                          '업체 정보 입력', 'Add business details'))),
                                ])),
                        const SizedBox(height: 20),
                        Text(t('1 업체 정보 → 2 상품과 사진 → 3 공개하기',
                            '1 Business details → 2 Products & photos → 3 Publish')),
                        const SizedBox(height: 12),
                        _publicationNotice(context),
                      ] else ...[
                        Card(
                            margin: EdgeInsets.zero,
                            child: Padding(
                                padding: const EdgeInsets.all(20),
                                child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Wrap(
                                          spacing: 12,
                                          runSpacing: 8,
                                          crossAxisAlignment:
                                              WrapCrossAlignment.center,
                                          children: [
                                            Text(b.name,
                                                style: Theme.of(context)
                                                    .textTheme
                                                    .headlineSmall),
                                            _SupplierStatus(
                                                label: b.published
                                                    ? t('공개 중', 'Published')
                                                    : t('비공개 초안',
                                                        'Private draft'),
                                                icon: b.published
                                                    ? Icons.visibility_outlined
                                                    : Icons
                                                        .visibility_off_outlined,
                                                active: b.published),
                                          ]),
                                      const SizedBox(height: 10),
                                      LocalizedText(
                                          '${supplierRegionLabel(b.region, Localizations.localeOf(context).languageCode != 'ko')} · ${b.phone}'),
                                      const SizedBox(height: 8),
                                      Text(
                                          b.published
                                              ? t('전체 회원에게 공개 중 · 업체가 직접 등록한 정보',
                                                  'Visible to all members · supplier-provided information')
                                              : t('업체와 상품을 검토한 뒤 공개해 주세요.',
                                                  'Review your business and products before publishing.'),
                                          style: Theme.of(context)
                                              .textTheme
                                              .bodySmall),
                                      const SizedBox(height: 12),
                                      Wrap(
                                          spacing: 8,
                                          runSpacing: 8,
                                          children: [
                                            OutlinedButton.icon(
                                                onPressed: () => edit(b),
                                                icon: const Icon(
                                                    Icons.edit_outlined,
                                                    size: 18),
                                                label: Text(t('업체 정보 수정',
                                                    'Edit business'))),
                                            TextButton.icon(
                                                onPressed: () =>
                                                    changePublication(b),
                                                icon: Icon(
                                                    b.published
                                                        ? Icons
                                                            .visibility_off_outlined
                                                        : Icons
                                                            .visibility_outlined,
                                                    size: 18),
                                                label: Text(b.published
                                                    ? t('비공개로 전환', 'Unpublish')
                                                    : t('공개하기', 'Publish'))),
                                          ]),
                                    ]))),
                        const SizedBox(height: 16),
                        if (section != 'products') ...[
                          _SupplierTermsSummary(
                              business: b,
                              expanded: section == 'terms',
                              onEdit: () => edit(b)),
                          const SizedBox(height: 16),
                        ],
                        if (section != 'terms') ...[
                          Wrap(
                              alignment: WrapAlignment.spaceBetween,
                              crossAxisAlignment: WrapCrossAlignment.center,
                              spacing: 16,
                              runSpacing: 12,
                              children: [
                                Text(t('취급 상품', 'Products'),
                                    style:
                                        Theme.of(context).textTheme.titleLarge),
                                FilledButton.icon(
                                    onPressed: () => editProduct(b),
                                    icon: const Icon(
                                        Icons.add_photo_alternate_outlined),
                                    label:
                                        Text(t('취급 상품 추가', 'Add a product'))),
                              ]),
                          const SizedBox(height: 12),
                          ref.watch(myCatalogProductsProvider(b.id)).when(
                              loading: () => const LinearProgressIndicator(),
                              error: (_, __) => TextButton(
                                  onPressed: () => ref.invalidate(
                                      myCatalogProductsProvider(b.id)),
                                  child:
                                      Text(t('상품 다시 불러오기', 'Reload products'))),
                              data:
                                  (products) => Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.stretch,
                                          children: [
                                            if (products.isEmpty)
                                              Card(
                                                  child: Padding(
                                                      padding:
                                                          const EdgeInsets.all(
                                                              24),
                                                      child: Column(children: [
                                                        const Icon(
                                                            Icons
                                                                .inventory_2_outlined,
                                                            size: 32,
                                                            color: ScoutStyle
                                                                .forest),
                                                        const SizedBox(
                                                            height: 12),
                                                        Text(t(
                                                            '대표 상품 1개부터 등록해 보세요.',
                                                            'Start with one representative product.')),
                                                      ]))),
                                            if (products.isNotEmpty) ...[
                                              Wrap(
                                                  spacing: 8,
                                                  runSpacing: 8,
                                                  children: [
                                                    _SupplierStatus(
                                                        label:
                                                            '${t('판매 중', 'Active')} ${products.where((p) => p.active).length}',
                                                        icon: Icons
                                                            .check_circle_outline,
                                                        active: true),
                                                    _SupplierStatus(
                                                        label:
                                                            '${t('판매 중지', 'Inactive')} ${products.where((p) => !p.active).length}',
                                                        icon: Icons
                                                            .pause_circle_outline,
                                                        active: false),
                                                  ]),
                                              const SizedBox(height: 12),
                                              TextField(
                                                  decoration: InputDecoration(
                                                      labelText: t('상품명·브랜드 검색',
                                                          'Search product or brand'),
                                                      prefixIcon: const Icon(
                                                          Icons.search)),
                                                  onChanged: (v) => setState(
                                                      () => _query = v
                                                          .trim()
                                                          .toLowerCase())),
                                              SwitchListTile(
                                                  contentPadding:
                                                      EdgeInsets.zero,
                                                  title: Text(t('판매 중지 상품 포함',
                                                      'Include inactive products')),
                                                  value: _includeInactive,
                                                  onChanged: (v) => setState(
                                                      () => _includeInactive =
                                                          v)),
                                              LayoutBuilder(builder:
                                                  (context, constraints) {
                                                final columns = constraints
                                                                .maxWidth >=
                                                            840 &&
                                                        MediaQuery.textScalerOf(
                                                                    context)
                                                                .scale(14) <
                                                            21
                                                    ? 2
                                                    : 1;
                                                return Wrap(
                                                    spacing: 12,
                                                    runSpacing: 12,
                                                    children: [
                                                      for (final p
                                                          in products.where((p) =>
                                                              (_includeInactive ||
                                                                  p.active) &&
                                                              '${p.name} ${p.brand} ${p.aliases}'
                                                                  .toLowerCase()
                                                                  .contains(
                                                                      _query)))
                                                        SizedBox(
                                                            width: (constraints
                                                                        .maxWidth -
                                                                    (columns -
                                                                            1) *
                                                                        12) /
                                                                columns,
                                                            child:
                                                                _SupplierProductCard(
                                                                    product: p,
                                                                    currency: b
                                                                        .currency,
                                                                    onEdit: () =>
                                                                        editProduct(
                                                                            b, p),
                                                                    actions: RecordManagementMenu(
                                                                        actions: [
                                                                          RecordManagementAction(
                                                                              'erase',
                                                                              t('영구 삭제',
                                                                                  'Delete permanently'),
                                                                              Icons.delete_forever,
                                                                              () async {
                                                                            if (await manageOwnerRecord(context, ref, kind: 'product', id: p.id) !=
                                                                                null) {
                                                                              ref.invalidate(myCatalogProductsProvider(b.id));
                                                                              ref.invalidate(mySupplierBusinessProvider);
                                                                            }
                                                                          }),
                                                                          RecordManagementAction(
                                                                              'copy',
                                                                              t('복사해서 만들기', 'Create a copy'),
                                                                              Icons.copy_outlined,
                                                                              () => editProduct(b, p.draftCopy(newShoppingId()))),
                                                                          RecordManagementAction(
                                                                              'active',
                                                                              p.active ? t('판매 중지', 'Inactive') : t('판매 재개', 'Resume selling'),
                                                                              p.active ? Icons.pause_circle_outline : Icons.play_circle_outline,
                                                                              () => changeProductState(b, p)),
                                                                        ]))),
                                                    ]);
                                              }),
                                            ],
                                          ])),
                        ],
                        const SizedBox(height: 20),
                        _publicationNotice(context),
                      ],
                    ])))));
  }

  Widget _publicationNotice(BuildContext context) => Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Text(
          catalogText(context, '공개하면 무료·유료 구분 없이 로그인한 모든 회원이 업체와 상품을 볼 수 있습니다.',
              'Once published, your business and products are visible to all signed-in members, on free and paid plans.'),
          style: Theme.of(context).textTheme.bodySmall));
}

class _SupplierStatus extends StatelessWidget {
  const _SupplierStatus(
      {required this.label, required this.icon, required this.active});
  final String label;
  final IconData icon;
  final bool active;
  @override
  Widget build(BuildContext context) => Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
          color: active
              ? ScoutStyle.mint
              : Theme.of(context).colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(12)),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(icon, size: 18, color: ScoutStyle.forest),
        const SizedBox(width: 6),
        Flexible(
            child: Text(label, style: Theme.of(context).textTheme.labelLarge)),
      ]));
}

class _SupplierTermsSummary extends StatelessWidget {
  const _SupplierTermsSummary(
      {required this.business, required this.expanded, required this.onEdit});
  final CatalogSupplier business;
  final bool expanded;
  final VoidCallback onEdit;
  @override
  Widget build(BuildContext context) {
    String t(String ko, String en) => catalogText(context, ko, en);
    final b = business;
    Widget detail(String label, String value) => Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(label, style: Theme.of(context).textTheme.labelMedium),
          const SizedBox(height: 4),
          Text(value, style: Theme.of(context).textTheme.titleSmall),
        ]));
    final children = [
      detail(
          t('배송 지역', 'Delivery regions'),
          b.deliveryRegions
              .map((r) => supplierRegionLabel(
                  r, Localizations.localeOf(context).languageCode != 'ko'))
              .join(', ')),
      detail(t('최소 주문금액', 'Minimum order'),
          '${shoppingNumber(b.minimumOrder)} ${b.currency}'),
      detail(
          t('배송비', 'Delivery fee'),
          b.shippingFee == null
              ? t('견적 시 확인', 'Confirm in quote')
              : '${shoppingNumber(b.shippingFee!)} ${b.currency}'),
      detail(
          t('무료배송 기준', 'Free delivery from'),
          b.freeShippingFrom == null
              ? t('견적 시 확인', 'Confirm in quote')
              : '${shoppingNumber(b.freeShippingFrom!)} ${b.currency}'),
      TextButton.icon(
          onPressed: onEdit,
          icon: const Icon(Icons.edit_outlined, size: 18),
          label: Text(t('거래조건 수정', 'Edit trade terms'))),
    ];
    return Card(
        margin: EdgeInsets.zero,
        child: expanded
            ? Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(t('거래조건', 'Trade terms'),
                          style: Theme.of(context).textTheme.titleLarge),
                      const SizedBox(height: 16),
                      ...children,
                    ]))
            : ExpansionTile(
                key: const PageStorageKey('supplier-trade-summary'),
                leading: const Icon(Icons.local_shipping_outlined),
                title: Text(t('배송·주문 조건', 'Delivery & order terms')),
                subtitle: Text(b.deliveryRegions
                    .map((r) => supplierRegionLabel(r,
                        Localizations.localeOf(context).languageCode != 'ko'))
                    .join(', ')),
                childrenPadding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
                expandedCrossAxisAlignment: CrossAxisAlignment.start,
                children: children));
  }
}

class _SupplierProductCard extends StatelessWidget {
  const _SupplierProductCard(
      {required this.product,
      required this.currency,
      required this.onEdit,
      this.actions});
  final Widget? actions;
  final CatalogProduct product;
  final String currency;
  final VoidCallback onEdit;
  @override
  Widget build(BuildContext context) {
    String t(String ko, String en) => catalogText(context, ko, en);
    final p = product;
    return Card(
        margin: EdgeInsets.zero,
        clipBehavior: Clip.antiAlias,
        child: InkWell(
            onTap: onEdit,
            child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      LayoutBuilder(builder: (context, constraints) {
                        final description = Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(p.name,
                                  style:
                                      Theme.of(context).textTheme.titleMedium),
                              const SizedBox(height: 6),
                              LocalizedText(
                                  '${shoppingNumber(p.contentQuantity)} ${p.contentUnit}/${p.saleUnit}'),
                            ]);
                        final photo =
                            SupplierProductImage(p.imagePath, size: 64);
                        if (constraints.maxWidth < 300 ||
                            MediaQuery.textScalerOf(context).scale(14) >= 28) {
                          return Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                photo,
                                const SizedBox(height: 12),
                                description,
                              ]);
                        }
                        return Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              photo,
                              const SizedBox(width: 14),
                              Expanded(child: description),
                            ]);
                      }),
                      const SizedBox(height: 14),
                      LocalizedText(
                          p.price == null
                              ? t('가격: 견적 필요', 'Price: request a quote')
                              : '${shoppingNumber(p.price!)} $currency / ${p.saleUnit}',
                          style: Theme.of(context)
                              .textTheme
                              .titleSmall
                              ?.copyWith(color: ScoutStyle.forest)),
                      if (p.priceValidUntil != null) ...[
                        const SizedBox(height: 4),
                        LocalizedText(
                            '${t('가격 유효일', 'Price valid until')}: ${p.priceValidUntil!.toIso8601String().split('T').first}',
                            style: Theme.of(context).textTheme.bodySmall),
                      ],
                      const SizedBox(height: 12),
                      Wrap(
                          alignment: WrapAlignment.spaceBetween,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            _SupplierStatus(
                                label: p.active
                                    ? t('판매 중', 'Active')
                                    : t('판매 중지', 'Inactive'),
                                icon: p.active
                                    ? Icons.check_circle_outline
                                    : Icons.pause_circle_outline,
                                active: p.active),
                            TextButton.icon(
                                onPressed: onEdit,
                                icon: const Icon(Icons.edit_outlined, size: 18),
                                label: Text(t('수정', 'Edit'))),
                            if (actions != null) actions!,
                          ]),
                    ]))));
  }
}

class _BusinessEditor extends ConsumerStatefulWidget {
  const _BusinessEditor(this.business);
  final CatalogSupplier? business;
  @override
  ConsumerState<_BusinessEditor> createState() => _BusinessEditorState();
}

class _BusinessEditorState extends ConsumerState<_BusinessEditor> {
  final _form = GlobalKey<FormState>();
  late final _b = widget.business;
  late final _id = _b?.id ?? newShoppingId();
  late final _name = TextEditingController(text: _b?.name),
      _contact = TextEditingController(text: _b?.contact),
      _phone = TextEditingController(text: _b?.phone),
      _address = TextEditingController(text: _b?.address),
      _website = TextEditingController(text: _b?.website),
      _description = TextEditingController(text: _b?.description);
  late final _fee = TextEditingController(
          text: _b?.shippingFee == null ? '' : shoppingNumber(_b!.shippingFee)),
      _free = TextEditingController(
          text: _b?.freeShippingFrom == null
              ? ''
              : shoppingNumber(_b!.freeShippingFrom)),
      _minimum =
          TextEditingController(text: shoppingNumber(_b?.minimumOrder ?? 0));
  late String _region = _b?.region ?? '서울', _currency = _b?.currency ?? 'KRW';
  late final _delivery = {...?_b?.deliveryRegions};
  bool _busy = false;
  String? _error;
  String t(String ko, String en) => catalogText(context, ko, en);
  @override
  void dispose() {
    for (final c in [
      _name,
      _contact,
      _phone,
      _address,
      _website,
      _description,
      _fee,
      _free,
      _minimum
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  Widget field(TextEditingController c, String label, int max,
          {bool required = false, bool amount = false}) =>
      Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: TextFormField(
              controller: c,
              enabled: !_busy,
              maxLength: max,
              decoration: InputDecoration(labelText: label),
              validator: (v) {
                if (required && (v ?? '').trim().isEmpty) {
                  return t('필수 항목입니다.', 'Required.');
                }
                if (amount && (v ?? '').trim().isNotEmpty) {
                  final n = shoppingInput(v!);
                  if (n == null || n < 0 || n > 1e12) {
                    return t('금액을 확인해 주세요.', 'Check the amount.');
                  }
                }
                if (c == _website &&
                    (v ?? '').trim().isNotEmpty &&
                    shoppingProductUri(v!) == null) {
                  return t(
                      'https 주소를 입력해 주세요.', 'Enter a valid HTTPS address.');
                }
                return null;
              }));
  @override
  Widget build(BuildContext context) => PopScope(
      canPop: !_busy,
      child: Dialog.fullscreen(
          child: Scaffold(
              appBar: AppBar(
                  title: Text(t('업체 정보', 'Business details')),
                  actions: [
                    GuideHelpButton(lesson: 'supplier-profile', enabled: !_busy)
                  ],
                  leading: IconButton(
                      onPressed: _busy ? null : () => Navigator.pop(context),
                      icon: const Icon(Icons.close))),
              body: Center(
                  child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 720),
                      child: SingleChildScrollView(
                          padding: const EdgeInsets.all(20),
                          child: Form(
                              key: _form,
                              child: Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.stretch,
                                  children: [
                                    Text(t('* 필수 · 나머지는 선택 항목입니다.',
                                        '* Required · other fields are optional.')),
                                    const SizedBox(height: 16),
                                    field(_name, t('업체명 *', 'Business name *'),
                                        120,
                                        required: true),
                                    field(_contact,
                                        t('담당자 *', 'Contact name *'), 120,
                                        required: true),
                                    field(_phone,
                                        t('공개 연락처 *', 'Public phone *'), 60,
                                        required: true),
                                    DropdownButtonFormField<String>(
                                        initialValue: _region,
                                        decoration: InputDecoration(
                                            labelText: t('소재 지역 *',
                                                'Business region *')),
                                        items: [
                                          for (final r in supplierRegions
                                              .where((r) => r != '전국'))
                                            DropdownMenuItem(
                                                value: r,
                                                child: Text(supplierRegionLabel(
                                                    r,
                                                    Localizations.localeOf(
                                                                context)
                                                            .languageCode ==
                                                        'en')))
                                        ],
                                        onChanged: _busy
                                            ? null
                                            : (v) =>
                                                setState(() => _region = v!)),
                                    const SizedBox(height: 16),
                                    Text(t('배송 가능 지역 *', 'Delivery regions *')),
                                    Wrap(spacing: 6, runSpacing: 4, children: [
                                      for (final r in supplierRegions)
                                        FilterChip(
                                            label: Text(supplierRegionLabel(
                                                r,
                                                Localizations.localeOf(context)
                                                        .languageCode ==
                                                    'en')),
                                            selected: _delivery.contains(r),
                                            onSelected: _busy
                                                ? null
                                                : (yes) => setState(() => yes
                                                    ? _delivery.add(r)
                                                    : _delivery.remove(r)))
                                    ]),
                                    const SizedBox(height: 16),
                                    field(_address,
                                        t('사업장 주소', 'Business address'), 500),
                                    field(
                                        _website,
                                        t('홈페이지·카카오 채널 주소',
                                            'Website or Kakao channel URL'),
                                        2048),
                                    field(
                                        _description,
                                        t('업체 소개', 'About your business'),
                                        2000),
                                    DropdownButtonFormField<String>(
                                        initialValue: _currency,
                                        decoration: InputDecoration(
                                            labelText: t('거래 통화', 'Currency')),
                                        items: [
                                          for (final c in ['KRW', 'USD'])
                                            DropdownMenuItem(
                                                value: c, child: Text(c))
                                        ],
                                        onChanged: _busy
                                            ? null
                                            : (v) =>
                                                setState(() => _currency = v!)),
                                    const SizedBox(height: 16),
                                    field(
                                        _fee,
                                        t('기본 배송비 · 세금 포함 (공란: 견적 필요)',
                                            'Delivery fee incl. tax (blank: quote)'),
                                        20,
                                        amount: true),
                                    field(
                                        _free,
                                        t('무료배송 상품액 기준',
                                            'Free shipping from subtotal'),
                                        20,
                                        amount: true),
                                    field(
                                        _minimum,
                                        t('최소 주문금액', 'Minimum order subtotal'),
                                        20,
                                        amount: true),
                                    if (_error != null)
                                      Text(_error!,
                                          style: TextStyle(
                                              color: Theme.of(context)
                                                  .colorScheme
                                                  .error)),
                                  ]))))),
              bottomNavigationBar: SafeArea(
                  child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: FilledButton(
                          onPressed: _busy
                              ? null
                              : () async {
                                  if (!_form.currentState!.validate() ||
                                      _delivery.isEmpty) {
                                    setState(() => _error = t(
                                        '필수 항목과 배송 지역을 확인해 주세요.',
                                        'Check required fields and delivery regions.'));
                                    return;
                                  }
                                  setState(() => _busy = true);
                                  try {
                                    await ref
                                        .read(supplierCatalogRepositoryProvider)
                                        .saveBusiness(CatalogSupplier(
                                            id: _id,
                                            name: _name.text.trim(),
                                            contact: _contact.text.trim(),
                                            phone: _phone.text.trim(),
                                            region: _region,
                                            deliveryRegions: _delivery.toList(),
                                            address: _address.text.trim(),
                                            website: _website.text.trim(),
                                            description:
                                                _description.text.trim(),
                                            currency: _currency,
                                            shippingFee:
                                                shoppingInput(_fee.text),
                                            freeShippingFrom:
                                                shoppingInput(_free.text),
                                            minimumOrder:
                                                shoppingInput(_minimum.text) ??
                                                    0,
                                            published: _b?.published ?? false,
                                            revision: _b?.revision ?? 0));
                                    if (context.mounted) Navigator.pop(context);
                                  } catch (error) {
                                    if (mounted) {
                                      setState(() => _error = error
                                              .toString()
                                              .contains(
                                                  'CATALOG_CURRENCY_WITH_PRICES')
                                          ? t('상품 가격이 등록되어 있습니다. 각 상품의 가격을 비운 뒤 거래 통화를 변경하고 새 통화로 가격을 등록해 주세요.',
                                              'Products already have prices. Clear their prices before changing currency, then enter prices in the new currency.')
                                          : t('저장하지 못했습니다. 닫고 새로고침하여 저장 상태를 확인해 주세요.',
                                              'Could not confirm save. Close and refresh to check saved details.'));
                                    }
                                  } finally {
                                    if (mounted) setState(() => _busy = false);
                                  }
                                },
                          child: Text(
                              t('업체 정보 저장', 'Save business details'))))))));
}

class _ProductEditor extends ConsumerStatefulWidget {
  const _ProductEditor(this.business, {this.product});
  final CatalogSupplier business;
  final CatalogProduct? product;
  @override
  ConsumerState<_ProductEditor> createState() => _ProductEditorState();
}

class _ProductEditorState extends ConsumerState<_ProductEditor> {
  late final SupplierCatalogRepository _repository;
  final _temporaryImages = <String>{};
  @override
  void initState() {
    super.initState();
    _repository = ref.read(supplierCatalogRepositoryProvider);
  }

  Future<void> _discard(String path) async {
    try {
      await _repository.discardImage(path);
    } catch (_) {
      // Best effort. Server policy preserves referenced images after uncertain saves.
    }
  }

  final _form = GlobalKey<FormState>();
  late final _p = widget.product;
  late final _id = _p?.id ?? newShoppingId();
  late final _name = TextEditingController(text: _p?.name),
      _aliases = TextEditingController(text: _p?.aliases),
      _brand = TextEditingController(text: _p?.brand),
      _country = TextEditingController(text: _p?.country),
      _description = TextEditingController(text: _p?.description),
      _sale = TextEditingController(text: _p?.saleUnit ?? 'pack'),
      _unit = TextEditingController(text: _p?.contentUnit ?? 'kg'),
      _quantity =
          TextEditingController(text: shoppingNumber(_p?.contentQuantity ?? 1)),
      _minimum = TextEditingController(text: '${_p?.minimumPacks ?? 1}'),
      _price = TextEditingController(
          text: _p?.price == null ? '' : shoppingNumber(_p!.price)),
      _date = TextEditingController(
          text: _p?.priceValidUntil?.toIso8601String().substring(0, 10));
  late String _category = _p?.category ?? 'produce',
      _subcategory = _p?.subcategory ?? 'vegetables',
      _origin = _p?.origin ?? 'domestic',
      _storage = _p?.storage ?? 'ambient',
      _tax = _p?.tax ?? 'included',
      _image = _p?.imagePath ?? '';
  late bool _active = _p?.active ?? true;
  bool _busy = false;
  String? _error;
  String t(String ko, String en) => catalogText(context, ko, en);
  bool get en => Localizations.localeOf(context).languageCode != 'ko';
  @override
  void dispose() {
    for (final path in _temporaryImages) {
      unawaited(_discard(path));
    }
    for (final c in [
      _name,
      _aliases,
      _brand,
      _country,
      _description,
      _sale,
      _unit,
      _quantity,
      _minimum,
      _price,
      _date
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  Widget field(TextEditingController c, String label, int max,
          {bool required = false}) =>
      Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: TextFormField(
              controller: c,
              enabled: !_busy,
              maxLength: max,
              decoration: InputDecoration(labelText: label),
              validator: (v) => required && (v ?? '').trim().isEmpty
                  ? t('필수 항목입니다.', 'Required.')
                  : null));
  Widget select(String value, String label, Map<String, String> options,
          ValueChanged<String> update) =>
      Padding(
          padding: const EdgeInsets.only(bottom: 16),
          child: DropdownButtonFormField<String>(
              initialValue: value,
              isExpanded: true,
              decoration: InputDecoration(labelText: label),
              items: [
                for (final e in options.entries)
                  DropdownMenuItem(value: e.key, child: Text(e.value))
              ],
              onChanged: _busy ? null : (v) => setState(() => update(v!))));
  @override
  Widget build(BuildContext context) => PopScope(
      canPop: !_busy,
      child: Dialog.fullscreen(
          child: Scaffold(
              appBar: AppBar(
                  title: Text(t('취급 상품 등록', 'Product details')),
                  actions: [
                    GuideHelpButton(lesson: 'supplier-product', enabled: !_busy)
                  ],
                  leading: IconButton(
                      onPressed: _busy ? null : () => Navigator.pop(context),
                      icon: const Icon(Icons.close))),
              body: Center(
                  child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 720),
                      child: SingleChildScrollView(
                          padding: const EdgeInsets.all(20),
                          child: Form(
                              key: _form,
                              child: Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.stretch,
                                  children: [
                                    Text(t(
                                        '* 필수 · 가격 없이도 견적 요청 상품으로 등록할 수 있습니다.',
                                        '* Required · products can request a quote without a listed price.')),
                                    const SizedBox(height: 12),
                                    Center(
                                        child: SupplierProductImage(_image,
                                            size: 140)),
                                    TextButton.icon(
                                        onPressed: _busy
                                            ? null
                                            : () async {
                                                final photo =
                                                    await ImagePicker()
                                                        .pickImage(
                                                            source: ImageSource
                                                                .gallery,
                                                            maxWidth: 1600,
                                                            maxHeight: 1600,
                                                            imageQuality: 85);
                                                if (photo == null || !mounted) {
                                                  return;
                                                }
                                                setState(() => _busy = true);
                                                try {
                                                  final image = await _repository
                                                      .uploadImage(
                                                          widget.business.id,
                                                          await photo
                                                              .readAsBytes());
                                                  if (mounted) {
                                                    final previous = _image;
                                                    _temporaryImages.add(image);
                                                    setState(
                                                        () => _image = image);
                                                    if (_temporaryImages
                                                        .remove(previous)) {
                                                      unawaited(
                                                          _discard(previous));
                                                    }
                                                  } else {
                                                    unawaited(_discard(image));
                                                  }
                                                } catch (_) {
                                                  if (mounted) {
                                                    setState(() => _error = t(
                                                        '5MB 이하 JPG·PNG·WebP 사진을 선택해 주세요.',
                                                        'Choose a JPG, PNG or WebP image up to 5 MB.'));
                                                  }
                                                } finally {
                                                  if (mounted) {
                                                    setState(
                                                        () => _busy = false);
                                                  }
                                                }
                                              },
                                        icon: const Icon(
                                            Icons.add_photo_alternate_outlined),
                                        label: Text(t('상품 사진 선택 *',
                                            'Choose product photo *'))),
                                    field(_name, t('상품명 *', 'Product name *'),
                                        250,
                                        required: true),
                                    select(
                                        _category, t('대분류 *', 'Category *'), {
                                      for (final c in supplierCategories.keys)
                                        c: supplierCategoryLabel(c, en)
                                    }, (v) {
                                      _category = v;
                                      _subcategory =
                                          supplierCategories[v]!.$3.first;
                                    }),
                                    // A new key updates the selected subcategory when its parent changes.
                                    KeyedSubtree(
                                        key: ValueKey(_category),
                                        child: select(
                                            _subcategory,
                                            t('소분류 *', 'Subcategory *'),
                                            {
                                              for (final c
                                                  in supplierCategories[
                                                          _category]!
                                                      .$3)
                                                c: supplierCategoryLabel(c, en)
                                            },
                                            (v) => _subcategory = v)),
                                    field(
                                        _aliases,
                                        t('검색 별칭 (예: 양파, onion)',
                                            'Search aliases (e.g. onion, yellow onion)'),
                                        500),
                                    field(_brand, t('브랜드', 'Brand'), 120),
                                    select(
                                        _origin,
                                        t('원산지 구분 *', 'Origin type *'),
                                        {
                                          'domestic':
                                              t('국산', 'Domestic (Korea)'),
                                          'imported': t('수입', 'Imported'),
                                          'mixed': t('혼합', 'Mixed'),
                                          'unknown': t('확인 필요', 'To confirm')
                                        },
                                        (v) => _origin = v),
                                    field(
                                        _country,
                                        t('원산지 국가·지역',
                                            'Country or region of origin'),
                                        120),
                                    field(
                                        _sale,
                                        t('판매 단위 * (예: box, pack)',
                                            'Selling unit * (e.g. box, pack)'),
                                        30,
                                        required: true),
                                    field(
                                        _quantity,
                                        t('판매 단위 1개에 들어 있는 내용량 *',
                                            'Contents per selling unit *'),
                                        20,
                                        required: true),
                                    field(
                                        _unit,
                                        t('내용량 단위 * (예: kg, g, ea)',
                                            'Content unit * (e.g. kg, g, ea)'),
                                        30,
                                        required: true),
                                    Text(t(
                                        '예: 1상자에 10kg → 판매 단위 box, 내용량 10, 내용 단위 kg',
                                        'Example: 10 kg per box → selling unit box, content 10, content unit kg')),
                                    const SizedBox(height: 12),
                                    field(
                                        _minimum,
                                        t('최소 구매 판매단위 수 *',
                                            'Minimum selling units *'),
                                        10,
                                        required: true),
                                    field(
                                        _price,
                                        '${t('판매 단위 1개 가격 (선택)', 'Price per selling unit (optional)')} · ${widget.business.currency}',
                                        20),
                                    field(
                                        _date,
                                        t('가격 유효일 (가격 입력 시 필수, YYYY-MM-DD)',
                                            'Price valid until (required with price, YYYY-MM-DD)'),
                                        10),
                                    select(
                                        _tax,
                                        t('표시 가격의 세금', 'Tax in listed price'),
                                        {
                                          'included': t('세금 포함', 'Included'),
                                          'exempt': t('면세', 'Exempt'),
                                          'unknown':
                                              t('견적 시 확인', 'Confirm in quote')
                                        },
                                        (v) => _tax = v),
                                    select(
                                        _storage,
                                        t('보관 방식', 'Storage'),
                                        {
                                          'ambient': t('상온', 'Ambient'),
                                          'chilled': t('냉장', 'Chilled'),
                                          'frozen': t('냉동', 'Frozen')
                                        },
                                        (v) => _storage = v),
                                    field(
                                        _description,
                                        t('상품 설명', 'Product description'),
                                        2000),
                                    SwitchListTile(
                                        title:
                                            Text(t('판매 중', 'Active product')),
                                        value: _active,
                                        onChanged: _busy
                                            ? null
                                            : (v) =>
                                                setState(() => _active = v)),
                                    if (_error != null)
                                      Text(_error!,
                                          style: TextStyle(
                                              color: Theme.of(context)
                                                  .colorScheme
                                                  .error)),
                                  ]))))),
              bottomNavigationBar: SafeArea(
                  child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: FilledButton(
                          onPressed: _busy
                              ? null
                              : () async {
                                  final q = shoppingInput(_quantity.text),
                                      min = int.tryParse(_minimum.text),
                                      price = shoppingInput(_price.text),
                                      date = DateTime.tryParse(_date.text);
                                  if (!_form.currentState!.validate() ||
                                      _image.isEmpty ||
                                      q == null ||
                                      q <= 0 ||
                                      q > 1e9 ||
                                      (q * 1e6 - (q * 1e6).round()).abs() >
                                          0.001 ||
                                      min == null ||
                                      min < 1 ||
                                      min > 1000000 ||
                                      (_price.text.trim().isNotEmpty &&
                                          (price == null ||
                                              price < 0 ||
                                              price > 1e12 ||
                                              _date.text.isEmpty ||
                                              !validRequestDate(_date.text))) ||
                                      ['tsp', 'tbsp', 'cup']
                                          .contains(_unit.text.trim()) ||
                                      ['tsp', 'tbsp', 'cup']
                                          .contains(_sale.text.trim())) {
                                    setState(() => _error = t(
                                        '사진·수량·구매 단위·가격과 유효일을 확인해 주세요.',
                                        'Check photo, quantities, purchase units, price and validity date.'));
                                    return;
                                  }
                                  setState(() => _busy = true);
                                  try {
                                    await ref
                                        .read(supplierCatalogRepositoryProvider)
                                        .saveProduct(CatalogProduct(
                                            id: _id,
                                            supplierId: widget.business.id,
                                            name: _name.text.trim(),
                                            category: _category,
                                            subcategory: _subcategory,
                                            aliases: _aliases.text.trim(),
                                            brand: _brand.text.trim(),
                                            origin: _origin,
                                            country: _country.text.trim(),
                                            storage: _storage,
                                            description:
                                                _description.text.trim(),
                                            imagePath: _image,
                                            saleUnit: _sale.text.trim(),
                                            contentQuantity: q,
                                            contentUnit: _unit.text.trim(),
                                            minimumPacks: min,
                                            price: price,
                                            priceValidUntil: date,
                                            tax: _tax,
                                            active: _active,
                                            revision: _p?.revision ?? 0));
                                    _temporaryImages.remove(_image);
                                    final previous = _p?.imagePath;
                                    if (previous != null &&
                                        previous.isNotEmpty &&
                                        previous != _image) {
                                      unawaited(_discard(previous));
                                    }
                                    if (context.mounted) Navigator.pop(context);
                                  } catch (_) {
                                    if (mounted) {
                                      setState(() => _error = t(
                                          '저장하지 못했습니다. 닫고 새로고침하여 저장 상태를 확인해 주세요.',
                                          'Could not confirm save. Close and refresh to check saved details.'));
                                    }
                                  } finally {
                                    if (mounted) setState(() => _busy = false);
                                  }
                                },
                          child: Text(t('상품 저장', 'Save product'))))))));
}
