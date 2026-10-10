import '../../../core/localization/localized_text.dart';
import '../../../core/auth/auth_return.dart';
import '../data/purchase_cleanup_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_theme.dart';
import '../../auth/application/auth_providers.dart';
import '../../kitchen/application/kitchen_providers.dart';
import '../../kitchen/domain/kitchen_models.dart';
import '../../recipes/application/recipe_providers.dart';
import '../data/shopping_assistant_repository.dart';
import '../domain/shopping_assistant.dart';
import 'shopping_assistant_dialogs.dart';
import 'shopping_store_search_dialog.dart';
import 'shopping_market_widgets.dart';
import 'ingredient_thumbnail.dart';

class ShoppingAssistantPage extends ConsumerWidget {
  const ShoppingAssistantPage(
      {super.key, this.listId, this.embedded = false, this.initialTab = 0});
  final String? listId;
  final bool embedded;
  final int initialTab;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final account = ref.watch(activeAccountIdProvider);
    if (account == null) {
      return Scaffold(
          appBar: AppBar(
              title: Text(shopText(context, '장보기 도우미', 'Shopping assistant'))),
          body: Center(
              child: FilledButton(
                  onPressed: () => context.push(loginFor(
                      GoRouterState.of(context).uri.toString(),
                      resume: true)),
                  child: Text(
                      shopText(context, '로그인하고 장보기', 'Sign in to shop')))));
    }
    return _ShoppingAssistantWorkspace(
        key: ValueKey('$account:$initialTab'),
        listId: listId,
        embedded: embedded,
        initialTab: initialTab);
  }
}

class _ShoppingAssistantWorkspace extends ConsumerStatefulWidget {
  const _ShoppingAssistantWorkspace(
      {super.key, this.listId, this.embedded = false, this.initialTab = 0});
  final String? listId;
  final bool embedded;
  final int initialTab;
  @override
  ConsumerState<_ShoppingAssistantWorkspace> createState() =>
      _ShoppingAssistantWorkspaceState();
}

