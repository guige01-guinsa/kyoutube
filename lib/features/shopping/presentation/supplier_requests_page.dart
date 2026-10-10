import '../../../core/localization/localized_text.dart';
import '../../../core/auth/auth_return.dart';
import '../data/purchase_cleanup_repository.dart';
import 'record_management.dart';
import '../../guide/presentation/guide_help_button.dart';
import 'package:flutter/material.dart';
import '../../../core/widgets/scout_page.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../auth/application/auth_providers.dart';
import '../../kitchen/application/kitchen_providers.dart';
import '../../recipes/application/recipe_providers.dart';
import '../application/supplier_request_share.dart';
import 'package:flutter/foundation.dart';
import '../data/shopping_assistant_repository.dart';
import '../data/supplier_request_repository.dart';
import '../domain/shopping_assistant.dart';
import '../domain/supplier_request.dart';
import 'shopping_assistant_dialogs.dart';
import 'supplier_request_editor.dart';
import '../application/purchase_workspace.dart';
import 'purchase_progress.dart';
import 'business_registration_widgets.dart';
import 'request_document_preview.dart';
import 'supplier_request_document.dart';
import '../../suppliers/data/supplier_catalog_repository.dart';

class SupplierRequestsPage extends ConsumerWidget {
  const SupplierRequestsPage(
      {super.key,
      this.listId,
      this.requestId,
      this.showStores = false,
      this.embedded = false,
      this.initialStage = PurchaseStage.preparing});
  final String? listId, requestId;
  final bool showStores;
  final bool embedded;
  final PurchaseStage initialStage;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final owner = ref.watch(activeAccountIdProvider);
    if (owner == null) {
      return Scaffold(
          appBar: AppBar(title: Text(shopText(context, '구매', 'Purchasing'))),
          body: Center(
              child: FilledButton(
                  onPressed: () => context.push(loginFor(
                      GoRouterState.of(context).uri.toString(),
                      resume: true)),
                  child: Text(shopText(context, '로그인', 'Sign in')))));
    }
    return _SupplierWorkspace(
        key: ValueKey(owner),
        listId: listId,
        requestId: requestId,
        showStores: showStores,
        embedded: embedded,
        initialStage: initialStage);
  }
}

class _SupplierWorkspace extends ConsumerStatefulWidget {
  const _SupplierWorkspace(
      {super.key,
      this.listId,
      this.requestId,
      required this.showStores,
      this.embedded = false,
      required this.initialStage});
  final String? listId, requestId;
  final bool showStores;
  final bool embedded;
  final PurchaseStage initialStage;
  @override
  ConsumerState<_SupplierWorkspace> createState() => _SupplierWorkspaceState();
}

class _SupplierWorkspaceState extends ConsumerState<_SupplierWorkspace> {
  late PurchaseStage _stage = widget.initialStage;
  String _requestQuery = '';
  String? _openedRequestId;
  @override
  void initState() {
    super.initState();
    _scheduleRequest();
  }

