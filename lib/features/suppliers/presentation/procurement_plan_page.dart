import '../../../core/localization/localized_text.dart';
import '../../../core/auth/auth_return.dart';
import '../../guide/presentation/guide_help_button.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../auth/application/auth_providers.dart';
import '../../kitchen/application/kitchen_providers.dart';
import '../../shopping/data/supplier_request_repository.dart';
import '../../shopping/domain/shopping_assistant.dart';
import '../../shopping/domain/supplier_request.dart';
import '../../shopping/presentation/shopping_assistant_dialogs.dart';
import '../../shopping/presentation/supplier_request_editor.dart';
import '../../shopping/presentation/supplier_requests_page.dart';
import '../data/supplier_catalog_repository.dart';
import '../domain/procurement_plan.dart';
import '../domain/supplier_catalog.dart';
import 'supplier_business_page.dart';
import 'supplier_directory_page.dart';
import '../application/procurement_session.dart';
import '../../shopping/presentation/purchase_progress.dart';
import '../../workspace/application/workspace_navigation.dart';

ProcurementPlan _calculatePlan(
        (List<IngredientCandidates>, ProcurementPriority) input) =>
    createProcurementPlan(input.$1, input.$2);

class ProcurementPlanPage extends ConsumerWidget {
  const ProcurementPlanPage({super.key, this.listId});
  final String? listId;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final owner = ref.watch(activeAccountIdProvider);
    if (owner == null) {
      return Scaffold(
          appBar: AppBar(
              title: Text(catalogText(
                  context, '구매요청 도우미', 'Purchase request planner'))),
          body: Center(
              child: FilledButton(
                  onPressed: () => context.push(loginFor(
                      GoRouterState.of(context).uri.toString(),
                      resume: true)),
                  child: Text(catalogText(context, '로그인', 'Sign in')))));
    }
    return ref.watch(kitchenShoppingListsProvider).when(
        loading: () =>
            const Scaffold(body: Center(child: CircularProgressIndicator())),
        error: (_, __) => Scaffold(
            body: Center(
                child: TextButton(
                    onPressed: () =>
                        ref.invalidate(kitchenShoppingListsProvider),
                    child: Text(catalogText(context, '다시 불러오기', 'Reload'))))),
        data: (lists) => _Planner(
            key: ValueKey('$owner/$listId'),
            sessionKey: listId ?? 'all',
            groups: shoppingPurchaseGroups(lists, listId: listId)));
  }
}

class _Planner extends ConsumerStatefulWidget {
  const _Planner({super.key, required this.groups, required this.sessionKey});
  final String sessionKey;
  final List<ShoppingPurchaseGroup> groups;
  @override
  ConsumerState<_Planner> createState() => _PlannerState();
}

class _PlannerState extends ConsumerState<_Planner> {
  late ProcurementSession _session;
  String? _owner;
  @override
  void initState() {
    super.initState();
    _owner = ref.read(activeAccountIdProvider);
    final sessions = ref.read(procurementSessionsProvider);
    final old = sessions[widget.sessionKey];
    if (old != null &&
        old.fingerprint ==
            ProcurementSession.sourceFingerprint(widget.groups)) {
      _session = old;
    } else {
      _session = ProcurementSession(widget.groups);
      sessions[widget.sessionKey] = _session;
    }
  }

  Map<String, SupplierRequestLine> get _lines => _session.lines;
  Set<String> get _selected => _session.selected;
  Map<String, List<PurchaseCandidate>> get _choices => _session.choices;
  Map<String, SupplierRequest> get _drafts => _session.drafts;
  Map<String, SupplierRequest> get _saved => _session.saved;
  ProcurementPriority get _priority => _session.priority;
  set _priority(ProcurementPriority value) => _session.priority = value;
  ProcurementPlan? get _plan => _session.plan;
  set _plan(ProcurementPlan? value) => _session.plan = value;
  int get _step => _session.step;
  set _step(int value) => _session.step = value;
  bool _busy = false;
  String? _message;
  String t(String ko, String en) => catalogText(context, ko, en);
  bool get en => Localizations.localeOf(context).languageCode != 'ko';
  Future<void> _candidates(String key) async {
    final line = _lines[key]!;
    if (line.quantity == null || line.quantity! <= 0 || line.unit.isEmpty) {
      setState(() => _message = t('먼저 구매 수량과 단위를 입력해 주세요.',
          'Enter the purchase quantity and unit first.'));
      return;
    }
    final choices = await showDialog<List<PurchaseCandidate>>(
        context: context,
        barrierDismissible: false,
        builder: (_) => ShoppingAccountGuard(
            child: _CandidatePicker(line: line, initial: _choices[key] ?? [])));
    if (choices != null && mounted) setState(() => _choices[key] = choices);
  }

