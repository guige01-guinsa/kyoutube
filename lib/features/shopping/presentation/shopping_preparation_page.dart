import '../../../core/localization/localized_text.dart';
import '../../../core/auth/auth_return.dart';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../auth/application/auth_providers.dart';
import '../../workspace/application/workspace_navigation.dart';
import '../../recipes/application/recipe_providers.dart';
import '../../kitchen/application/kitchen_providers.dart';
import '../../kitchen/domain/kitchen_models.dart';
import '../data/shopping_preparation_store.dart';
import '../data/shopping_classification_repository.dart';
import '../data/shopping_assistant_repository.dart';
import '../data/shopping_affiliate_repository.dart';
import '../domain/shopping_assistant.dart';
import '../domain/shopping_preparation.dart';
import 'shopping_assistant_dialogs.dart';
import 'shopping_store_search_dialog.dart';
import 'coupang_purchase_planner.dart';
import 'ingredient_thumbnail.dart';
import '../application/shopping_market_provider.dart';
import '../domain/shopping_market.dart';
import 'shopping_market_widgets.dart';
import 'coupang_disclosure.dart';
import 'manual_shopping_dialog.dart';
import '../domain/shopping_navigation.dart';

class ShoppingPreparationPage extends ConsumerWidget {
  const ShoppingPreparationPage(
      {super.key,
      this.listId,
      this.embedded = false,
      this.purchasing = false,
      this.onConfirmed,
      this.onEditing});
  final String? listId;
  final bool embedded, purchasing;
  final VoidCallback? onConfirmed, onEditing;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final account = ref.watch(activeAccountIdProvider);
    final lists = ref.watch(kitchenShoppingListsProvider);
    final inventory = ref.watch(kitchenIngredientsProvider);
    String t(String ko, String en) => shopText(context, ko, en);
    Widget body;
    if (account == null) {
      body = Center(
          child: FilledButton(
              onPressed: () => context.push(loginFor(
                  GoRouterState.of(context).uri.toString(),
                  resume: true)),
              child: Text(t('로그인하고 장보기', 'Sign in to shop'))));
    } else if (lists.isLoading || inventory.isLoading) {
      body = const Center(child: CircularProgressIndicator());
    } else if (lists.hasError || inventory.hasError) {
      body = Center(
          child: TextButton(
              onPressed: () {
                ref.invalidate(kitchenShoppingListsProvider);
                ref.invalidate(kitchenIngredientsProvider);
              },
              child: Text(t('정보를 다시 불러오기', 'Reload information'))));
    } else {
      final active =
          lists.requireValue.where((l) => l.status == 'active').toList();
      final identities = shoppingPurchaseGroups(active)
          .map(preparationIdentity)
          .toList()
        ..sort();
      final stock = inventory.requireValue
          .map((i) =>
              jsonEncode([i.id, i.name, i.quantity, i.unit, i.expiresOn]))
          .toList()
        ..sort();
      // Refresh quantities and reconfirm stock on a new day or source change.
      final fingerprint = jsonEncode([
        identities,
        stock,
        DateTime.now().toIso8601String().substring(0, 10)
      ]);
      body = _PreparationWorkspace(
          key: ValueKey('$account:$fingerprint:$listId'),
          account: account,
          fingerprint: fingerprint,
          lists: active,
          inventory: inventory.requireValue,
          listId: listId,
          purchasing: purchasing,
          onConfirmed: onConfirmed,
          onEditing: onEditing,
          embedded: embedded);
    }
    return Scaffold(
        appBar: embedded
            ? null
            : AppBar(title: Text(t('장보기 목록 정리', 'Prepare shopping list'))),
        body: Center(
            child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 900),
                child: body)));
  }
}

class _PreparationWorkspace extends ConsumerStatefulWidget {
  const _PreparationWorkspace(
      {super.key,
      required this.account,
      required this.fingerprint,
      required this.lists,
      required this.inventory,
      this.purchasing = false,
      this.embedded = false,
      this.onConfirmed,
      this.onEditing,
      this.listId});
  final String account, fingerprint;
  final String? listId;
  final List<KitchenShoppingList> lists;
  final List<KitchenIngredient> inventory;
  final bool purchasing, embedded;
  final VoidCallback? onConfirmed, onEditing;
  @override
  ConsumerState<_PreparationWorkspace> createState() =>
      _PreparationWorkspaceState();
}