  @override
  void didUpdateWidget(_SupplierWorkspace oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.initialStage != widget.initialStage) {
      _stage = widget.initialStage;
    }
    if (oldWidget.requestId != widget.requestId) _scheduleRequest();
  }

  void _scheduleRequest() {
    final id = widget.requestId;
    if (id == null || id == _openedRequestId) return;
    _openedRequestId = id;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _openRequest(id);
    });
  }

  Future<void> _openRequest(String id) async {
    final owner = ref.read(activeAccountIdProvider);
    setState(() {
      _opening = true;
      _loadingRequest = true;
    });
    try {
      final request =
          await ref.read(supplierRequestRepositoryProvider).request(id);
      if (!mounted || owner != ref.read(activeAccountIdProvider)) return;
      if (request == null) {
        _message(t('요청서를 찾을 수 없습니다. 삭제되었거나 접근할 수 없는 요청입니다.',
            'This request was removed or is not accessible.'));
      } else {
        setState(() => _stage = purchaseStage(request.status));
        setState(() => _loadingRequest = false);
        await _details(request);
      }
    } catch (_) {
      if (mounted && owner == ref.read(activeAccountIdProvider)) {
        _message(t('요청서를 불러오지 못했습니다. 다시 시도해 주세요.',
            'Could not load the request. Please retry.'));
      }
    } finally {
      if (mounted) {
        setState(() {
          _opening = false;
          _loadingRequest = false;
        });
      }
    }
  }

  Future<void> _newRequest() async {
    if (_choosingSource) return;
    final owner = ref.read(activeAccountIdProvider);
    _choosingSource = true;
    try {
      final source = await showModalBottomSheet<String>(
          context: context,
          showDragHandle: true,
          useSafeArea: true,
          isScrollControlled: true,
          builder: (ctx) => SingleChildScrollView(
              child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
                  child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(t('어디서 시작할까요?', 'How would you like to start?'),
                            style: Theme.of(context).textTheme.titleLarge),
                        for (final item in [
                          (
                            'shopping',
                            Icons.shopping_basket_outlined,
                            t('장보기 재료에서', 'From shopping ingredients'),
                            t('재료별 업체를 비교해 요청서를 만들어요.',
                                'Compare suppliers for each ingredient.')
                          ),
                          (
                            'repeat',
                            Icons.history,
                            t('이전 요청서에서', 'From a previous request'),
                            t('지난 품목을 가져와 수량과 날짜만 바꾸세요.',
                                'Reuse items, then update quantities and dates.')
                          ),
                          (
                            'direct',
                            Icons.edit_note,
                            t('직접 작성', 'Write a request'),
                            t('거래처와 품목을 직접 정해요.',
                                'Choose a supplier and add items.')
                          ),
                        ])
                          ListTile(
                              contentPadding: EdgeInsets.zero,
                              leading: Icon(item.$2),
                              title: Text(item.$3),
                              subtitle: Text(item.$4),
                              trailing: const Icon(Icons.chevron_right),
                              onTap: () => Navigator.pop(ctx, item.$1)),
                      ]))));
      if (!mounted || owner != ref.read(activeAccountIdProvider)) return;
      if (source == 'shopping') {
        context.push(Uri(
                path: '/supplier-plan',
                queryParameters:
                    widget.listId == null ? null : {'list': widget.listId!})
            .toString());
      } else if (source == 'direct') {
        await _edit();
      } else if (source == 'repeat') {
        final rows = await ref.read(supplierRequestsProvider.future);
        if (!mounted || owner != ref.read(activeAccountIdProvider)) return;
        final selected = await showDialog<SupplierRequest>(
            context: context,
            builder: (ctx) => ShoppingAccountGuard(
                    child: AlertDialog(
                        title: Text(
                            t('다시 요청할 내역 선택', 'Choose a request to repeat')),
                        content: SizedBox(
                            width: 560,
                            height: 380,
                            child: rows.isEmpty
                                ? Text(t(
                                    '저장한 요청서가 없습니다.', 'No saved requests yet.'))
                                : ListView(children: [
                                    for (final r in rows)
                                      ListTile(
                                          title: Text(r.supplier.name),
                                          subtitle: Text(r.reference),
                                          onTap: () => Navigator.pop(ctx, r))
                                  ])),
                        actions: [
                      TextButton(
                          onPressed: () => Navigator.pop(ctx),
                          child: Text(t('닫기', 'Close')))
                    ])));
        if (selected != null &&
            mounted &&
            owner == ref.read(activeAccountIdProvider)) {
          await _edit(request: selected.repeat());
        }
      }
    } catch (_) {
      if (mounted && owner == ref.read(activeAccountIdProvider)) {
        _message(t('정보를 불러오지 못했습니다. 다시 시도해 주세요.',
            'Could not load information. Please retry.'));
      }
    } finally {
      _choosingSource = false;
    }
  }

  final _query = TextEditingController();
  bool _favoritesOnly = false;
  bool _opening = false;
  bool _loadingRequest = false;
  bool _choosingSource = false;
  @override
  void dispose() {
    _query.dispose();
    super.dispose();
  }

  String t(String ko, String en) => shopText(context, ko, en);
  void _refresh() {
    ref.invalidate(shoppingSuppliersProvider);
    ref.invalidate(supplierRequestsProvider);
  }

  void _message(String m) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));
  Future<void> _supplier([ShoppingSupplier? supplier]) async {
    await showDialog<bool>(
        context: context,
        barrierDismissible: false,
        builder: (_) =>
            ShoppingAccountGuard(child: SupplierEditor(supplier: supplier)));
    if (mounted) _refresh();
  }

  Future<void> _edit({SupplierRequest? request, String? supplierId}) async {
    if (_opening) return;
    final owner = ref.read(activeAccountIdProvider);
    setState(() {
      _opening = true;
      _loadingRequest = true;
    });
    try {
      final allSuppliers = await ref.read(shoppingSuppliersProvider.future);
      final archives = ref.read(purchaseCleanupIndexProvider(null)).valueOrNull;
      final suppliers = allSuppliers
          .where((s) => !(archives?.contains('supplier', s.id) ?? false))
          .toList();
      final lists = await ref.read(kitchenShoppingListsProvider.future);
      if (!mounted || owner != ref.read(activeAccountIdProvider)) return;
      setState(() => _loadingRequest = false);
      final saved = await showDialog<SupplierRequest>(
          context: context,
          barrierDismissible: false,
          builder: (_) => ShoppingAccountGuard(
                  child: SupplierRequestEditor(
                      suppliers: [
                    if (request != null &&
                        request.revision > 0 &&
                        !suppliers.any((s) => s.id == request.supplier.id))
                      request.supplier,
                    ...suppliers
                  ],
                      groups:
                          shoppingPurchaseGroups(lists, listId: widget.listId),
                      request: request,
                      initialSupplierId: supplierId)));
      if (!mounted || owner != ref.read(activeAccountIdProvider)) return;
      _refresh();
      if (saved != null) await _details(saved);
    } catch (_) {
      if (mounted) {
        _message(t('정보를 불러오지 못했습니다. 연결을 확인해 주세요.',
            'Could not load information. Check your connection.'));
      }
    } finally {
      if (mounted) {
        setState(() {
          _opening = false;
          _loadingRequest = false;
        });
      }
    }
  }

  Future<void> _details(SupplierRequest request) async {
    final action = await showDialog<String>(
        context: context,
        barrierDismissible: false,
        builder: (_) => ShoppingAccountGuard(
            child: SupplierRequestDetails(request: request)));
    if (!mounted) return;
    _refresh();
    if (action == 'edit' || action == 'repeat') {
      // A saved draft keeps its revision. A repeat starts a new request.
      _opening = false;
      await _edit(request: action == 'repeat' ? request.repeat() : request);
    }
  }

  Future<void> _openWebsite(ShoppingSupplier supplier) async {
    final uri = shoppingProductUri(supplier.website);
    try {
      if (uri == null || !await ref.read(shoppingLinkLauncherProvider)(uri)) {
        throw StateError('Store unavailable');
      }
    } catch (_) {
      if (mounted) {
        _message(t('구매처를 열지 못했습니다. 링크를 확인해 주세요.',
            'Could not open the store. Check the link.'));
      }
    }
  }

  List<Widget> _directory(List<ShoppingSupplier> suppliers) {
    final visible = shoppingSupplierDirectory(suppliers, query: _query.text)
        .where((s) => !_favoritesOnly || s.favorite)
        .toList();
    return [
      TextField(
          controller: _query,
          onChanged: (_) => setState(() {}),
          decoration: InputDecoration(
              labelText:
                  t('구매처 이름·재료·메모 검색', 'Search stores, ingredients or notes'),
              prefixIcon: const Icon(Icons.search),
              suffixIcon: _query.text.isEmpty
                  ? null
                  : IconButton(
                      tooltip: t('검색어 지우기', 'Clear search'),
                      onPressed: () => setState(_query.clear),
                      icon: const Icon(Icons.close)))),
      const SizedBox(height: 8),
      Align(
          alignment: Alignment.centerLeft,
          child: FilterChip(
              label: Text(t('자주 쓰는 구매처만', 'Favorites only')),
              selected: _favoritesOnly,
              onSelected: (v) => setState(() => _favoritesOnly = v))),
      const SizedBox(height: 8),
      if (visible.isEmpty)
        Padding(
            padding: const EdgeInsets.symmetric(vertical: 24),
            child: Text(suppliers.isEmpty
                ? t('온라인 쇼핑몰, 동네 매장, 협력업체를 직접 등록해 보세요.',
                    'Add an online store, local shop or supplier.')
                : t('조건에 맞는 구매처가 없습니다.', 'No stores match your search.'))),
      for (final s in visible)
        Card(
            margin: const EdgeInsets.only(bottom: 12),
            child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(children: [
                        const Icon(Icons.storefront_outlined, size: 22),
                        const SizedBox(width: 8),
                        Expanded(
                            child: Text(s.name,
                                style:
                                    Theme.of(context).textTheme.titleMedium)),
                        if (s.favorite)
                          Tooltip(
                              message: t('자주 쓰는 구매처', 'Favorite store'),
                              child: const Icon(Icons.star_rounded, size: 22)),
                      ]),
                      const SizedBox(height: 8),
                      if (s.contact.isNotEmpty || s.phone.isNotEmpty)
                        SelectableText('${s.contact} ${s.phone}'.trim()),
                      if (s.products.isNotEmpty)
                        Text(s.products,
                            maxLines: 2, overflow: TextOverflow.ellipsis),
                      if (s.address.isNotEmpty)
                        Text(s.address,
                            maxLines: 2, overflow: TextOverflow.ellipsis),
                      if (s.website.isNotEmpty)
                        Text(shoppingProductUri(s.website)?.host ??
                            t('링크 확인 필요', 'Check link')),
                      if (s.memo.isNotEmpty)
                        Padding(
                            padding: const EdgeInsets.only(top: 8),
                            child: LocalizedText(
                                '${t('나만의 메모', 'Private note')}: ${s.memo}',
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: Theme.of(context).textTheme.bodySmall)),
                      const SizedBox(height: 8),
                      Wrap(spacing: 8, runSpacing: 4, children: [
                        if (s.website.isNotEmpty)
                          OutlinedButton.icon(
                              onPressed: shoppingProductUri(s.website) == null
                                  ? null
                                  : () => _openWebsite(s),
                              icon: const Icon(Icons.open_in_new, size: 18),
                              label:
                                  Text(t('구매 사이트 열기', 'Open store website'))),
                        OutlinedButton.icon(
                            onPressed:
                                _opening ? null : () => _edit(supplierId: s.id),
                            icon: const Icon(Icons.description_outlined,
                                size: 18),
                            label: Text(
                                t('이 구매처에 요청', 'Request from this store'))),
                        TextButton(
                            onPressed: () => _supplier(s),
                            child: Text(t('수정', 'Edit'))),
                        RecordManagementMenu(actions: [
                          RecordManagementAction(
                              'erase',
                              t('영구 삭제', 'Delete permanently'),
                              Icons.delete_forever, () async {
                            if (await manageOwnerRecord(context, ref,
                                    kind: 'supplier', id: s.id) !=
                                null) {
                              ref.invalidate(shoppingSuppliersProvider);
                            }
                          }),
                          RecordManagementAction(
                              'archive',
                              t('보관·복원', 'Archive / restore'),
                              Icons.archive_outlined, () async {
                            await managePurchaseArchive(context, ref,
                                kind: 'supplier', id: s.id, title: s.name);
                          }),
                        ]),
                      ])
                    ]))),
    ];
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(supplierRequestsProvider, (_, next) {
      if (next.hasValue) ref.invalidate(purchaseCleanupIndexProvider(null));
    });
    ref.listen(shoppingSuppliersProvider, (_, next) {
      if (next.hasValue) ref.invalidate(purchaseCleanupIndexProvider(null));
    });
    final stores = widget.showStores;
    final suppliers = stores ? ref.watch(shoppingSuppliersProvider) : null;
    final requests = stores ? null : ref.watch(supplierRequestsProvider);
    final checkpoints = ref.watch(requestEditCheckpointsProvider);
    final english = Localizations.localeOf(context).languageCode != 'ko';
    final archives = ref.watch(purchaseCleanupIndexProvider(null)).valueOrNull;
    final rows = (requests?.valueOrNull ?? <SupplierRequest>[])
        .where((r) =>
            !(archives?.hidesRequest('request', r.id, r.status) ?? false))
        .toList();
    final filtered =
        purchaseRequestsForStage(rows, _stage, query: _requestQuery);
    return Scaffold(
      appBar: widget.embedded
          ? null
          : AppBar(
              title:
                  Text(stores ? t('거래처', 'Suppliers') : t('구매', 'Purchasing')),
              actions: [
                  GuideHelpButton(
                      lesson: stores ? 'buy-suppliers' : 'buy-request',
                      enabled: !_opening),
                  IconButton(
                      onPressed: _opening ? null : _refresh,
                      tooltip: t('새로고침', 'Refresh'),
                      icon: const Icon(Icons.refresh)),
                ]),
      body: Center(
          child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 1000),
              child: ListView(padding: const EdgeInsets.all(20), children: [
                if (_loadingRequest) const LinearProgressIndicator(),
                if (stores) ...[
                  ScoutPageHeading(
                      title: t('내 거래처부터 빠르게 선택하세요.',
                          'Start with your trusted suppliers.'),
                      subtitle: t('등록한 거래처를 선택하거나 새 업체를 찾아 구매를 준비하세요.',
                          'Choose a saved supplier or find another business to prepare a purchase.'),
                      icon: Icons.storefront_outlined),
                  const SizedBox(height: 12),
                  Wrap(spacing: 8, runSpacing: 8, children: [
                    FilledButton.icon(
                        onPressed: () => context.push('/supplier-directory'),
                        icon: const Icon(Icons.search),
                        label: Text(t('공개 업체에서 찾기', 'Find public suppliers'))),
                    OutlinedButton.icon(
                        onPressed: () => _supplier(),
                        icon: const Icon(Icons.add),
                        label: Text(t('구매처 추가', 'Add store'))),
                  ]),
                  const SizedBox(height: 16),
                  suppliers!.when(
                      data: (items) => Column(
                          children: _directory(items
                              .where((r) =>
                                  !(archives?.contains('supplier', r.id) ??
                                      false))
                              .toList())),
                      loading: () => const LinearProgressIndicator(),
                      error: (_, __) => TextButton(
                          onPressed: _refresh,
                          child: Text(t('다시 불러오기', 'Reload')))),
                ] else ...[
                  if (!widget.embedded)
                    ScoutPageHeading(
                        title: t('필요한 재료부터, 요청서까지.',
                            'From ingredients to purchase requests.'),
                        subtitle: t('준비한 목록과 거래 기록을 한곳에서 이어가세요.',
                            'Keep your shopping plans and request records together.'),
                        icon: Icons.shopping_basket_outlined),
                  const SizedBox(height: 16),
                  Wrap(spacing: 8, runSpacing: 8, children: [
                    FilledButton.icon(
                        key: const Key('new-purchase-request'),
                        onPressed: _opening ? null : _newRequest,
                        icon: const Icon(Icons.add),
                        label: Text(t('새 구매요청', 'New request'))),
                    OutlinedButton.icon(
                        onPressed: () =>
                            context.push('/supplier-request-ledger'),
                        icon: const Icon(Icons.table_chart_outlined),
                        label:
                            Text(t('대장 · 검색·출력', 'Ledger · search & export'))),
                  ]),
                  const SizedBox(height: 16),
                  if (!widget.embedded)
                    Card(
                        child: ListTile(
                            leading: const Icon(Icons.shopping_basket_outlined),
                            key: const Key('professional-shopping-preparation'),
                            title:
                                Text(t('장보기 목록 정리', 'Prepare shopping list')),
                            subtitle: Text(t(
                                '재료 분류·단위 합산·보유량을 확인하고 구매할 목록을 확정하세요.',
                                'Group ingredients, combine compatible units and check stock before buying.')),
                            trailing: const Icon(Icons.chevron_right),
                            onTap: () => context.push(widget.listId == null
                                ? '/shopping-preparation'
                                : Uri(
                                    path: '/shopping-preparation',
                                    queryParameters: {
                                        'list': widget.listId!
                                      }).toString()))),
                  const SizedBox(height: 16),
                  ScoutSectionLabel(
                      title: t('진행 단계별 요청서', 'Requests by progress')),
                  if (!widget.embedded)
                    Wrap(spacing: 8, runSpacing: 8, children: [
                      for (final stage in PurchaseStage.values)
                        ChoiceChip(
                            key: ValueKey('purchase-stage-${stage.name}'),
                            label: Text(switch (stage) {
                              PurchaseStage.preparing => t('준비 중', 'Preparing'),
                              PurchaseStage.active => t('진행 중', 'In progress'),
                              PurchaseStage.completed => t('완료', 'Completed'),
                            }),
                            selected: _stage == stage,
                            onSelected: (_) => setState(() => _stage = stage)),
                    ]),
                  const SizedBox(height: 16),
                  TextField(
                      key: const Key('purchase-search'),
                      decoration: InputDecoration(
                          labelText: t('업체·재료·요청번호 검색',
                              'Search supplier, ingredient or reference'),
                          prefixIcon: const Icon(Icons.search)),
                      onChanged: (value) =>
                          setState(() => _requestQuery = value)),
                  const SizedBox(height: 12),
                  Text(
                      t('전달·수락·입고는 직접 확인한 상태입니다. 완료에는 취소된 요청도 포함됩니다.',
                          'Sharing, acceptance and receipt are recorded by you. Completed includes cancelled requests.'),
                      style: Theme.of(context).textTheme.bodySmall),
                  const SizedBox(height: 12),
                  if (_stage == PurchaseStage.preparing)
                    for (final checkpoint in checkpoints.values.where((c) =>
                        _requestQuery.isEmpty ||
                        c.request.supplier.name
                            .toLowerCase()
                            .contains(_requestQuery.toLowerCase())))
                      Card(
                          child: ListTile(
                              leading: const Icon(Icons.edit_note),
                              title: Text(
                                  checkpoint.request.supplier.name.isEmpty
                                      ? t('작성하던 요청서', 'Unfinished request')
                                      : checkpoint.request.supplier.name),
                              subtitle: Text(t('이어서 작성 · 현재 앱에서 임시 보관',
                                  'Continue editing · kept in this app session')),
                              trailing: const Icon(Icons.chevron_right),
                              onTap: _opening
                                  ? null
                                  : () => _edit(request: checkpoint.request))),
                  requests!.when(
                      loading: () => const LinearProgressIndicator(),
                      error: (_, __) => TextButton(
                          onPressed: _refresh,
                          child: Text(t('다시 불러오기', 'Reload'))),
                      data: (_) => Column(children: [
                            if (filtered.isEmpty)
                              Padding(
                                  padding:
                                      const EdgeInsets.symmetric(vertical: 28),
                                  child: Text(t('이 조건의 요청서가 없습니다.',
                                      'No requests match this view.'))),
                            for (final r in filtered
                                .where((r) => !checkpoints.containsKey(r.id)))
                              Card(
                                  margin: const EdgeInsets.only(bottom: 12),
                                  child: ListTile(
                                      key: ValueKey('purchase-request-${r.id}'),
                                      title: Text(r.supplier.name),
                                      subtitle: LocalizedText(
                                          '${requestStatus(r.status, english)} · ${r.lines.length}${t('개 품목', ' items')}\n${r.deliveryDate.isEmpty ? r.reference : r.deliveryDate}',
                                          style: Theme.of(context)
                                              .textTheme
                                              .bodySmall),
                                      trailing: const Icon(Icons.chevron_right),
                                      onTap:
                                          _opening ? null : () => _details(r))),
                            if (rows.length >=
                                ref.watch(supplierRequestLimitProvider)) ...[
                              Text(t('불러온 최근 요청 기준입니다. 전체 기간은 대장에서 검색하세요.',
                                  'Showing loaded recent requests. Search the ledger for all dates.')),
                              if (ref.watch(supplierRequestLimitProvider) <
                                  1000)
                                TextButton(
                                    onPressed: () => ref
                                        .read(supplierRequestLimitProvider
                                            .notifier)
                                        .state += 50,
                                    child: Text(
                                        t('요청서 더 보기', 'Load more requests'))),
                            ],
                          ])),
                ],
              ]))),
    );
  }
}