  Future<void> _quantity(String key) async {
    final line = await showDialog<SupplierRequestLine>(
        context: context,
        builder: (_) => ShoppingAccountGuard(
            child:
                SupplierRequestLineEditor(line: _lines[key], currency: 'KRW')));
    if (line != null && mounted) {
      setState(() {
        _lines[key] = line;
        _choices.remove(key);
      });
    }
  }

  Future<void> _generate() async {
    if (_selected.isEmpty ||
        _selected.any((key) => (_choices[key] ?? []).isEmpty)) {
      setState(() => _message = t('선택한 재료마다 후보 업체를 1~3곳 선택해 주세요.',
          'Choose 1–3 candidate suppliers for every selected ingredient.'));
      return;
    }
    setState(() {
      _busy = true;
      _message = null;
    });
    try {
      final ids = _selected
          .expand((key) => (_choices[key] ?? <PurchaseCandidate>[])
              .map((c) => c.offer.product.id))
          .toSet()
          .toList();
      final fresh = {
        for (final offer in await ref
            .read(supplierCatalogRepositoryProvider)
            .currentOffers(ids))
          offer.product.id: offer
      };
      for (final key in _selected) {
        _choices[key] = [
          for (final candidate in _choices[key] ?? <PurchaseCandidate>[])
            (() {
              final offer = fresh[candidate.offer.product.id];
              if (offer == null ||
                  offer.product.contentUnit !=
                      candidate.offer.product.contentUnit) {
                throw const FormatException(
                    'Supplier changed; reselect candidates');
              }
              return PurchaseCandidate(offer,
                  contentUnitsPerPurchaseUnit:
                      candidate.contentUnitsPerPurchaseUnit);
            })()
        ];
      }
      if (!mounted || _owner != ref.read(activeAccountIdProvider)) return;
      final input = [
        for (final key in _selected)
          IngredientCandidates(
              line: _lines[key]!, choices: List.of(_choices[key] ?? []))
      ];
      final priority = _priority;
      final plan = await compute(_calculatePlan, (input, priority));
      if (mounted) {
        setState(() {
          _plan = plan;
          _step = 2;
          _drafts.clear();
          _saved.clear();
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() => _message = t(
            '업체나 상품이 변경됐을 수 있습니다. 재료별 후보 1~3곳, 환산 기준, 동일 통화 여부를 다시 확인해 주세요.',
            'A supplier or product may have changed. Recheck 1–3 suppliers per ingredient, conversions and a single currency.'));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _edit(String id, {bool repeat = false}) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final repo = ref.read(supplierCatalogRepositoryProvider);
      final personal = await repo.selectSupplier(id);
      if (!mounted || _owner != ref.read(activeAccountIdProvider)) return;
      ref.invalidate(shoppingSuppliersProvider);
      final draft = repeat
          ? _saved[id]!.repeat()
          : _saved[id] ??
              _drafts.putIfAbsent(
                  id, () => _plan!.draftFor(id, personal, english: en));
      final suppliers = await ref.read(shoppingSuppliersProvider.future);
      if (!mounted) return;
      final result = await showDialog<SupplierRequest>(
          context: context,
          barrierDismissible: false,
          builder: (_) => ShoppingAccountGuard(
              child: SupplierRequestEditor(
                  suppliers: suppliers,
                  groups: widget.groups,
                  request: draft)));
      if (result != null && mounted) {
        setState(() => _saved[id] = result);
        ref.invalidate(supplierRequestsProvider);
      }
    } catch (_) {
      if (mounted) {
        setState(() => _message = t(
            '초안을 열지 못했습니다. 업체 공개 상태·내 거래처 한도·연결을 확인해 주세요.',
            'Could not open the draft. Check supplier availability, your supplier limit and connection.'));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _preview(String id) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final latest = await ref
          .read(supplierRequestRepositoryProvider)
          .request(_saved[id]!.id);
      if (!mounted || _owner != ref.read(activeAccountIdProvider)) return;
      if (latest == null) {
        setState(() {
          _saved.remove(id);
          _drafts.remove(id);
          _message = t('저장된 요청서가 삭제되었습니다. 다시 검토해 주세요.',
              'The saved request was removed. Review it again.');
        });
        return;
      }
      _saved[id] = latest;
    } catch (_) {
      if (mounted) {
        setState(() => _message = t('요청서를 새로 불러오지 못했습니다. 다시 시도해 주세요.',
            'Could not refresh the request. Please retry.'));
      }
      return;
    } finally {
      if (mounted) setState(() => _busy = false);
    }
    final action = await showDialog<String>(
        context: context,
        barrierDismissible: false,
        builder: (_) => ShoppingAccountGuard(
            child: SupplierRequestDetails(
                request: _saved[id]!,
                onChanged: (request) {
                  if (!mounted) return;
                  setState(() {
                    if (request == null) {
                      _saved.remove(id);
                      _drafts.remove(id);
                    } else {
                      _saved[id] = request;
                    }
                  });
                })));
    if (!mounted) return;
    ref.invalidate(supplierRequestsProvider);
    if (_saved.containsKey(id) && (action == 'edit' || action == 'repeat')) {
      await _edit(id, repeat: action == 'repeat');
    }
  }

  @override
  Widget build(BuildContext context) {
    final names = {
      ProcurementPriority.fewestSuppliers:
          t('최소 구매요청서 · 최소 거래처 수', 'Fewest requests · fewest suppliers'),
      ProcurementPriority.lowestPrice: t('최저 구매가격', 'Lowest purchase price'),
      ProcurementPriority.highestRating: t('평점 1순위', 'Highest rating first')
    };
    return WorkspaceEditGuard(
        dirty: _selected.isNotEmpty,
        busy: _busy,
        confirmLeave: () async => !_busy,
        child: PopScope(
            canPop: !_busy,
            child: Scaffold(
                appBar: AppBar(
                    title: Text(t('새 구매요청', 'New purchase request')),
                    actions: [
                      GuideHelpButton(
                          lesson: _step == 0
                              ? 'buy-quantity'
                              : _step == 1
                                  ? 'buy-candidates'
                                  : 'buy-compare',
                          enabled: !_busy)
                    ]),
                body: Center(
                    child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 1000),
                        child: ListView(
                            padding: const EdgeInsets.all(20),
                            children: [
                              PurchaseProgress(step: _step),
                              Text(t(
                                  '선택한 내용은 현재 앱에서 이어 쓸 수 있어요. 앱 종료 전에 요청서를 저장하세요.',
                                  'Selections remain in this app session. Save requests before closing the app.')),
                              const SizedBox(height: 12),
                              if (_message != null)
                                Padding(
                                    padding: const EdgeInsets.only(bottom: 12),
                                    child: Text(_message!,
                                        style: TextStyle(
                                            color: Theme.of(context)
                                                .colorScheme
                                                .error))),
                              if (_step <= 1) ...[
                                if (_step == 1)
                                  Text(t(
                                      '재료마다 후보 업체를 최대 3곳 선택하세요. 전체 업체 수에는 3곳 제한이 없습니다.',
                                      'Choose up to 3 suppliers for each ingredient. The entire order is not limited to 3 suppliers.')),
                                if (_lines.isEmpty)
                                  Padding(
                                      padding: const EdgeInsets.all(24),
                                      child: Text(t(
                                          '먼저 장보기 목록에 구매할 재료를 추가해 주세요.',
                                          'Add ingredients to your shopping list first.'))),
                                if (_lines.isEmpty)
                                  FilledButton.icon(
                                      onPressed: () =>
                                          context.push('/kitchen?tab=shopping'),
                                      icon: const Icon(Icons.add),
                                      label: Text(t('장보기 재료 준비하기',
                                          'Prepare shopping ingredients'))),
                                for (final entry in _lines.entries.where((e) =>
                                    _step == 0 || _selected.contains(e.key)))
                                  Card(
                                      child: Padding(
                                          padding: const EdgeInsets.all(12),
                                          child: Column(
                                              crossAxisAlignment:
                                                  CrossAxisAlignment.stretch,
                                              children: [
                                                CheckboxListTile(
                                                    contentPadding:
                                                        EdgeInsets.zero,
                                                    value: _selected
                                                        .contains(entry.key),
                                                    title:
                                                        Text(entry.value.name),
                                                    subtitle: LocalizedText(
                                                        '${shoppingNumber(entry.value.quantity)} ${shopUnit(context, entry.value.unit)}'),
                                                    onChanged: _step == 1
                                                        ? null
                                                        : (v) => setState(() {
                                                              if (v == true) {
                                                                _selected.add(
                                                                    entry.key);
                                                              } else {
                                                                _selected.remove(
                                                                    entry.key);
                                                              }
                                                            })),
                                                if (_selected
                                                    .contains(entry.key)) ...[
                                                  if (_step == 1)
                                                    Text((_choices[entry.key] ??
                                                                [])
                                                            .isEmpty
                                                        ? t('후보 미선택 · 이 재료는 아직 배정할 수 없습니다.',
                                                            'No candidates yet · this ingredient cannot be assigned.')
                                                        : (_choices[
                                                                    entry
                                                                        .key] ??
                                                                [])
                                                            .map((c) => c.offer
                                                                .supplier.name)
                                                            .join(' · ')),
                                                  Wrap(spacing: 8, children: [
                                                    TextButton(
                                                        onPressed: () =>
                                                            _quantity(
                                                                entry.key),
                                                        child: Text(t(
                                                            '구매 수량·단위 수정',
                                                            'Edit purchase quantity & unit'))),
                                                    if (_step == 1)
                                                      OutlinedButton.icon(
                                                          onPressed: () =>
                                                              _candidates(
                                                                  entry.key),
                                                          icon: const Icon(Icons
                                                              .storefront_outlined),
                                                          label: LocalizedText(
                                                              '${t('업체 후보', 'Supplier candidates')} ${_choices[entry.key]?.length ?? 0}/3'))
                                                  ]),
                                                ],
                                              ]))),
                              ],
                              if (_step == 1) ...[
                                LocalizedText(
                                    '${_selected.length}${t('개 재료 선택 완료. 구매요청 기준을 하나 선택하세요.', ' ingredients ready. Choose one purchasing priority.')}'),
                                const SizedBox(height: 12),
                                for (final p in ProcurementPriority.values)
                                  Card(
                                      child: ListTile(
                                          leading: Icon(_priority == p
                                              ? Icons.radio_button_checked
                                              : Icons.radio_button_unchecked),
                                          selected: _priority == p,
                                          onTap: _busy
                                              ? null
                                              : () =>
                                                  setState(() => _priority = p),
                                          title: Text(names[p]!),
                                          subtitle: Text(switch (p) {
                                            ProcurementPriority
                                                  .fewestSuppliers =>
                                              t('함께 공급 가능한 재료를 묶어 요청서 수를 줄입니다.',
                                                  'Combine ingredients supplied by the same business.'),
                                            ProcurementPriority.lowestPrice => t(
                                                '판매 포장 수와 업체별 배송비를 포함한 견적을 비교합니다.',
                                                'Compare selling pack quantities and delivery fees.'),
                                            ProcurementPriority.highestRating =>
                                              t('입고 확인 구매자 평점을 우선합니다. 평가 없음은 별도 표시합니다.',
                                                  'Prioritize buyer-confirmed receipt ratings; unrated suppliers remain distinct.')
                                          }))),
                                Text(t('등록 가격이 없거나 배송비·세금이 불명확하면 견적 필요로 표시합니다.',
                                    'Missing prices, delivery fees or taxes are marked as quote needed.')),
                                TextButton(
                                    onPressed: _busy
                                        ? null
                                        : () => setState(() => _step = 0),
                                    child: Text(
                                        t('이전: 재료 선택', 'Back: ingredients'))),
                              ] else if (_plan != null) ...[
                                Text(names[_priority]!,
                                    style: Theme.of(context)
                                        .textTheme
                                        .headlineSmall),
                                LocalizedText(
                                    '${_plan!.supplierIds.length}${t('개 업체 · ', ' suppliers · ')}${t('비교 예상액', 'Comparison estimate')} ${shoppingNumber(_plan!.total)} ${_plan!.purchases.first.candidate.offer.supplier.currency}'),
                                if (!_plan!.exhaustive)
                                  Text(t(
                                      '후보 조합이 많아 일부 조합을 비교한 추천안입니다. 전체 조합의 최적 결과를 보장하지 않습니다.',
                                      'This recommendation compares a bounded set of combinations; a global optimum is not guaranteed.')),
                                if (_plan!.quotesNeeded > 0)
                                  Text(t(
                                      '견적 필요 항목이 있습니다. 표시되지 않은 금액은 0원이 아닙니다.',
                                      'Some costs require quotes. Missing amounts are not zero.')),
                                if (_plan!.minimumOrderFailures > 0)
                                  Text(t(
                                      '최소 주문금액 미달 업체가 있습니다. 추가 거래 조건을 업체에 확인하세요.',
                                      'Some suppliers are below minimum order. Confirm terms with the supplier.')),
                                Text(t(
                                    '비교 시점의 등록 정보입니다. 요청서에서 수량·단가·업체를 바꾸면 위 비교 예상액과 달라집니다.',
                                    'These are catalog estimates at comparison time. Editing quantities, prices or suppliers changes the estimate.')),
                                const SizedBox(height: 12),
                                for (final id in _plan!.supplierIds)
                                  Card(
                                      child: Padding(
                                          padding: const EdgeInsets.all(16),
                                          child: Column(
                                              crossAxisAlignment:
                                                  CrossAxisAlignment.stretch,
                                              children: [
                                                Text(
                                                    _plan!
                                                        .forSupplier(id)
                                                        .first
                                                        .candidate
                                                        .offer
                                                        .supplier
                                                        .name,
                                                    style: Theme.of(context)
                                                        .textTheme
                                                        .titleLarge),
                                                for (final row
                                                    in _plan!.forSupplier(id))
                                                  LocalizedText(
                                                      '${row.line.name} → ${row.candidate.offer.product.name} · ${row.packs} ${row.candidate.offer.product.saleUnit}'),
                                                LocalizedText(
                                                    '${t('상품액', 'Subtotal')} ${shoppingNumber(_plan!.subtotal(id))} · ${t('배송비', 'Delivery')} ${shoppingNumber(_plan!.delivery(id))}'),
                                                if (_plan!.subtotal(id) !=
                                                        null &&
                                                    _plan!.subtotal(id)! <
                                                        _plan!
                                                            .forSupplier(id)
                                                            .first
                                                            .candidate
                                                            .offer
                                                            .supplier
                                                            .minimumOrder)
                                                  Text(t('최소 주문금액 미달',
                                                      'Below minimum order')),
                                                if (_saved.containsKey(id))
                                                  Text(t('요청서 저장됨',
                                                      'Request saved')),
                                                Wrap(spacing: 8, children: [
                                                  if (!_saved.containsKey(id) ||
                                                      _saved[id]!.status ==
                                                          'draft')
                                                    OutlinedButton(
                                                        onPressed: _busy
                                                            ? null
                                                            : () => _edit(id),
                                                        child: Text(_saved
                                                                .containsKey(id)
                                                            ? t('저장된 초안 수정',
                                                                'Edit saved draft')
                                                            : t('초안 수정·저장',
                                                                'Edit & save draft'))),
                                                  if (_saved.containsKey(id))
                                                    FilledButton.icon(
                                                        onPressed: _busy
                                                            ? null
                                                            : () =>
                                                                _preview(id),
                                                        icon: const Icon(Icons
                                                            .share_outlined),
                                                        label: Text(t('미리보기·발송',
                                                            'Preview & share')))
                                                ]),
                                              ]))),
                                TextButton(
                                    onPressed: _busy
                                        ? null
                                        : () => setState(() => _step = 1),
                                    child: Text(t('이전: 업체·기준 변경',
                                        'Back: suppliers & priority'))),
                                TextButton(
                                    onPressed: () => context.push('/purchases'),
                                    child: Text(
                                        t('저장된 요청서 목록', 'Saved requests'))),
                              ],
                            ]))),
                bottomNavigationBar: _step == 2
                    ? null
                    : SafeArea(
                        child: Padding(
                            padding: const EdgeInsets.all(16),
                            child: FilledButton.icon(
                                onPressed: _busy
                                    ? null
                                    : _step == 0
                                        ? () {
                                            if (_selected.isEmpty ||
                                                _selected.length > 100 ||
                                                _selected.any((key) =>
                                                    _lines[key]!.quantity ==
                                                        null ||
                                                    _lines[key]!.quantity! <=
                                                        0 ||
                                                    _lines[key]!
                                                        .unit
                                                        .isEmpty)) {
                                              setState(() => _message = t(
                                                  '구매할 재료 1~100개와 구매 수량·단위를 확인해 주세요.',
                                                  'Choose 1–100 ingredients and check purchase quantities and units.'));
                                              return;
                                            }
                                            setState(() {
                                              _step = 1;
                                              _message = null;
                                            });
                                          }
                                        : _generate,
                                icon: Icon(_step == 0
                                    ? Icons.arrow_forward
                                    : Icons.description_outlined),
                                label: Text(_busy
                                    ? t('비교 중…', 'Comparing…')
                                    : _step == 0
                                        ? t('다음: 업체·기준 선택',
                                            'Next: suppliers & priority')
                                        : t('구매요청서 초안 만들기',
                                            'Create request drafts'))))))));
  }
}

class _CandidatePicker extends ConsumerStatefulWidget {
  const _CandidatePicker({required this.line, required this.initial});
  final SupplierRequestLine line;
  final List<PurchaseCandidate> initial;
  @override
  ConsumerState<_CandidatePicker> createState() => _CandidatePickerState();
}

class _CandidatePickerState extends ConsumerState<_CandidatePicker> {
  late final _query = TextEditingController(text: widget.line.name);
  late final _chosen = {for (final c in widget.initial) c.offer.supplier.id: c};
  List<SupplierOffer> _offers = [];
  bool _busy = false, _loading = true, _more = false;
  String _region = '', _currency = 'KRW';
  String? _error;
  String t(String ko, String en) => catalogText(context, ko, en);
  @override
  void initState() {
    super.initState();
    if (widget.initial.isNotEmpty) {
      _currency = widget.initial.first.offer.supplier.currency;
    }
    _load();
  }