class _ShoppingAssistantWorkspaceState
    extends ConsumerState<_ShoppingAssistantWorkspace> {
  late String? _listId = widget.listId;
  late int _tab = widget.initialTab;
  String t(String ko, String en) => shopText(context, ko, en);

  Future<void> _search(ShoppingPurchaseGroup group) => showDialog<void>(
      context: context,
      builder: (_) =>
          ShoppingAccountGuard(child: ShoppingStoreSearchDialog(group: group)));

  Future<void> _refresh() async {
    ref.invalidate(kitchenShoppingListsProvider);
    ref.invalidate(kitchenIngredientsProvider);
    ref.invalidate(kitchenSummaryProvider);
    ref.invalidate(shoppingRecordsProvider);
    ref.invalidate(shoppingFavoritesProvider);
  }

  void _message(String message) => ScaffoldMessenger.of(context)
      .showSnackBar(SnackBar(content: Text(message)));
  Future<void> _open(Uri uri) async {
    try {
      if (shoppingProductUri(uri.toString()) == null ||
          !await ref.read(shoppingLinkLauncherProvider)(uri)) {
        if (mounted) {
          _message(t('구매처를 열지 못했습니다. 링크를 확인해 주세요.',
              'Could not open the store. Check the link.'));
        }
      }
    } catch (_) {
      if (mounted) {
        _message(t('구매처를 열지 못했습니다. 다시 시도해 주세요.',
            'Could not open the store. Try again.'));
      }
    }
  }

  Future<void> _favorite(
      String name, String unit, ShoppingFavorite? favorite) async {
    await showDialog<bool>(
        context: context,
        barrierDismissible: false,
        builder: (_) => ShoppingAccountGuard(
            child: ShoppingFavoriteDialog(
                name: name, unit: unit, favorite: favorite)));
  }

  Future<void> _purchase(ShoppingPurchaseGroup group,
      ShoppingFavorite? favorite, List<KitchenIngredient> inventory) async {
    final saved = await showDialog<bool>(
        context: context,
        barrierDismissible: false,
        builder: (_) => ShoppingAccountGuard(
            child: ShoppingPurchaseDialog(
                group: group,
                favorite: favorite,
                knownStock: group.knownStock(inventory))));
    if (!mounted) return;
    await _refresh();
    if (saved == true && mounted) {
      _message(t('기록했습니다. 장보기 목록을 완료하면 재고에 반영됩니다.',
          'Recorded. Complete the shopping lists to update inventory.'));
    }
  }

  Future<void> _removeFavorite(ShoppingFavorite favorite) async {
    final confirmed = await showDialog<bool>(
        context: context,
        builder: (ctx) => ShoppingAccountGuard(
                child: AlertDialog(
                    title: Text(t('즐겨찾기 삭제', 'Remove favorite')),
                    content: Text(favorite.productName),
                    actions: [
                  TextButton(
                      onPressed: () => Navigator.pop(ctx, false),
                      child: Text(t('취소', 'Cancel'))),
                  FilledButton(
                      onPressed: () => Navigator.pop(ctx, true),
                      child: Text(t('삭제', 'Remove')))
                ])));
    if (confirmed != true || !mounted) return;
    try {
      await ref
          .read(shoppingAssistantRepositoryProvider)
          .removeFavorite(favorite.id);
      ref.invalidate(shoppingFavoritesProvider);
    } catch (_) {
      if (mounted) {
        _message(t('삭제하지 못했습니다. 다시 시도해 주세요.', 'Could not remove. Try again.'));
      }
    }
  }

  Future<void> _correctAmount(ShoppingPurchaseRecord record) async {
    final edited = await showDialog<bool>(
        context: context,
        barrierDismissible: false,
        builder: (_) =>
            ShoppingAccountGuard(child: _ShoppingAmountDialog(record: record)));
    if (edited == true) ref.invalidate(shoppingRecordsProvider);
  }

  Widget _error(VoidCallback retry) => Padding(
      padding: const EdgeInsets.all(16),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Text(t('정보를 불러오지 못했습니다. 연결을 확인해 주세요.',
            'Could not load information. Check your connection.')),
        TextButton(onPressed: retry, child: Text(t('다시 시도', 'Try again')))
      ]));

  @override
  Widget build(BuildContext context) {
    ref.listen(shoppingRecordsProvider(null), (_, next) {
      if (next.hasValue) ref.invalidate(purchaseCleanupIndexProvider(null));
    });
    ref.listen(shoppingFavoritesProvider, (_, next) {
      if (next.hasValue) ref.invalidate(purchaseCleanupIndexProvider(null));
    });
    final favorites = ref.watch(shoppingFavoritesProvider);
    final lists = ref.watch(kitchenShoppingListsProvider);
    return Scaffold(
      appBar: widget.embedded
          ? null
          : AppBar(title: Text(t('장보기 도우미', 'Shopping assistant')), actions: [
              IconButton(
                  tooltip: t('구매처 관리', 'Manage stores'),
                  onPressed: _manageStores,
                  icon: const Icon(Icons.storefront_outlined)),
              IconButton(
                  tooltip: t('새로고침', 'Refresh'),
                  onPressed: _refresh,
                  icon: const Icon(Icons.refresh))
            ]),
      body: Center(
          child: ConstrainedBox(
              constraints:
                  const BoxConstraints(maxWidth: ScoutStyle.workspaceWidth),
              child: Column(children: [
                if (_tab == 0) const ShoppingMarketSelector(),
                if (!widget.embedded)
                  Padding(
                      padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
                      child: Align(
                          alignment: AlignmentDirectional.centerStart,
                          child: Wrap(spacing: 8, runSpacing: 4, children: [
                            for (final tab in [
                              (0, t('구매 준비', 'Prepare')),
                              (1, t('구매 기록', 'Records')),
                              (2, t('저장 상품', 'Favorites')),
                            ])
                              ChoiceChip(
                                  showCheckmark: false,
                                  selectedColor: ScoutStyle.forest,
                                  labelStyle: Theme.of(context)
                                      .textTheme
                                      .labelLarge
                                      ?.copyWith(
                                          color: _tab == tab.$1
                                              ? Colors.white
                                              : ScoutStyle.ink,
                                          fontWeight: _tab == tab.$1
                                              ? FontWeight.w700
                                              : FontWeight.w500),
                                  label: Text(tab.$2),
                                  selected: _tab == tab.$1,
                                  onSelected: (_) =>
                                      setState(() => _tab = tab.$1)),
                          ]))),
                Expanded(
                    child: _tab == 0
                        ? lists.when(
                            loading: () => const Center(
                                child: CircularProgressIndicator()),
                            error: (_, __) => _error(() =>
                                ref.invalidate(kitchenShoppingListsProvider)),
                            data: (values) => _prepare(values, favorites))
                        : _tab == 1
                            ? _records()
                            : favorites.when(
                                loading: () => const Center(
                                    child: CircularProgressIndicator()),
                                error: (_, __) => _error(() =>
                                    ref.invalidate(shoppingFavoritesProvider)),
                                data: _favorites)),
              ]))),
      bottomNavigationBar: widget.embedded
          ? null
          : SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 10),
                child: Center(
                  heightFactor: 1,
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(
                        maxWidth: ScoutStyle.workspaceWidth - 32),
                    child: SizedBox(
                      width: double.infinity,
                      child: OutlinedButton.icon(
                        onPressed: () => context.go('/kitchen?tab=shopping'),
                        icon: const Icon(Icons.checklist_outlined, size: 20),
                        label: Text(t('장보기 목록 확인 · 완료',
                            'Review & complete shopping lists')),
                      ),
                    ),
                  ),
                ),
              ),
            ),
    );
  }

  Widget _prepare(List<KitchenShoppingList> lists,
      AsyncValue<List<ShoppingFavorite>> favorites) {
    final groups = shoppingPurchaseGroups(lists, listId: _listId);
    final inventoryState = ref.watch(kitchenIngredientsProvider);
    final inventory = inventoryState.isLoading || inventoryState.hasError
        ? <KitchenIngredient>[]
        : inventoryState.valueOrNull ?? <KitchenIngredient>[];
    return RefreshIndicator(
        onRefresh: _refresh,
        child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
            physics: const AlwaysScrollableScrollPhysics(),
            children: [
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(t('구매할 재료', 'Ingredients to buy'),
                        style: Theme.of(context).textTheme.headlineSmall),
                    const SizedBox(height: 4),
                    OutlinedButton.icon(
                        onPressed: () => context.push(Uri(
                                path: '/shopping-preparation',
                                queryParameters:
                                    _listId == null ? null : {'list': _listId!})
                            .toString()),
                        icon: const Icon(Icons.checklist),
                        label: Text(t('장보기 목록 정리', 'Prepare shopping list'))),
                    Text(
                        t('재료를 확인하고 구매처를 선택하세요.',
                            'Review your ingredients and choose a store.'),
                        style: Theme.of(context).textTheme.bodyMedium),
                  ],
                ),
              ),
              Wrap(spacing: 6, runSpacing: 4, children: [
                ChoiceChip(
                    label: Text(t('모든 목록 합산', 'All lists')),
                    selected: _listId == null,
                    onSelected: (_) => setState(() => _listId = null)),
                for (final list in lists)
                  ChoiceChip(
                      label: ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 220),
                          child: Text(list.title,
                              maxLines: 2, overflow: TextOverflow.ellipsis)),
                      selected: _listId == list.id,
                      onSelected: (_) => setState(() => _listId = list.id)),
              ]),
              const SizedBox(height: 8),
              if (favorites.hasError)
                _error(() => ref.invalidate(shoppingFavoritesProvider)),
              const SizedBox(height: 12),
              if (groups.isEmpty)
                Padding(
                    padding: const EdgeInsets.symmetric(vertical: 24),
                    child: Column(children: [
                      const Icon(Icons.check_circle_outline,
                          size: 36, color: ScoutStyle.forest),
                      const SizedBox(height: 12),
                      Text(t('이 범위에서 구매가 필요한 재료가 없습니다.',
                          'No ingredients need buying in these lists.')),
                      const SizedBox(height: 12),
                      OutlinedButton.icon(
                          onPressed: () => context.go('/kitchen?tab=shopping'),
                          icon: const Icon(Icons.checklist_outlined),
                          label: Text(t('장보기 목록 확인', 'Review shopping lists'))),
                    ])),
              for (final group in groups)
                _groupCard(
                    group,
                    favorites.isLoading || favorites.hasError
                        ? null
                        : favorites.valueOrNull
                            ?.where((f) =>
                                f.matches(group) &&
                                !_archived('favorite', f.id))
                            .firstOrNull,
                    inventory),
              if (groups.isNotEmpty)
                TextButton.icon(
                    onPressed: () async {
                      await Clipboard.setData(ClipboardData(
                          text: groups
                              .map((g) =>
                                  '${g.name} ${shoppingNumber(g.neededQuantity)} ${shopUnit(context, g.unit)}')
                              .join('\n')));
                      if (mounted) {
                        _message(
                            t('필요한 재료를 복사했습니다.', 'Ingredient list copied.'));
                      }
                    },
                    icon: const Icon(Icons.copy_outlined, size: 18),
                    label: Text(t('필요한 재료 복사', 'Copy ingredients'))),
              const SizedBox(height: 16),
              Text(
                  t('가격·배송비·재고는 구매처에서 최종 확인해 주세요.',
                      'Confirm the final price, delivery charges and availability at the store.'),
                  style: Theme.of(context).textTheme.bodySmall),
              const SizedBox(height: 12),
              Card(
                child: ExpansionTile(
                  key: const PageStorageKey('shopping-management-tools'),
                  leading: const Icon(Icons.tune_outlined),
                  title: Text(t('구매 관리 도구', 'Shopping tools')),
                  childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                  expandedCrossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(t('재료를 모아 확인하고 구매처에서 결제하세요. 돌아온 뒤 구매 내용을 기록할 수 있어요.',
                        'Review your ingredients and check out at the store. Return here to record your purchase.')),
                    const SizedBox(height: 12),
                    OutlinedButton.icon(
                        onPressed: _manageStores,
                        icon: const Icon(Icons.storefront_outlined),
                        label: Text(t('내 구매처 관리', 'Manage my stores'))),
                    const SizedBox(height: 8),
                    OutlinedButton.icon(
                        onPressed: () => context.push(Uri(
                                path: '/supplier-plan',
                                queryParameters:
                                    _listId == null ? null : {'list': _listId!})
                            .toString()),
                        icon: const Icon(Icons.compare_arrows),
                        label: Text(t('재료별 업체 선택 · 구매요청 초안',
                            'Choose suppliers per ingredient · draft requests'))),
                    const SizedBox(height: 8),
                    OutlinedButton.icon(
                        onPressed: () => context.push(Uri(
                                path: '/supplier-requests',
                                queryParameters:
                                    _listId == null ? null : {'list': _listId!})
                            .toString()),
                        icon: const Icon(Icons.description_outlined),
                        label:
                            Text(t('협력업체에 구매 요청', 'Request from a supplier'))),
                  ],
                ),
              ),
            ]));
  }

  void _manageStores() => context.push(Uri(
          path: '/shopping-stores',
          queryParameters: _listId == null ? null : {'list': _listId!})
      .toString());

  Widget _groupCard(ShoppingPurchaseGroup group, ShoppingFavorite? favorite,
      List<KitchenIngredient> inventory) {
    final quantity = group.neededQuantity;
    return Card(
        margin: const EdgeInsets.only(bottom: 12),
        child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    IngredientThumbnail(ingredient: group.name),
                    const SizedBox(width: 10),
                    Expanded(
                        child: Text(group.name,
                            style: Theme.of(context).textTheme.titleMedium)),
                    IconButton(
                        visualDensity: VisualDensity.compact,
                        tooltip: t('자주 사는 상품 저장', 'Save favorite product'),
                        onPressed: () =>
                            _favorite(group.name, group.unit, favorite),
                        icon: Icon(
                            favorite == null ? Icons.star_border : Icons.star,
                            size: 23))
                  ]),
                  Text(
                      quantity == null
                          ? t('수량·단위 확인 필요', 'Check quantity and unit')
                          : t('필요 수량 ${shoppingNumber(quantity)} ${shopUnit(context, group.unit)}',
                              'Needed ${shoppingNumber(quantity)} ${shopUnit(context, group.unit)}'),
                      style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                          color: quantity == null
                              ? Theme.of(context).colorScheme.error
                              : ScoutStyle.forest,
                          fontWeight: FontWeight.w700)),
                  if (group.sources.length > 1)
                    Text(
                        t('${group.sources.length}개 목록에서 같은 재료를 합쳤어요.',
                            'Combined from ${group.sources.length} lists.'),
                        style: Theme.of(context).textTheme.bodySmall),
                  if (favorite != null)
                    Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: LocalizedText(
                            '${favorite.productName}\n${shoppingProductUri(favorite.url)?.host ?? ''}',
                            style: Theme.of(context).textTheme.bodySmall)),
                  const SizedBox(height: 6),
                  Wrap(spacing: 6, runSpacing: 4, children: [
                    FilledButton.icon(
                        style: FilledButton.styleFrom(
                            minimumSize: const Size(0, 36),
                            padding: const EdgeInsets.symmetric(
                                horizontal: 12, vertical: 8),
                            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                            visualDensity: VisualDensity.compact),
                        onPressed: () => favorite != null &&
                                shoppingProductUri(favorite.url) != null
                            ? _open(shoppingProductUri(favorite.url)!)
                            : _search(group),
                        icon: const Icon(Icons.open_in_new, size: 18),
                        label: Text(favorite == null
                            ? t('구매처 찾기', 'Find a store')
                            : t('저장한 상품 열기', 'Open saved product'))),
                    if (favorite != null)
                      TextButton(
                          onPressed: () => _search(group),
                          child: Text(t('다른 상품 찾기', 'Find alternatives'))),
                    OutlinedButton.icon(
                        style: OutlinedButton.styleFrom(
                            minimumSize: const Size(0, 36),
                            padding: const EdgeInsets.symmetric(
                                horizontal: 12, vertical: 8),
                            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                            visualDensity: VisualDensity.compact),
                        onPressed: () => _purchase(group, favorite, inventory),
                        icon: const Icon(Icons.receipt_long_outlined, size: 18),
                        label: Text(t('구매 기록', 'Record'))),
                  ]),
                  if (group.sources.length > 1)
                    ExpansionTile(
                        tilePadding: EdgeInsets.zero,
                        childrenPadding: const EdgeInsets.only(bottom: 8),
                        title: Text(t('목록별 재료 보기', 'View source lists'),
                            style: Theme.of(context).textTheme.labelLarge),
                        children: [
                          for (final source in group.sources)
                            ListTile(
                                dense: true,
                                contentPadding: EdgeInsets.zero,
                                title: Text(source.listTitle),
                                subtitle: Text(source.item.ingredientText))
                        ]),
                ])));
  }

  bool _archived(String kind, String id) =>
      ref
          .watch(purchaseCleanupIndexProvider(null))
          .valueOrNull
          ?.contains(kind, id) ??
      false;

  Widget _favorites(List<ShoppingFavorite> favorites) {
    final visible =
        favorites.where((f) => !_archived('favorite', f.id)).toList();
    return ListView(padding: const EdgeInsets.all(16), children: [
      Text(t('재료 카드의 별표로 상품 링크를 저장하세요. 같은 재료와 단위로 다시 장볼 때 표시됩니다.',
          'Save a product link with the star on an ingredient. It appears next time for the same ingredient and unit.')),
      const SizedBox(height: 12),
      if (visible.isEmpty)
        Text(t('표시할 저장 상품이 없습니다. 보관한 상품은 보관함에서 복원할 수 있습니다.',
            'No saved products to display. Archived products can be restored from the archive.')),
      for (final favorite in visible)
        Card(
            child: Padding(
                padding: const EdgeInsets.all(14),
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(favorite.ingredientName,
                          style: Theme.of(context).textTheme.titleMedium),
                      Text(favorite.productName),
                      Text(shoppingProductUri(favorite.url)?.host ??
                          t('링크 확인 필요', 'Check link')),
                      Wrap(spacing: 8, children: [
                        TextButton.icon(
                            onPressed: shoppingProductUri(favorite.url) == null
                                ? null
                                : () =>
                                    _open(shoppingProductUri(favorite.url)!),
                            icon: const Icon(Icons.open_in_new, size: 18),
                            label: Text(t('열기', 'Open'))),
                        TextButton(
                            onPressed: () => _favorite(favorite.ingredientName,
                                favorite.unit, favorite),
                            child: Text(t('수정', 'Edit'))),
                        TextButton(
                            onPressed: () => _removeFavorite(favorite),
                            child: Text(t('삭제', 'Remove')))
                      ])
                    ]))),
    ]);
  }

  Widget _records() => ref.watch(shoppingRecordsProvider(null)).when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (_, __) =>
          _error(() => ref.invalidate(shoppingRecordsProvider(null))),
      data: (records) {
        final visible =
            records.where((r) => !_archived('record', r.id)).toList();
        return ListView(padding: const EdgeInsets.all(16), children: [
          Text(t('직접 확인한 최근 100건입니다. 외부 결제 영수증과 다를 경우 금액을 수정하세요.',
              'Your latest 100 confirmed records. Correct the amount if it differs from the store receipt.')),
          const SizedBox(height: 8),
          if (records.isEmpty)
            Text(t('아직 구매 기록이 없습니다.', 'No purchase records yet.'))
          else if (visible.isEmpty)
            Text(t('표시할 구매 기록이 없습니다. 보관한 기록은 보관함에서 복원할 수 있습니다.',
                'No purchase records to display. Archived records can be restored from the archive.')),
          for (final record in visible)
            Card(
                child: ListTile(
                    title: Text(record.name),
                    isThreeLine: true,
                    subtitle: LocalizedText(
                        '${record.createdAt.toLocal().toString().substring(0, 10)} · '
                        '${shoppingNumber(record.quantity)} ${shopUnit(context, record.unit)}\n'
                        '${record.amount == null ? t('금액 미입력', 'Amount not entered') : '${record.currency} ${shoppingNumber(record.amount)}'}'),
                    trailing: record.quantity == 0
                        ? null
                        : IconButton(
                            icon: const Icon(Icons.edit_outlined),
                            tooltip: t('결제 금액 수정', 'Correct paid amount'),
                            onPressed: () => _correctAmount(record)))),
        ]);
      });
}