class SupplierRequestDetails extends ConsumerStatefulWidget {
  const SupplierRequestDetails(
      {super.key, required this.request, this.onChanged});
  final SupplierRequest request;
  final ValueChanged<SupplierRequest?>? onChanged;
  @override
  ConsumerState<SupplierRequestDetails> createState() =>
      _SupplierRequestDetailsState();
}

class _SupplierRequestDetailsState
    extends ConsumerState<SupplierRequestDetails> {
  late SupplierRequest _request = widget.request;
  bool _busy = false;
  String? _message;
  String t(String ko, String en) => shopText(context, ko, en);
  bool get english => Localizations.localeOf(context).languageCode != 'ko';
  Future<void> _share(bool pdf, BuildContext buttonContext) async {
    final owner = ref.read(activeAccountIdProvider);
    final box = buttonContext.findRenderObject() as RenderBox;
    final origin = box.localToGlobal(Offset.zero) & box.size;
    setState(() {
      _busy = true;
      _message = null;
    });
    try {
      await ref.read(supplierRequestShareProvider)(_request,
          pdf: pdf,
          english: english,
          origin: origin,
          accountStillActive: () =>
              mounted &&
              owner != null &&
              ref.read(activeAccountIdProvider) == owner);
      if (mounted) {
        setState(() => _message = kIsWeb
            ? (pdf
                ? t('PDF를 내려받았습니다. 파일을 열어 출력하거나 업체에 전달하세요.',
                    'PDF downloaded. Open it to print or send to your supplier.')
                : t('요청서를 복사했습니다. 업체 채팅방에 붙여넣고 전송해 주세요.',
                    'Request copied. Paste it into your supplier chat and send it.'))
            : t('업체 채팅방에서 전송 여부를 확인한 뒤 전달 확인을 눌러 주세요.',
                'Check that you sent the request in the supplier chat, then confirm delivery here.'));
      }
    } on PostgrestException catch (error) {
      if (mounted) {
        setState(() => _message = error.message
                .contains('PDF_MEMBERSHIP_REQUIRED')
            ? t('PDF 공유는 플러스·비즈니스에서 제공합니다. 무료 회원은 텍스트로 공유할 수 있습니다.',
                'PDF sharing requires Plus or Business. Free members can share text.')
            : t('공유 권한을 확인하지 못했습니다. 다시 시도해 주세요.',
                'Could not verify sharing access. Please try again.'));
      }
    } catch (_) {
      if (mounted) {
        setState(() => _message = t('공유하지 못했습니다. 다시 시도하거나 텍스트 공유를 이용해 주세요.',
            'Could not share. Try again or use text sharing.'));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<bool> _confirm(String title, String body) async =>
      await showDialog<bool>(
          context: context,
          builder: (ctx) => ShoppingAccountGuard(
                  child: AlertDialog(
                      title: Text(title),
                      content: Text(body),
                      actions: [
                    TextButton(
                        onPressed: () => Navigator.pop(ctx, false),
                        child: Text(t('취소', 'Cancel'))),
                    FilledButton(
                        onPressed: () => Navigator.pop(ctx, true),
                        child: Text(t('확인', 'Confirm'))),
                  ]))) ==
      true;
  Future<void> _status(String status) async {
    if (!await _confirm(
            requestStatus(status, english),
            t('업체와 확인한 내용을 직접 기록합니다. 메시지 전송·결제·재고 반영은 실행되지 않습니다. 전달 확인 후에는 요청서 내용이 고정됩니다.',
                'Record what you confirmed with the supplier. This does not send a message, make a payment or update inventory. Confirming delivery locks the request contents.')) ||
        !mounted) {
      return;
    }
    setState(() => _busy = true);
    try {
      final updated = await ref
          .read(supplierRequestRepositoryProvider)
          .save(_request, status: status);
      widget.onChanged?.call(updated);
      if (mounted) {
        setState(() {
          _request = updated;
          _message = null;
        });
      }
      ref.invalidate(supplierRequestsProvider);
    } catch (_) {
      if (mounted) {
        setState(() => _message = t('변경을 확인하지 못했습니다. 재시도하거나 닫고 목록을 새로고침해 주세요.',
            'Could not confirm the change. Retry, or close and refresh the list.'));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _receipt(SupplierRequestLine line) async {
    final owner = ref.read(activeAccountIdProvider);
    setState(() => _busy = true);
    try {
      ref.invalidate(kitchenShoppingListsProvider);
      final lists = await ref.read(kitchenShoppingListsProvider.future);
      if (!mounted || owner != ref.read(activeAccountIdProvider)) return;
      final group = requestReceiptGroup(line, shoppingPurchaseGroups(lists));
      if (group == null) {
        setState(() => _message = t(
            '연결된 미구매 항목이 없거나 단위가 다릅니다. 장보기 도우미에서 현재 목록을 확인해 주세요.',
            'No compatible pending items remain. Review the current lists in the shopping assistant.'));
        return;
      }
      final saved = await showDialog<bool>(
          context: context,
          barrierDismissible: false,
          builder: (_) => ShoppingAccountGuard(
              child: ShoppingPurchaseDialog(
                  group: group,
                  suggestedQuantity:
                      shoppingConvert(line.quantity!, line.unit, group.unit),
                  purchaseLabel: _request.supplier.name)));
      if (saved == true && mounted) {
        ref.invalidate(kitchenShoppingListsProvider);
        ref.invalidate(shoppingRecordsProvider);
        ref.invalidate(kitchenIngredientsProvider);
        ref.invalidate(kitchenSummaryProvider);
        setState(() =>
            _message = t('구매 이력에 기록했습니다.', 'Recorded in purchase history.'));
      }
    } catch (_) {
      if (mounted) {
        setState(() => _message = t('정보를 불러오지 못했습니다. 연결을 확인해 주세요.',
            'Could not load information. Check your connection.'));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _delete() async {
    if (_busy || _request.status != 'draft') return;
    if (!await _confirm(
            t('요청서 삭제', 'Delete request'),
            t('전달 이력이 없는 초안만 삭제합니다. 기록을 남기려면 보관을 선택하세요.',
                'Only a draft with no delivery history can be deleted. Archive it to keep the record.')) ||
        !mounted) {
      return;
    }
    setState(() => _busy = true);
    try {
      await ref.read(supplierRequestRepositoryProvider).deleteDraft(_request);
      widget.onChanged?.call(null);
      ref.invalidate(supplierRequestsProvider);
      if (mounted) Navigator.pop(context);
    } catch (_) {
      if (mounted) {
        setState(() => _message =
            t('삭제하지 못했습니다. 다시 시도해 주세요.', 'Could not remove. Try again.'));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final next = const {
      'draft': 'sent',
      'sent': 'accepted',
      'accepted': 'received'
    }[_request.status];
    return PopScope(
        canPop: !_busy,
        child: Dialog.fullscreen(
            child: Scaffold(
          appBar: AppBar(
              title: Text(t('구매 요청서 미리보기', 'Purchase request preview')),
              leading: IconButton(
                  onPressed: _busy ? null : () => Navigator.pop(context),
                  tooltip: t('닫기', 'Close'),
                  icon: const Icon(Icons.close))),
          body: ScoutPageBody(
              maxWidth: 960,
              child: ListView(padding: const EdgeInsets.all(20), children: [
                ScoutPageHeading(
                    title: _request.supplier.name,
                    eyebrow: t('구매요청서 확인', 'Review purchase request'),
                    subtitle: requestStatus(_request.status, english),
                    icon: Icons.receipt_long_outlined),
                const SizedBox(height: 16),
                const PurchaseProgress(step: 3),
                Text(requestStatus(_request.status, english),
                    style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 12),
                Text(t('공유할 내용에 업체명·품목·수량·주소가 맞는지 확인해 주세요.',
                    'Check the supplier, items, quantities and address before sharing.')),
                const SizedBox(height: 12),
                SupplierRequestDocument(request: _request),
                if (!_request.buyerBusiness.isEmpty)
                  BusinessRegistrationLink(
                      title: t('요청 업소 사업자등록번호', 'Buyer registration number'),
                      registration: _request.buyerBusiness),
                if (!_request.supplierBusiness.isEmpty)
                  BusinessRegistrationLink(
                      title: t('공급업체 사업자등록번호', 'Supplier registration number'),
                      registration: _request.supplierBusiness),
                OutlinedButton.icon(
                    onPressed: _busy
                        ? null
                        : () => showDialog<void>(
                            context: context,
                            builder: (_) =>
                                RequestDocumentPreview(request: _request)),
                    icon: const Icon(Icons.print_outlined),
                    label: Text(t('PDF 미리보기 · 인쇄', 'PDF preview · print'))),
                const SizedBox(height: 16),
                Wrap(spacing: 8, runSpacing: 8, children: [
                  if (_request.status == 'draft')
                    OutlinedButton(
                        onPressed:
                            _busy ? null : () => Navigator.pop(context, 'edit'),
                        child: Text(t('내용 수정', 'Edit contents'))),
                  OutlinedButton.icon(
                      onPressed:
                          _busy ? null : () => Navigator.pop(context, 'repeat'),
                      icon: const Icon(Icons.copy),
                      label: Text(t('새 요청서로 복제', 'Repeat as a new request'))),
                  if (next != null)
                    OutlinedButton(
                        onPressed: _busy ? null : () => _status(next),
                        child: Text(requestStatus(next, english))),
                  if (next != null)
                    TextButton(
                        onPressed: _busy ? null : () => _status('cancelled'),
                        child: Text(t('요청 취소 기록', 'Record cancellation'))),
                  RecordManagementMenu(actions: [
                    if (!_busy)
                      RecordManagementAction(
                          'erase',
                          t('영구 삭제', 'Delete permanently'),
                          Icons.delete_forever, () async {
                        if (await manageOwnerRecord(context, ref,
                                    kind: 'request', id: _request.id) !=
                                null &&
                            context.mounted) {
                          widget.onChanged?.call(null);
                          ref.invalidate(supplierRequestsProvider);
                          Navigator.pop(context);
                        }
                      }),
                    if (!_busy &&
                        const ['draft', 'received', 'cancelled']
                            .contains(_request.status))
                      RecordManagementAction(
                          'archive',
                          t('보관·복원', 'Archive / restore'),
                          Icons.archive_outlined, () async {
                        if (await managePurchaseArchive(context, ref,
                            kind: 'request',
                            id: _request.id,
                            title: _request.supplier.name)) {
                          if (context.mounted) Navigator.pop(context);
                        }
                      }),
                    if (!_busy && _request.status == 'draft')
                      RecordManagementAction(
                          'delete',
                          t('초안 삭제', 'Delete draft'),
                          Icons.delete_outline,
                          _delete),
                  ]),
                ]),
                const SizedBox(height: 16),
                if (const ['accepted', 'received']
                    .contains(_request.status)) ...[
                  if (_request.status == 'received' &&
                      _request.catalogSupplierId != null)
                    OutlinedButton.icon(
                        onPressed: _busy
                            ? null
                            : () async {
                                var stars = 5;
                                final yes = await showDialog<bool>(
                                    context: context,
                                    builder: (ctx) => StatefulBuilder(
                                        builder: (ctx, change) => AlertDialog(
                                              title: Text(
                                                  t('거래처 평가', 'Rate supplier')),
                                              content: Column(
                                                  mainAxisSize:
                                                      MainAxisSize.min,
                                                  children: [
                                                    Text(t(
                                                        '직접 입고 확인한 거래를 평가합니다. 업체별 나의 최근 평가 1개가 반영됩니다.',
                                                        'Rate a purchase you confirmed receiving. Your latest rating per supplier counts once.')),
                                                    DropdownButton<int>(
                                                        value: stars,
                                                        items: [
                                                          for (var i = 1;
                                                              i <= 5;
                                                              i++)
                                                            DropdownMenuItem(
                                                                value: i,
                                                                child: LocalizedText(
                                                                    '★ $i'))
                                                        ],
                                                        onChanged: (v) =>
                                                            change(() =>
                                                                stars = v!)),
                                                  ]),
                                              actions: [
                                                TextButton(
                                                    onPressed: () =>
                                                        Navigator.pop(
                                                            ctx, false),
                                                    child: Text(
                                                        t('취소', 'Cancel'))),
                                                FilledButton(
                                                    onPressed: () =>
                                                        Navigator.pop(
                                                            ctx, true),
                                                    child: Text(t('평가 저장',
                                                        'Save rating')))
                                              ],
                                            )));
                                if (yes != true || !mounted) return;
                                try {
                                  await ref
                                      .read(supplierCatalogRepositoryProvider)
                                      .rate(_request.id, stars, '');
                                  if (mounted) {
                                    setState(() => _message =
                                        t('평가를 저장했습니다.', 'Rating saved.'));
                                  }
                                } catch (_) {
                                  if (mounted) {
                                    setState(() => _message = t(
                                        '평가를 저장하지 못했습니다. 업체 본인은 평가할 수 없습니다.',
                                        'Could not save the rating. Suppliers cannot rate their own business.'));
                                  }
                                }
                              },
                        icon: const Icon(Icons.star_outline),
                        label: Text(t('입고한 거래처 평가', 'Rate received purchase'))),
                  Text(
                      t('실제 입고 수량·금액 기록', 'Record actual quantities and costs'),
                      style: Theme.of(context).textTheme.titleMedium),
                  Text(t(
                      '요청 당시 장보기 항목에 연결합니다. 복제하거나 직접 추가한 품목은 장보기 도우미에서 기록해 주세요.',
                      'Connect to the original shopping items. For repeated or manually added items, use the shopping assistant.')),
                  for (final line
                      in _request.lines.where((l) => l.sourceIds.isNotEmpty))
                    OutlinedButton(
                        onPressed: _busy ? null : () => _receipt(line),
                        child: Text(line.name)),
                  TextButton(
                      onPressed: _busy
                          ? null
                          : () {
                              Navigator.pop(context);
                              context.go('/shopping-assistant');
                            },
                      child: Text(t('장보기 도우미 열기', 'Open shopping assistant'))),
                ],
                if (_message != null)
                  Padding(
                      padding: const EdgeInsets.only(top: 12),
                      child: Text(_message!)),
              ])),
          bottomNavigationBar: SafeArea(
              top: false,
              child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Wrap(spacing: 8, runSpacing: 8, children: [
                    Builder(
                        builder: (ctx) => FilledButton.icon(
                            key: const Key('request-share-pdf'),
                            onPressed: _busy || _request.status == 'cancelled'
                                ? null
                                : () => _share(true, ctx),
                            icon: const Icon(Icons.picture_as_pdf_outlined),
                            label: Text(kIsWeb
                                ? t('PDF 다운로드', 'Download PDF')
                                : t('PDF 파일 공유', 'Share PDF file')))),
                    Builder(
                        builder: (ctx) => OutlinedButton.icon(
                            key: const Key('request-share-text'),
                            onPressed: _busy || _request.status == 'cancelled'
                                ? null
                                : () => _share(false, ctx),
                            icon: const Icon(Icons.text_snippet_outlined),
                            label: Text(kIsWeb
                                ? t('요청서 텍스트 복사', 'Copy request text')
                                : t('텍스트 공유', 'Share text')))),
                  ]))),
        )));
  }
}