class _PreparationWorkspaceState extends ConsumerState<_PreparationWorkspace> {
  late final _store = ref.read(shoppingPreparationStoreProvider).session();
  final _edits = <String, PreparedPurchase>{};
  final _approved = <String, String>{};
  List<List<ShoppingPurchaseGroup>> _matches = [];
  int _aiPage = 0;
  late Set<String> _selected = widget.lists
      .where((l) => widget.listId == null || l.id == widget.listId)
      .map((l) => l.id)
      .toSet();
  bool _loading = true,
      _saving = false,
      _confirmed = false,
      _loadFailed = false;
  String? _error;
  String t(String ko, String en) => shopText(context, ko, en);
  List<ShoppingPurchaseGroup> get _rawGroups => shoppingPurchaseGroups(
      widget.lists.where((l) => _selected.contains(l.id)).toList());
  List<ShoppingPurchaseGroup> get groups =>
      mergePreparedGroups(_rawGroups, _approved);
  PreparedPurchase entry(ShoppingPurchaseGroup g) =>
      _edits[preparationIdentity(g)] ??
      PreparedPurchase(
          category: shoppingCategory(g.name),
          stock: 0,
          quantity: g.neededQuantity);

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _loadFailed = false;
      _error = null;
    });
    try {
      final data = await _store.read(widget.account);
      if (!mounted) return;
      _edits.clear();
      _approved.clear();
      _confirmed = false;
      final same = data?['fingerprint'] == widget.fingerprint;
      final additions = data?['fingerprint'] is String &&
          preparationHasOnlyAdditions(
              data!['fingerprint'] as String, widget.fingerprint);
      if (data != null && (same || additions)) {
        final selected = (data['selected'] as List).cast<String>().toSet();
        if (additions) {
          final previousLists = (data['listIds'] as List? ?? selected.toList())
              .cast<String>()
              .toSet();
          selected.addAll(widget.lists
              .where((l) => !previousLists.contains(l.id))
              .map((l) => l.id));
        }
        final edits = (data['edits'] as Map<String, dynamic>).map((k, v) =>
            MapEntry(k, PreparedPurchase.fromJson(v as Map<String, dynamic>)));
        // An explicit list link must never inherit a different saved selection.
        _selected = widget.listId == null
            ? selected.intersection(widget.lists.map((l) => l.id).toSet())
            : widget.lists
                .where((l) => l.id == widget.listId)
                .map((l) => l.id)
                .toSet();
        _approved
            .addAll(Map<String, String>.from(data['approved'] as Map? ?? {}));
        final identities = groups.map(preparationIdentity).toSet();
        _edits.addAll(Map.fromEntries(
            edits.entries.where((e) => identities.contains(e.key))));
        _confirmed = _store.status != PreparationSync.conflict &&
            same &&
            data['confirmed'] == true &&
            selected.length == _selected.length &&
            selected.containsAll(_selected) &&
            groups.isNotEmpty &&
            groups.every((g) => entry(g).ready);
      }
    } catch (_) {
      if (mounted) {
        _loadFailed = true;
        _error = t('구매 리스트를 불러오지 못했습니다.', 'Could not load the purchase list.');
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<bool> _save({bool confirm = false}) async {
    if (ref.read(activeAccountIdProvider) != widget.account) return false;
    var saved = false;
    setState(() {
      _saving = true;
      _error = null;
      _confirmed = false;
    });
    try {
      if (confirm && ref.read(shoppingMarketProvider).isKorea) {
        for (final g in groups
            .where((g) => entry(g).included && entry(g).coupang != null)) {
          final plan = entry(g).coupang!;
          final current =
              await ref.read(shoppingAffiliateRepositoryProvider).find(g.name);
          if (!current.any(plan.matches)) {
            ref.invalidate(shoppingAffiliatesProvider(g.name));
            throw StateError('Changed Coupang product');
          }
        }
        if (!mounted || ref.read(activeAccountIdProvider) != widget.account) {
          return false;
        }
      }
      await _store.write(widget.account, {
        'fingerprint': widget.fingerprint,
        'listIds': widget.lists.map((l) => l.id).toList(),
        'selected': _selected.toList(),
        'edits': _edits.map((k, v) => MapEntry(k, v.toJson())),
        'approved': _approved,
        'confirmed': confirm
      });
      if (mounted && ref.read(activeAccountIdProvider) == widget.account) {
        saved = true;
        setState(() => _confirmed = confirm);
      }
    } on PreparationConflict {
      if (mounted) {
        setState(() => _error = t('다른 기기에서 목록을 수정했습니다. 내 수정은 이 기기에 보관되어 있습니다.',
            'Another device changed this list. Your edits are kept on this device.'));
      }
    } catch (_) {
      if (mounted) {
        setState(() => _error =
            t('저장하지 못했습니다. 다시 시도해 주세요.', 'Could not save. Try again.'));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
    if (confirm && mounted && _confirmed) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _confirmed) widget.onConfirmed?.call();
      });
    }
    return saved;
  }

  Future<void> _reopen() async {
    if (await _save() && mounted) widget.onEditing?.call();
  }

  Future<void> _addManual() async {
    if (!await _save() || !mounted) return;
    final id = await showDialog<String>(
        context: context,
        barrierDismissible: false,
        builder: (_) => ShoppingAccountGuard(
            child: ManualShoppingDialog(owner: widget.account)));
    if (!mounted ||
        id == null ||
        ref.read(activeAccountIdProvider) != widget.account) {
      return;
    }
    ref.invalidate(kitchenShoppingListsProvider);
    ref.invalidate(kitchenSummaryProvider);
    if (widget.listId != null) {
      context.go(shoppingPath(stage: ShoppingStage.prepare));
    } else {
      widget.onEditing?.call();
    }
  }

  Future<void> _edit(ShoppingPurchaseGroup g) async {
    final value = await showDialog<PreparedPurchase>(
        context: context,
        builder: (_) => ShoppingAccountGuard(
            child: _PreparationEditor(
                group: g,
                value: entry(g),
                knownStock: g.knownStock(widget.inventory))));
    if (!mounted || value == null) return;
    setState(() => _edits[preparationIdentity(g)] = value);
    await _save();
  }

  Future<void> _record(ShoppingPurchaseGroup g) async {
    if (g.sources.map((s) => shoppingNameKey(s.item.name)).toSet().length > 1) {
      final ids = g.sources.map((s) => s.item.id).toSet();
      final original = _rawGroups
          .where((r) => r.sources.any((s) => ids.contains(s.item.id)))
          .toList();
      final selected = await showDialog<ShoppingPurchaseGroup>(
          context: context,
          builder: (ctx) => ShoppingAccountGuard(
                  child: SimpleDialog(
                title: Text(t('원래 재료별 구매 기록', 'Record original ingredients')),
                children: [
                  for (final item in original)
                    SimpleDialogOption(
                        onPressed: () => Navigator.pop(ctx, item),
                        child: LocalizedText(
                            '${item.name} · ${shoppingNumber(item.neededQuantity)} ${shopUnit(context, item.unit)}'))
                ],
              )));
      if (selected != null && mounted) await _record(selected);
      return;
    }
    final value = entry(g);
    final saved = await showDialog<bool>(
        context: context,
        barrierDismissible: false,
        builder: (_) => ShoppingAccountGuard(
            child: ShoppingPurchaseDialog(
                group: g,
                knownStock: g.knownStock(widget.inventory),
                confirmedStock: value.stock,
                suggestedQuantity: ref.read(shoppingMarketProvider).isKorea
                    ? value.purchaseQuantity
                    : value.quantity,
                purchaseLabel: ref.read(shoppingMarketProvider).isKorea
                    ? value.coupang?.offer.title
                    : null)));
    if (saved == true && mounted) {
      ref.invalidate(kitchenShoppingListsProvider);
      ref.invalidate(kitchenIngredientsProvider);
      ref.invalidate(kitchenSummaryProvider);
      ref.invalidate(shoppingRecordsProvider);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_loadFailed) {
      return Center(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
        Text(_error!),
        TextButton(onPressed: _load, child: Text(t('다시 시도', 'Try again')))
      ]));
    }
    final all = groups;
    final market = ref.watch(shoppingMarketProvider);
    final aiCount = all.where((g) => entry(g).included).length;
    final aiPages = (aiCount + 19) ~/ 20;
    final ready = all.isNotEmpty && all.every((g) => entry(g).ready);
    final buying =
        all.where((g) => entry(g).included && entry(g).quantity != 0).toList();
    final omitted =
        all.where((g) => !entry(g).included || entry(g).quantity == 0).toList();
    return WorkspaceEditGuard(
        dirty: false,
        busy: _saving,
        confirmLeave: () async => false,
        child: CoupangDisclosureLayout(
            respectShoppingMarket: true,
            ingredients: buying.map((g) => g.name),
            hasSelection: buying.any((g) => entry(g).coupang != null),
            child: ListView(padding: const EdgeInsets.all(16), children: [
              ShoppingMarketSelector(enabled: !_saving),
              Text(
                  widget.purchasing && _confirmed
                      ? t('구매처에서 결제한 뒤 실제 구매량을 기록하세요.',
                          'Buy at your store, then record the actual quantity.')
                      : market.isKorea
                          ? t('필요량 확인 → 쿠팡 상품 선택 → 구매',
                              'Check amounts → choose a Coupang product → buy')
                          : context.tr('필요량 확인 → 현지 상품 검색 → 판매처에서 구매'),
                  style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 8),
              Text(market.isKorea
                  ? t('필요량은 레시피와 인분으로 계산됩니다. 쿠팡에서 판매 단위·수량을 선택하세요.',
                      'Amounts come from your recipe and servings. Choose the pack and quantity at Coupang.')
                  : context.tr('필요량을 참고하여 재료별로 검색하세요. 실제 구매 수량은 판매처에서 선택합니다.')),
              const SizedBox(height: 12),
              if (_confirmed)
                OutlinedButton.icon(
                    onPressed: _saving ? null : _reopen,
                    icon: const Icon(Icons.edit_outlined),
                    label:
                        Text(t('목록 수정·재료 추가', 'Edit list or add ingredients')))
              else
                FilledButton.tonalIcon(
                    onPressed: _saving ? null : _addManual,
                    icon: const Icon(Icons.add),
                    label: Text(t('재료 직접 추가', 'Add ingredients'))),
              if (!widget.purchasing || !_confirmed) ...[
                Wrap(spacing: 8, runSpacing: 8, children: [
                  FilterChip(
                      label: Text(t('모든 목록 합산', 'All lists')),
                      selected: _selected.length == widget.lists.length,
                      onSelected: _saving
                          ? null
                          : (v) {
                              setState(() {
                                _selected = v
                                    ? widget.lists.map((l) => l.id).toSet()
                                    : {};
                                _edits.clear();
                                _approved.clear();
                                _matches = [];
                              });
                              _save();
                            }),
                  for (final list in widget.lists)
                    FilterChip(
                        label: ConstrainedBox(
                            constraints: const BoxConstraints(maxWidth: 200),
                            child: Text(list.title,
                                maxLines: 2, overflow: TextOverflow.ellipsis)),
                        selected: _selected.contains(list.id),
                        onSelected: _saving
                            ? null
                            : (v) {
                                setState(() {
                                  v
                                      ? _selected.add(list.id)
                                      : _selected.remove(list.id);
                                  _edits.clear();
                                  _approved.clear();
                                  _matches = [];
                                });
                                _save();
                              })
                ]),
                const SizedBox(height: 12),
                if (_error != null)
                  Text(_error!,
                      style: TextStyle(
                          color: Theme.of(context).colorScheme.error)),
                if (all.any((g) => entry(g).included)) ...[
                  if (aiPages > 1) ...[
                    Text(t(
                        'AI 확인 범위 (최대 20개)', 'Items for AI review (up to 20)')),
                    Wrap(spacing: 6, children: [
                      for (var page = 0; page < aiPages; page++)
                        ChoiceChip(
                            label: LocalizedText(
                                '${page * 20 + 1}–${(page + 1) * 20 > aiCount ? aiCount : (page + 1) * 20}'),
                            selected: (_aiPage < aiPages ? _aiPage : 0) == page,
                            onSelected: _saving
                                ? null
                                : (_) => setState(() => _aiPage = page))
                    ]),
                  ],
                  OutlinedButton.icon(
                      onPressed: _saving ? null : _classify,
                      icon: const Icon(Icons.auto_awesome_outlined),
                      label: Text(t('AI 분류·같은 재료 찾기',
                          'AI categories and matching ingredients'))),
                  Text(t(
                      '재료 이름만 전송합니다. 한 번에 최대 20개를 추천하며 기존 AI 사용 한도가 적용됩니다. 추천은 수정할 수 있습니다.',
                      'Only ingredient names are sent. Up to 20 items per request, using your existing AI allowance. Suggestions are editable.')),
                ],
              ],
              for (final match in _matches)
                Card(
                    child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Text(
                                  t('AI 동일 재료 추천',
                                      'AI matching ingredient suggestion'),
                                  style:
                                      Theme.of(context).textTheme.titleMedium),
                              Text(match
                                  .map((g) =>
                                      '${g.name}: ${shoppingNumber(g.neededQuantity)} ${shopUnit(context, g.unit)}')
                                  .join('\n')),
                              Text(t(
                                  '같은 재료인지 확인하세요. 호환 단위만 합치며, 보유량과 구매량은 합친 뒤 다시 확인합니다.',
                                  'Confirm these are the same ingredient. Only compatible units are merged; recheck stock and purchase amounts afterward.')),
                              FilledButton(
                                  onPressed: _saving
                                      ? null
                                      : () => _approveMatch(match),
                                  child: Text(t('같은 재료로 확인·합치기',
                                      'Confirm same ingredient and merge'))),
                              TextButton(
                                  onPressed: _saving
                                      ? null
                                      : () => setState(
                                          () => _matches.remove(match)),
                                  child: Text(t('따로 유지', 'Keep separate'))),
                            ]))),
              if (_approved.isNotEmpty)
                TextButton(
                    onPressed: _saving
                        ? null
                        : () {
                            setState(() {
                              _approved.clear();
                              _edits.clear();
                              _matches = [];
                            });
                            _save();
                          },
                    child: Text(t('동일 재료 합치기 취소', 'Undo ingredient merges'))),
              if (all.isEmpty)
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(t('구매할 목록을 선택해 주세요.', 'Select a list to shop from.')),
                  if (widget.lists.isEmpty)
                    FilledButton.icon(
                        onPressed: () => context.go('/my-recipes'),
                        icon: const Icon(Icons.menu_book_outlined),
                        label: Text(t(
                            '레시피에서 재료 가져오기', 'Add ingredients from recipes'))),
                ]),
              if (!_confirmed && !ready && all.isNotEmpty) ...[
                Text(t('수량이 불명확한 재료는 원래 목록에서 보완하거나 이번 구매에서 제외해 주세요.',
                    'Correct unclear quantities in the source lists or exclude those items from this purchase.')),
                TextButton(
                    onPressed: () => context.push('/kitchen?tab=shopping'),
                    child:
                        Text(t('원래 목록에서 수량 보완', 'Correct source quantities')))
              ],
              for (final category in ShoppingCategory.values)
                if (buying.any((g) => entry(g).category == category)) ...[
                  Padding(
                      padding: const EdgeInsets.only(top: 20, bottom: 8),
                      child: Text(t(category.ko, category.en),
                          style: Theme.of(context).textTheme.titleLarge)),
                  for (final g
                      in buying.where((g) => entry(g).category == category))
                    _card(g)
                ],
              if (omitted.isNotEmpty)
                ExpansionTile(
                    title: Text(t('이번 구매에서 제외', 'Excluded from this purchase')),
                    children: [for (final g in omitted) _card(g)]),
              const SizedBox(height: 16),
              if (_confirmed)
                OutlinedButton.icon(
                    onPressed: _saving ? null : _reopen,
                    icon: const Icon(Icons.edit_outlined),
                    label: Text(
                        t('구매 리스트 확정됨 · 목록 수정', 'List confirmed · Edit list'))),
              if (!_confirmed)
                FilledButton.icon(
                    onPressed:
                        _saving || !ready ? null : () => _save(confirm: true),
                    icon:
                        Icon(_confirmed ? Icons.check_circle : Icons.checklist),
                    label: Text(_saving
                        ? t('저장 중', 'Saving')
                        : t('구매 리스트 확정', 'Confirm purchase list'))),
              if (_confirmed &&
                  !widget.purchasing &&
                  widget.onConfirmed != null)
                FilledButton.icon(
                    onPressed: _saving ? null : widget.onConfirmed,
                    icon: const Icon(Icons.shopping_cart_outlined),
                    label: Text(t('구매 계속하기', 'Continue shopping'))),
              if (_confirmed)
                TextButton.icon(
                    onPressed: () async {
                      final text = <String>[];
                      for (final c in ShoppingCategory.values) {
                        final rows =
                            buying.where((g) => entry(g).category == c);
                        if (rows.isEmpty) continue;
                        text.add(t(c.ko, c.en));
                        text.addAll(rows.map((g) =>
                            '${market.isKorea ? g.name : ingredientSearchName(g.name, market.language)}: ${shoppingNumber(market.isKorea ? entry(g).purchaseQuantity : entry(g).quantity)} ${shopUnit(context, g.unit)}${!market.isKorea || entry(g).coupang == null ? '' : ' · ${entry(g).coupang!.count} ${entry(g).coupang!.pack.label}'}'));
                      }
                      await Clipboard.setData(
                          ClipboardData(text: text.join('\n')));
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                            content: Text(t(
                                '구매 리스트를 복사했습니다.', 'Purchase list copied.'))));
                      }
                    },
                    icon: const Icon(Icons.copy),
                    label: Text(
                        t('분류별 구매 리스트 복사', 'Copy categorized purchase list'))),
              _syncStatus(),
              Text(t('원래 목록이나 보유 재료가 바뀌거나 날짜가 바뀌면 다시 확인합니다.',
                  'Recheck when source lists, inventory or the date change.')),
            ])));
  }

  Widget _syncStatus() {
    final status = _store.status;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(switch (status) {
        PreparationSync.synced => t('계정에 저장됨 · 다른 기기에서도 불러올 수 있습니다.',
            'Saved to your account · Available on your other devices.'),
        PreparationSync.conflict => t('다른 기기와 수정 내용이 다릅니다. 저장본을 선택해 주세요.',
            'Edits differ between devices. Choose the saved copy to use.'),
        PreparationSync.offline => t('이 기기에 저장됨 · 계정 동기화를 다시 시도해 주세요.',
            'Saved on this device · Retry account sync.'),
        PreparationSync.local => t('이 기기에 저장됨', 'Saved on this device'),
      }),
      if (status == PreparationSync.offline)
        TextButton(
            onPressed: _saving ? null : _load,
            child: Text(t('동기화 다시 시도', 'Retry sync'))),
      if (status == PreparationSync.conflict)
        TextButton(
            onPressed: _saving
                ? null
                : () async {
                    setState(() => _saving = true);
                    try {
                      await _store.discardPending(widget.account);
                      if (mounted) await _load();
                    } catch (_) {
                      if (mounted) {
                        setState(() => _error = t(
                            '정보를 다시 불러오지 못했습니다. 다시 시도해 주세요.',
                            'Could not reload. Try again.'));
                      }
                    } finally {
                      if (mounted) setState(() => _saving = false);
                    }
                  },
            child: Text(t('내 수정 취소 · 다른 기기 저장본 불러오기',
                'Discard my edits · Load the other device’s copy'))),
    ]);
  }

  Future<void> _classify() async {
    final eligible = groups.where((g) => entry(g).included).toList();
    final candidates = eligible
        .skip((_aiPage * 20 < eligible.length ? _aiPage : 0) * 20)
        .take(20)
        .toList();
    if (candidates.isEmpty) return;
    setState(() {
      _saving = true;
      _confirmed = false;
      _error = null;
    });
    try {
      final result = await ref
          .read(shoppingClassificationRepositoryProvider)
          .classify(candidates.map((g) => g.name).toList());
      if (!mounted) return;
      for (var i = 0; i < candidates.length; i++) {
        final g = candidates[i], old = entry(g);
        _edits[preparationIdentity(g)] = PreparedPurchase(
            category: result.categories[i],
            stock: old.stock,
            quantity: old.quantity,
            coupang: old.coupang,
            included: old.included);
      }
      _matches = [
        for (final ids in result.matches) [for (final i in ids) candidates[i]]
      ];
      await _save();
      if (mounted && _error == null) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(t('AI 분류 추천을 반영했습니다. 분류를 확인하고 구매 리스트를 확정해 주세요.',
                'AI category suggestions applied. Review the categories before confirming your list.'))));
      }
    } catch (_) {
      if (mounted) {
        setState(() => _error = t(
            'AI 분류를 이용할 수 없습니다. 사용 한도와 연결 상태를 확인하거나 직접 분류해 주세요.',
            'AI classification is unavailable. Check your allowance and connection, or choose categories manually.'));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _approveMatch(List<ShoppingPurchaseGroup> match) async {
    final ids = match.expand((g) => g.sources).map((s) => s.item.id).toSet();
    final representativeIds = match.first.sources.map((s) => s.item.id).toSet();
    final raw = _rawGroups;
    final representative = raw.firstWhere(
        (g) => g.sources.any((s) => representativeIds.contains(s.item.id)));
    final target = preparationIdentity(representative);
    setState(() {
      for (final g
          in raw.where((g) => g.sources.any((s) => ids.contains(s.item.id)))) {
        _approved[preparationIdentity(g)] = target;
      }
      // Never carry separately deducted stock into a newly merged group.
      _edits.clear();
      _matches = [];
    });
    await _save();
  }

  Widget _card(ShoppingPurchaseGroup g) {
    final stored = entry(g);
    final savedIngredients = stored.coupang?.offer.data['ingredients'];
    final savedMatches = savedIngredients is List &&
        savedIngredients
            .whereType<String>()
            .map(shoppingNameKey)
            .contains(shoppingNameKey(g.name));
    final v = stored.coupang == null || savedMatches
        ? stored
        : PreparedPurchase(
            category: stored.category,
            stock: stored.stock,
            quantity: stored.quantity,
            included: stored.included);
    final unit = shopUnit(context, g.unit);
    final mergedNames =
        g.sources.map((s) => shoppingNameKey(s.item.name)).toSet().length > 1;
    return Card(
        child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(children: [
                    IngredientThumbnail(ingredient: g.name),
                    const SizedBox(width: 10),
                    Expanded(
                        child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                          Text(g.name,
                              style: Theme.of(context).textTheme.titleMedium),
                          if (v.quantity != null)
                            LocalizedText(
                                '${t('구매', 'Buy')} ${shoppingNumber(v.quantity)} $unit')
                          else
                            Chip(
                                visualDensity: VisualDensity.compact,
                                label: Text(t('수량 확인 필요', 'Check quantity'))),
                        ])),
                    IconButton(
                        tooltip: t('구매 항목 수정', 'Edit purchase item'),
                        onPressed: _saving ? null : () => _edit(g),
                        icon: const Icon(Icons.edit_outlined)),
                  ]),
                  if (v.included &&
                      v.quantity != 0 &&
                      !ref.watch(shoppingMarketProvider).isKorea)
                    OverseasIngredientSearch(
                      key: ValueKey('overseas-${preparationIdentity(g)}'),
                      ingredient: g.name,
                      enabled: !_saving,
                    ),
                  if (v.included &&
                      v.quantity != 0 &&
                      ref.watch(shoppingMarketProvider).isKorea)
                    CoupangPurchasePlanner(
                        key: ValueKey('coupang-${preparationIdentity(g)}'),
                        ingredient: g.name,
                        unit: g.unit,
                        needed: v.quantity,
                        value: v.coupang,
                        enabled: !_saving,
                        emphasizeCheckout: !widget.purchasing,
                        onChanged: (plan) async {
                          setState(() => _edits[preparationIdentity(g)] =
                              PreparedPurchase(
                                  category: v.category,
                                  stock: v.stock,
                                  quantity: v.quantity,
                                  included: v.included,
                                  coupang: plan));
                          await _save();
                        }),
                  if (mergedNames) ...[
                    TextButton.icon(
                        style: TextButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 4)),
                        onPressed: () => showDialog<void>(
                            context: context,
                            builder: (_) => AlertDialog(
                                    title: Text(
                                        t('합산한 재료', 'Combined ingredients')),
                                    content: LocalizedText(
                                        '${g.sources.map((s) => '${s.item.name}: ${s.item.ingredientText}').join('\n')}\n\n${t('합친 구매량은 구매 준비용입니다. 실제 구매 기록은 원래 재료별로 확인해 주세요.', 'The merged amount is for shopping preparation. Record actual purchases against the original ingredients.')}'),
                                    actions: [
                                      TextButton(
                                          onPressed: () =>
                                              Navigator.pop(context),
                                          child: Text(t('닫기', 'Close')))
                                    ])),
                        icon: const Icon(Icons.info_outline, size: 18),
                        label:
                            Text(t('합산한 재료 보기', 'View combined ingredients'))),
                  ],
                  Wrap(spacing: 8, runSpacing: 8, children: [
                    if (_confirmed &&
                        (!widget.embedded || widget.purchasing) &&
                        v.included &&
                        v.quantity != null &&
                        v.quantity! > 0) ...[
                      FilledButton(
                          onPressed: () => showDialog<void>(
                              context: context,
                              builder: (_) => ShoppingAccountGuard(
                                  child: ShoppingStoreSearchDialog(
                                      group: g, purchaseQuantity: v.quantity))),
                          child: Text(t('구매처 찾기', 'Find a store'))),
                      OutlinedButton(
                          onPressed: () => _record(g),
                          child: Text(mergedNames
                              ? t('원래 재료별 구매 기록', 'Record original ingredients')
                              : t('수량 확인 · 구매 기록', 'Check & record')))
                    ],
                    if (_confirmed &&
                        (!widget.embedded || widget.purchasing) &&
                        v.included &&
                        v.quantity == 0)
                      OutlinedButton(
                          onPressed: () => _record(g),
                          child:
                              Text(t('보유 재료로 준비 확인', 'Confirm using stock'))),
                  ]),
                ])));
  }
}