  @override
  void dispose() {
    _query.dispose();
    super.dispose();
  }

  Future<void> _load({bool more = false}) async {
    setState(() => _loading = true);
    try {
      final rows = await ref.read(supplierCatalogRepositoryProvider).search(
          query: _query.text.trim(),
          region: _region,
          offset: more ? _offers.length : 0);
      if (mounted) {
        setState(() {
          _offers = more ? [..._offers, ...rows] : rows;
          _more = rows.length == 30;
          _error = null;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(
            () => _error = t('후보를 불러오지 못했습니다.', 'Could not load candidates.'));
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _toggle(SupplierOffer offer, bool yes) async {
    if (!yes) {
      setState(() => _chosen.remove(offer.supplier.id));
      return;
    }
    if (_chosen.length >= 3 && !_chosen.containsKey(offer.supplier.id)) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(t('이 재료의 후보는 최대 3개 업체입니다.',
              'Choose up to 3 suppliers for this ingredient.'))));
      return;
    }
    var candidate = PurchaseCandidate(offer);
    if (candidate.packs(widget.line) == null) {
      final input = TextEditingController();
      final value = await showDialog<double>(
          context: context,
          builder: (ctx) => AlertDialog(
                  title: Text(t('구매 단위 환산 기준', 'Purchase unit conversion')),
                  content: Column(mainAxisSize: MainAxisSize.min, children: [
                    LocalizedText(
                        '1 ${widget.line.unit} = ? ${offer.product.contentUnit}'),
                    Text(t('이 상품에 적용할 구매 기준을 직접 입력하세요.',
                        'Enter the purchase conversion for this product.')),
                    TextField(
                        controller: input,
                        keyboardType: const TextInputType.numberWithOptions(
                            decimal: true))
                  ]),
                  actions: [
                    TextButton(
                        onPressed: () => Navigator.pop(ctx),
                        child: Text(t('취소', 'Cancel'))),
                    FilledButton(
                        onPressed: () {
                          final n = shoppingInput(input.text);
                          if (n != null && n > 0 && n <= 1e9) {
                            Navigator.pop(ctx, n);
                          }
                        },
                        child: Text(t('적용', 'Apply')))
                  ]));
      input.dispose();
      if (value == null || !mounted) return;
      candidate = PurchaseCandidate(offer, contentUnitsPerPurchaseUnit: value);
    }
    if (candidate.packs(widget.line) == null) {
      setState(() => _error =
          t('수량과 환산 기준을 확인해 주세요.', 'Check quantities and conversion.'));
      return;
    }
    setState(() {
      _chosen[offer.supplier.id] = candidate;
      _error = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final mine = (ref.watch(shoppingSuppliersProvider).valueOrNull ?? [])
        .map((s) => s.catalogSupplierId)
        .toSet();
    return PopScope(
        canPop: !_busy,
        child: Dialog.fullscreen(
            child: Scaffold(
                appBar: AppBar(
                    title: LocalizedText('${widget.line.name} · ${_chosen.length}/3'),
                    leading: IconButton(
                        onPressed: _busy ? null : () => Navigator.pop(context),
                        icon: const Icon(Icons.close))),
                body: ListView(padding: const EdgeInsets.all(20), children: [
                  Text(t('이 재료의 업체 후보를 고릅니다. 같은 업체의 다른 상품을 고르면 기존 상품을 바꿉니다.',
                      'Choose candidates for this ingredient. Choosing another product from the same supplier replaces its previous product.')),
                  LocalizedText(
                      '${shoppingNumber(widget.line.quantity)} ${widget.line.unit}'),
                  const SizedBox(height: 12),
                  TextField(
                      controller: _query,
                      onSubmitted: (_) => _load(),
                      decoration: InputDecoration(
                          labelText: t(
                              '재료·상품 검색어 수정', 'Edit ingredient/product search'),
                          suffixIcon: IconButton(
                              onPressed: _loading ? null : () => _load(),
                              icon: const Icon(Icons.search)))),
                  const SizedBox(height: 12),
                  Wrap(spacing: 12, runSpacing: 12, children: [
                    SizedBox(
                        width: 180,
                        child: DropdownButtonFormField<String>(
                            initialValue: _region,
                            decoration: InputDecoration(
                                labelText: t('배송 지역', 'Delivery region')),
                            items: [
                              DropdownMenuItem(
                                  value: '', child: Text(t('전체', 'All'))),
                              for (final r
                                  in supplierRegions.where((r) => r != '전국'))
                                DropdownMenuItem(
                                    value: r,
                                    child: Text(supplierRegionLabel(
                                        r,
                                        Localizations.localeOf(context)
                                                .languageCode ==
                                            'en')))
                            ],
                            onChanged: _loading
                                ? null
                                : (v) {
                                    setState(() => _region = v!);
                                    _load();
                                  })),
                    SizedBox(
                        width: 130,
                        child: DropdownButtonFormField<String>(
                            initialValue: _currency,
                            decoration: InputDecoration(
                                labelText: t('거래 통화', 'Currency')),
                            items: [
                              for (final c in ['KRW', 'USD'])
                                DropdownMenuItem(value: c, child: Text(c))
                            ],
                            onChanged: _busy
                                ? null
                                : (v) => setState(() => _currency = v!)))
                  ]),
                  const SizedBox(height: 12),
                  if (_chosen.isNotEmpty)
                    Wrap(spacing: 6, children: [
                      for (final entry in _chosen.entries)
                        InputChip(
                            label: Text(entry.value.offer.supplier.name),
                            onDeleted: _busy
                                ? null
                                : () =>
                                    setState(() => _chosen.remove(entry.key)))
                    ]),
                  if (_loading) const LinearProgressIndicator(),
                  if (_error != null) Text(_error!),
                  if (!_loading &&
                      _offers
                          .where((o) => o.supplier.currency == _currency)
                          .isEmpty)
                    Text(t('검색 결과가 없습니다. 검색어·지역을 바꾸거나 업체 등록을 요청해 주세요.',
                        'No results. Change the query or region, or ask the supplier to register.')),
                  if (!_loading &&
                      _offers
                          .where((o) => o.supplier.currency == _currency)
                          .isEmpty)
                    TextButton.icon(
                        onPressed: _busy
                            ? null
                            : () async {
                                final account =
                                    ref.read(activeAccountIdProvider);
                                final supplier =
                                    await showDialog<ShoppingSupplier>(
                                        context: context,
                                        barrierDismissible: false,
                                        builder: (_) =>
                                            const ShoppingAccountGuard(
                                                child: SupplierEditor(
                                                    returnSupplier: true)));
                                if (!context.mounted ||
                                    account !=
                                        ref.read(activeAccountIdProvider) ||
                                    supplier == null) {
                                  return;
                                }
                                await showDialog<void>(
                                    context: context,
                                    barrierDismissible: false,
                                    builder: (_) => ShoppingAccountGuard(
                                        child: SupplierRequestEditor(
                                            suppliers: [supplier],
                                            groups: const [],
                                            initialSupplierId: supplier.id,
                                            initialLines: [widget.line])));
                                if (!mounted) return;
                                ref.invalidate(supplierRequestsProvider);
                              },
                        icon: const Icon(Icons.add),
                        label: Text(t('내 거래처 등록·직접 요청서 작성',
                            'Add my supplier & write a request'))),
                  for (final o
                      in _offers.where((o) => o.supplier.currency == _currency))
                    SupplierOfferCard(
                        offer: o,
                        isMine: mine.contains(o.supplier.id),
                        action: CheckboxListTile(
                            contentPadding: EdgeInsets.zero,
                            value: _chosen[o.supplier.id]?.offer.product.id ==
                                o.product.id,
                            onChanged:
                                _busy ? null : (v) => _toggle(o, v ?? false),
                            title: Text(t(
                                '이 재료의 후보로 선택', 'Choose for this ingredient')),
                            subtitle: LocalizedText(
                                '${t('구매 예상', 'Purchase estimate')}: ${PurchaseCandidate(o).packs(widget.line) ?? t('환산 기준 필요', 'conversion needed')} ${o.product.saleUnit}'))),
                  if (_more)
                    TextButton(
                        onPressed: _loading ? null : () => _load(more: true),
                        child: Text(t('더 보기', 'Load more'))),
                ]),
                bottomNavigationBar: SafeArea(
                    child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: FilledButton(
                            onPressed: _busy || _chosen.isEmpty
                                ? null
                                : () async {
                                    if (_chosen.values
                                            .map((c) =>
                                                c.offer.supplier.currency)
                                            .toSet()
                                            .length !=
                                        1) {
                                      setState(() => _error = t(
                                          '같은 통화의 후보를 선택해 주세요.',
                                          'Choose candidates with the same currency.'));
                                      return;
                                    }
                                    setState(() => _busy = true);
                                    try {
                                      for (final id in _chosen.keys) {
                                        await ref
                                            .read(
                                                supplierCatalogRepositoryProvider)
                                            .selectSupplier(id);
                                      }
                                      ref.invalidate(shoppingSuppliersProvider);
                                      if (context.mounted) {
                                        ScaffoldMessenger.of(context)
                                            .removeCurrentSnackBar();
                                        Navigator.pop(
                                            context, _chosen.values.toList());
                                      }
                                    } catch (_) {
                                      if (mounted) {
                                        setState(() => _error = t(
                                            '내 거래처 등록을 완료하지 못했습니다. 이미 등록된 업체는 유지됩니다. 거래처 한도를 확인하고 다시 시도해 주세요.',
                                            'Could not finish adding suppliers. Already added suppliers remain. Check your supplier limit and retry.'));
                                      }
                                    } finally {
                                      if (mounted) {
                                        setState(() => _busy = false);
                                      }
                                    }
                                  },
                            child: LocalizedText(
                                '${_chosen.length}${t('곳 선택 완료 · 내 거래처에 등록', ' suppliers selected · add to my suppliers')}')))))));
  }
}