class _ShoppingAmountDialog extends ConsumerStatefulWidget {
  const _ShoppingAmountDialog({required this.record});
  final ShoppingPurchaseRecord record;
  @override
  ConsumerState<_ShoppingAmountDialog> createState() =>
      _ShoppingAmountDialogState();
}

class _ShoppingAmountDialogState extends ConsumerState<_ShoppingAmountDialog> {
  late final _amount = TextEditingController(
      text: widget.record.amount == null
          ? ''
          : shoppingNumber(widget.record.amount));
  late String _currency = widget.record.currency;
  final _form = GlobalKey<FormState>();
  bool _saving = false;
  String? _error;
  String t(String ko, String en) => shopText(context, ko, en);
  @override
  void dispose() {
    _amount.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => PopScope(
      canPop: !_saving,
      child: AlertDialog(
          scrollable: true,
          title: Text(t('결제 금액 수정', 'Correct paid amount')),
          content: Form(
              key: _form,
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                Text(widget.record.name),
                TextFormField(
                    controller: _amount,
                    enabled: !_saving,
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                    decoration: InputDecoration(
                        labelText: t('실제 결제 금액', 'Amount paid')),
                    validator: (s) => (s ?? '').trim().isEmpty ||
                            (shoppingInput(s!) != null &&
                                shoppingInput(s)! >= 0 &&
                                shoppingInput(s)! <= 1e12)
                        ? null
                        : t('금액을 확인해 주세요.', 'Check the amount.')),
                DropdownButtonFormField<String>(
                    initialValue: _currency,
                    items: ['KRW', 'USD']
                        .map((c) => DropdownMenuItem(value: c, child: Text(c)))
                        .toList(),
                    onChanged:
                        _saving ? null : (c) => setState(() => _currency = c!)),
                Text(t('수량과 재고는 바뀌지 않습니다. 셰프 원가는 필요할 때 다시 불러오세요.',
                    'Quantity and inventory stay the same. Import the corrected cost into Chef Studio when needed.')),
                if (_error != null) Text(_error!),
              ])),
          actions: [
            TextButton(
                onPressed: _saving ? null : () => Navigator.pop(context),
                child: Text(t('취소', 'Cancel'))),
            FilledButton(
                onPressed: _saving
                    ? null
                    : () async {
                        if (!_form.currentState!.validate()) return;
                        setState(() {
                          _saving = true;
                          _error = null;
                        });
                        try {
                          await ref
                              .read(shoppingAssistantRepositoryProvider)
                              .correctAmount(widget.record.id,
                                  shoppingInput(_amount.text), _currency);
                          if (context.mounted) Navigator.pop(context, true);
                        } catch (_) {
                          if (mounted) {
                            setState(() => _error = t('저장하지 못했습니다. 다시 시도해 주세요.',
                                'Could not save. Try again.'));
                          }
                        } finally {
                          if (mounted) setState(() => _saving = false);
                        }
                      },
                child: Text(t('저장', 'Save')))
          ]));
}