class _PreparationEditor extends StatefulWidget {
  const _PreparationEditor(
      {required this.group, required this.value, this.knownStock});
  final ShoppingPurchaseGroup group;
  final PreparedPurchase value;
  final double? knownStock;
  @override
  State<_PreparationEditor> createState() => _PreparationEditorState();
}

class _PreparationEditorState extends State<_PreparationEditor> {
  final _form = GlobalKey<FormState>();
  late final _stock =
      TextEditingController(text: shoppingNumber(widget.value.stock));
  late final _quantity = TextEditingController(
      text: widget.value.quantity == null
          ? ''
          : shoppingNumber(widget.value.quantity));
  late var _category = widget.value.category;
  late var _included = widget.value.included;
  String t(String ko, String en) => shopText(context, ko, en);
  @override
  void dispose() {
    _stock.dispose();
    _quantity.dispose();
    super.dispose();
  }

  String? valid(String? input) {
    final n = shoppingInput(input ?? '');
    return n == null || n < 0 || n > 1e9
        ? t('0 이상의 올바른 수량을 입력해 주세요.', 'Enter a valid amount of zero or more.')
        : null;
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
          scrollable: true,
          title: Text(widget.group.name),
          content: SizedBox(
              width: 430,
              child: Form(
                  key: _form,
                  child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        DropdownButtonFormField<ShoppingCategory>(
                            initialValue: _category,
                            isExpanded: true,
                            decoration:
                                InputDecoration(labelText: t('분류', 'Category')),
                            items: [
                              for (final c in ShoppingCategory.values)
                                DropdownMenuItem(
                                    value: c, child: Text(t(c.ko, c.en)))
                            ],
                            onChanged: (v) => setState(() => _category = v!)),
                        CheckboxListTile(
                            contentPadding: EdgeInsets.zero,
                            title: Text(
                                t('이번 구매에 포함', 'Include in this purchase')),
                            value: _included,
                            onChanged: (v) => setState(() => _included = v!)),
                        Text(widget.group.sources
                            .map((s) =>
                                '${s.listTitle}: ${s.item.ingredientText}')
                            .join('\n')),
                        if (widget.group.neededQuantity != null) ...[
                          if (widget.knownStock != null)
                            LocalizedText(
                                '${t('재고 기록 참고', 'Inventory reference')}: ${shoppingNumber(widget.knownStock)} ${shopUnit(context, widget.group.unit)}'),
                          TextFormField(
                              controller: _stock,
                              enabled: _included,
                              keyboardType:
                                  const TextInputType.numberWithOptions(
                                      decimal: true),
                              decoration: InputDecoration(
                                  labelText: t('확인한 보유량', 'Checked stock'),
                                  suffixText:
                                      shopUnit(context, widget.group.unit)),
                              validator: _included ? valid : null,
                              onChanged: (s) {
                                final n = shoppingInput(s);
                                if (n != null && n >= 0 && n <= 1e9) {
                                  _quantity.text =
                                      shoppingNumber(widget.group.toBuy(n));
                                }
                              }),
                          TextFormField(
                              controller: _quantity,
                              enabled: _included,
                              keyboardType:
                                  const TextInputType.numberWithOptions(
                                      decimal: true),
                              decoration: InputDecoration(
                                  labelText: t('구매 예정량', 'Planned purchase'),
                                  suffixText:
                                      shopUnit(context, widget.group.unit)),
                              validator: _included ? valid : null),
                          Text(t(
                              '포장 규격에 맞춰 구매량을 수정할 수 있습니다. 실제 구매·수령량은 나중에 따로 기록합니다.',
                              'Adjust the amount to the package size. Record the actual purchase or delivery separately.')),
                        ] else
                          Text(t('수량이 불명확한 재료는 원래 목록에서 보완하거나 이번 구매에서 제외해 주세요.',
                              'Correct unclear quantities in the source lists or exclude those items from this purchase.')),
                      ]))),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(context),
                child: Text(t('취소', 'Cancel'))),
            FilledButton(
                onPressed: () {
                  if (!_form.currentState!.validate()) return;
                  Navigator.pop(
                      context,
                      PreparedPurchase(
                          category: _category,
                          included: _included,
                          coupang: _included &&
                                  shoppingInput(_stock.text) ==
                                      widget.value.stock &&
                                  shoppingInput(_quantity.text) ==
                                      widget.value.quantity
                              ? widget.value.coupang
                              : null,
                          stock: shoppingInput(_stock.text) ?? 0,
                          quantity: widget.group.neededQuantity == null
                              ? null
                              : shoppingInput(_quantity.text)));
                },
                child: Text(t('저장', 'Save')))
          ]);
}
