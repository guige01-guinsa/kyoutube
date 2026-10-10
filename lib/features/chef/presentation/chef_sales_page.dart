import '../../../core/localization/localized_text.dart';
import '../../guide/presentation/guide_help_button.dart';
import '../data/chef_access.dart';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import '../../../core/localization/chef_localizations.dart';
import '../data/chef_repository.dart';
import '../data/chef_sales_repository.dart';
import '../domain/chef_sales.dart';
import '../../auth/application/auth_providers.dart';
import '../../shopping/presentation/shopping_assistant_dialogs.dart';
import '../../shopping/presentation/record_management.dart';

class ChefSalesPage extends ConsumerStatefulWidget {
  const ChefSalesPage({super.key, this.recipeId});
  final String? recipeId;
  @override
  ConsumerState<ChefSalesPage> createState() => _ChefSalesPageState();
}

class _ChefSalesPageState extends ConsumerState<ChefSalesPage> {
  ChefSalesPeriod _period = ChefSalesPeriod.day;
  DateTime _date = DateTime.now();
  String _currency = 'KRW';
  bool _showVoided = false;
  ChefWorkspace? _workspace;
  ChefSalesTotals? _totals;
  List<ChefSale> _rows = [];
  bool _loading = true,
      _more = false,
      _loadingMore = false,
      _initialized = false;
  String? _error;
  int _loadNumber = 0;
  String t(String key) => chefText(context, key);
  ChefSalesRepository get repository => ref.read(chefSalesRepositoryProvider);
  ChefSalesRange get range => ChefSalesRange.forDate(_date, _period);
  String money(double value) => NumberFormat.currency(
          name: _currency,
          symbol: _currency == 'KRW' ? '₩' : r'US$',
          decimalDigits: _currency == 'KRW' ? 0 : 2)
      .format(value);
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    final account = ref.read(activeAccountIdProvider);
    final number = ++_loadNumber;
    setState(() {
      _loading = true;
      _error = null;
      _totals = null;
      _rows = [];
    });
    try {
      final work = widget.recipeId == null
          ? null
          : await ref.read(chefRepositoryProvider).load(widget.recipeId!);
      if (!mounted ||
          number != _loadNumber ||
          account != ref.read(activeAccountIdProvider)) {
        return;
      }
      if (!_initialized && work != null) _currency = work.document.currency;
      _initialized = true;
      final totals =
          await repository.totals(range, _currency, recipeId: widget.recipeId);
      final rows = await (_showVoided
          ? repository.voidedSales
          : repository.list)(range, _currency, recipeId: widget.recipeId);
      if (!mounted ||
          number != _loadNumber ||
          account != ref.read(activeAccountIdProvider)) {
        return;
      }
      setState(() {
        _workspace = work;
        _totals = totals;
        _rows = rows;
        _more = rows.length == 50;
      });
    } catch (_) {
      if (mounted && number == _loadNumber) {
        setState(() => _error = 'salesError');
      }
    } finally {
      if (mounted && number == _loadNumber) setState(() => _loading = false);
    }
  }

  Future<void> _moreRows() async {
    final account = ref.read(activeAccountIdProvider);
    final number = _loadNumber;
    setState(() => _loadingMore = true);
    try {
      final rows = await (_showVoided
              ? repository.voidedSales
              : repository.list)(range, _currency,
          recipeId: widget.recipeId, beforeId: _rows.last.id);
      if (!mounted ||
          number != _loadNumber ||
          account != ref.read(activeAccountIdProvider)) {
        return;
      }
      setState(() {
        _rows = [..._rows, ...rows];
        _more = rows.length == 50;
      });
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(t('salesError'))));
      }
    } finally {
      if (mounted) setState(() => _loadingMore = false);
    }
  }

  Future<DateTime?> _chooseDate(DateTime initial) => showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100, 12, 31));
  void _move(int direction) {
    final current = range;
    final next = direction > 0
        ? current.until
        : DateTime(current.from.year, current.from.month, current.from.day - 1);
    if (next.isBefore(DateTime(2000)) || next.isAfter(DateTime(2100, 12, 31))) {
      return;
    }
    _date = next;
    _load();
  }

  Future<void> _edit([ChefSale? original]) async {
    final work = _workspace;
    if (original == null &&
        (work?.document.sellingPrice == null || widget.recipeId == null)) {
      return;
    }
    var date = original?.date ?? _date;
    var quantity = original?.quantity ?? 1;
    final price = original?.unitPrice ?? work!.document.sellingPrice!;
    final unitCost = original?.unitCost ?? work!.document.portionCost!;
    final requestKey =
        '${DateTime.now().microsecondsSinceEpoch}-${Random.secure().nextInt(1 << 32)}';
    final form = GlobalKey<FormState>();
    var saving = false;
    var reason = '';
    final account = ref.read(activeAccountIdProvider);
    String? failure;
    final accepted = await showDialog<bool>(
        context: context,
        barrierDismissible: false,
        builder: (ctx) => ShoppingAccountGuard(
            child: StatefulBuilder(
                builder: (ctx, update) => PopScope(
                    canPop: !saving,
                    child: AlertDialog(
                      title:
                          Text(t(original == null ? 'recordSale' : 'editSale')),
                      scrollable: true,
                      content: SizedBox(
                          width: 420,
                          child: Form(
                              key: form,
                              child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  crossAxisAlignment:
                                      CrossAxisAlignment.stretch,
                                  children: [
                                    Text(
                                        original?.title ?? work!.document.title,
                                        style: Theme.of(context)
                                            .textTheme
                                            .titleMedium),
                                    OutlinedButton.icon(
                                        onPressed: saving
                                            ? null
                                            : () async {
                                                final chosen =
                                                    await _chooseDate(date);
                                                if (chosen != null &&
                                                    ctx.mounted) {
                                                  update(() => date = chosen);
                                                }
                                              },
                                        icon: const Icon(
                                            Icons.calendar_today_outlined),
                                        label: Text(chefDate(date))),
                                    TextFormField(
                                        initialValue: quantity.toString(),
                                        enabled: !saving,
                                        decoration: InputDecoration(
                                            labelText: t('saleQuantity')),
                                        keyboardType: TextInputType.number,
                                        validator: (v) {
                                          final n = int.tryParse(v ?? '');
                                          return n == null ||
                                                  n < 1 ||
                                                  n > 100000
                                              ? t('number')
                                              : null;
                                        },
                                        onChanged: (v) => update(() =>
                                            quantity = int.tryParse(v) ?? 0)),
                                    if (original != null)
                                      TextFormField(
                                          decoration: InputDecoration(
                                              labelText: shopText(ctx, '정정 사유',
                                                  'Correction reason')),
                                          enabled: !saving,
                                          maxLength: 300,
                                          onChanged: (v) => reason = v.trim(),
                                          validator: (v) =>
                                              v == null || v.trim().isEmpty
                                                  ? shopText(ctx, '사유를 입력하세요.',
                                                      'Enter a reason.')
                                                  : null),
                                    const SizedBox(height: 16),
                                    LocalizedText(
                                        '${t('sellingPrice')}: ${money(price)}'),
                                    LocalizedText(
                                        '${t('portionCost')}: ${money(unitCost)}'),
                                    LocalizedText(
                                        '${t('revenue')}: ${money(price * quantity)}'),
                                    LocalizedText(
                                        '${t('profit')}: ${money((price - unitCost) * quantity)}'),
                                    const SizedBox(height: 12),
                                    Text(t(original == null
                                        ? 'saleSnapshotHint'
                                        : 'saleEditHint')),
                                    if (failure != null)
                                      Padding(
                                          padding:
                                              const EdgeInsets.only(top: 12),
                                          child: Text(t(failure!),
                                              style: TextStyle(
                                                  color: Theme.of(context)
                                                      .colorScheme
                                                      .error))),
                                  ]))),
                      actions: [
                        TextButton(
                            onPressed:
                                saving ? null : () => Navigator.pop(ctx, false),
                            child: Text(t('cancel'))),
                        FilledButton(
                            onPressed: saving
                                ? null
                                : () async {
                                    if (!form.currentState!.validate() ||
                                        account !=
                                            ref.read(activeAccountIdProvider)) {
                                      return;
                                    }
                                    update(() {
                                      saving = true;
                                      failure = null;
                                    });
                                    try {
                                      if (original == null) {
                                        await repository.record(
                                            widget.recipeId!,
                                            work!.revision,
                                            date,
                                            quantity,
                                            requestKey);
                                      } else {
                                        await repository.correct(
                                            original, date, quantity, reason);
                                      }
                                      if (ctx.mounted) Navigator.pop(ctx, true);
                                    } catch (error) {
                                      if (ctx.mounted) {
                                        update(() {
                                          saving = false;
                                          failure = error.toString().contains(
                                                  'CHEF_REVISION_CONFLICT')
                                              ? 'salesStale'
                                              : 'salesError';
                                        });
                                      }
                                    }
                                  },
                            child: saving
                                ? const SizedBox(
                                    width: 18,
                                    height: 18,
                                    child: CircularProgressIndicator(
                                        strokeWidth: 2))
                                : Text(t('confirm'))),
                      ],
                    )))));
    if (!mounted || account != ref.read(activeAccountIdProvider)) return;
    if (accepted == true) _date = date;
    await _load();
  }

  Future<void> _void(ChefSale sale) async {
    final account = ref.read(activeAccountIdProvider);
    var reason = '';
    final form = GlobalKey<FormState>();
    final accepted = await showDialog<bool>(
        context: context,
        builder: (ctx) => ShoppingAccountGuard(
                child: AlertDialog(
              scrollable: true,
              title: Text(shopText(ctx, sale.voided ? '매출 복원' : '매출 취소',
                  sale.voided ? 'Restore sale' : 'Void sale')),
              content: Form(
                  key: form,
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                    Text(shopText(
                        ctx,
                        '취소하면 집계에서 제외되고 복원하면 다시 포함됩니다. 판매 단가·원가와 정정 이력은 유지되며 재고는 변경하지 않습니다.',
                        'Voided sales are excluded from totals; restoration includes them again. Sale price, cost and history are preserved. Inventory does not change.')),
                    TextFormField(
                        maxLength: 300,
                        onChanged: (v) => reason = v.trim(),
                        decoration: InputDecoration(
                            labelText: shopText(ctx, '처리 사유', 'Reason')),
                        validator: (v) => v == null || v.trim().isEmpty
                            ? shopText(ctx, '사유를 입력하세요.', 'Enter a reason.')
                            : null),
                  ])),
              actions: [
                TextButton(
                    onPressed: () => Navigator.pop(ctx),
                    child: Text(t('cancel'))),
                FilledButton(
                    onPressed: () {
                      if (form.currentState!.validate()) {
                        Navigator.pop(ctx, true);
                      }
                    },
                    child: Text(t('confirm')))
              ],
            )));
    if (accepted != true ||
        !mounted ||
        account != ref.read(activeAccountIdProvider)) {
      return;
    }
    await repository.setVoided(sale, !sale.voided, reason);
    if (mounted && account == ref.read(activeAccountIdProvider)) await _load();
  }

  Future<void> _history(ChefSale sale) async {
    final pending = repository.history(sale.id);
    await showDialog<void>(
        context: context,
        builder: (ctx) => ShoppingAccountGuard(
                child: AlertDialog(
              title: Text(shopText(
                  ctx, '매출 처리 이력 (최근 100건)', 'Sale history (latest 100)')),
              content: SizedBox(
                  width: 560,
                  height: 400,
                  child: FutureBuilder<List<Map<String, dynamic>>>(
                      future: pending,
                      builder: (ctx, snapshot) {
                        if (snapshot.hasError) return Text(t('salesError'));
                        if (!snapshot.hasData) {
                          return const Center(
                              child: CircularProgressIndicator());
                        }
                        return ListView(children: [
                          for (final e in snapshot.data!)
                            ListTile(
                                title: Text(switch (e['action']) {
                                  'created' => shopText(ctx, '등록', 'Created'),
                                  'corrected' =>
                                    shopText(ctx, '정정', 'Corrected'),
                                  'voided' => shopText(ctx, '취소', 'Voided'),
                                  'restored' => shopText(ctx, '복원', 'Restored'),
                                  _ => shopText(ctx, '기준 기록', 'Baseline'),
                                }),
                                subtitle: Text([
                                  e['recorded_at'],
                                  e['reason'],
                                  if (e['before_data'] != null)
                                    '${e['before_data']['sale_date']} · ${e['before_data']['quantity']}',
                                  if (e['after_data'] != null)
                                    '→ ${e['after_data']['sale_date']} · ${e['after_data']['quantity']}',
                                ]
                                    .where((v) => v != null && v != '')
                                    .join('\n')))
                        ]);
                      })),
              actions: [
                TextButton(
                    onPressed: () => Navigator.pop(ctx),
                    child: Text(shopText(ctx, '닫기', 'Close')))
              ],
            )));
  }

  Widget _metric(String label, String value) => Container(
      padding: const EdgeInsets.all(18),
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
          color: const Color(0xffe8f0e8),
          borderRadius: BorderRadius.circular(18)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text(t(label)),
        const SizedBox(height: 6),
        Text(value, style: Theme.of(context).textTheme.headlineSmall),
      ]));
  @override
  Widget build(BuildContext context) {
    ref.listen(activeAccountIdProvider, (previous, next) {
      if (previous != next) _load();
    });
    final access = ref.watch(chefPaidAccessProvider);
    if (access.valueOrNull != true) {
      return Scaffold(
          appBar: AppBar(title: Text(t('sales'))),
          body: access.isLoading
              ? const Center(child: CircularProgressIndicator())
              : const Center(child: ChefPaidNotice()));
    }

    final current = range;
    return Scaffold(
        appBar: AppBar(title: Text(t('sales')), actions: [
          GuideHelpButton(lesson: 'pro-sales', enabled: !_loading),
          IconButton(
              tooltip: t('reload'),
              onPressed: _loading ? null : _load,
              icon: const Icon(Icons.refresh)),
        ]),
        body: Center(
            child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 800),
                child: ListView(padding: const EdgeInsets.all(20), children: [
                  if (_workspace != null)
                    Text(_workspace!.document.title,
                        style: Theme.of(context).textTheme.headlineSmall),
                  Wrap(spacing: 8, children: [
                    for (final period in ChefSalesPeriod.values)
                      ChoiceChip(
                          label: Text(t(period.name)),
                          selected: _period == period,
                          onSelected: _loading
                              ? null
                              : (_) {
                                  _period = period;
                                  _load();
                                }),
                  ]),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                      initialValue: _currency,
                      key: ValueKey(_currency),
                      decoration: InputDecoration(labelText: t('currency')),
                      items: ['KRW', 'USD']
                          .map(
                              (c) => DropdownMenuItem(value: c, child: Text(c)))
                          .toList(),
                      onChanged: _loading
                          ? null
                          : (v) {
                              if (v != null) {
                                _currency = v;
                                _load();
                              }
                            }),
                  const SizedBox(height: 12),
                  Wrap(
                      alignment: WrapAlignment.center,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        IconButton(
                            tooltip: t('previousPeriod'),
                            onPressed: _loading ? null : () => _move(-1),
                            icon: const Icon(Icons.chevron_left)),
                        TextButton(
                            onPressed: _loading
                                ? null
                                : () async {
                                    final date = await _chooseDate(_date);
                                    if (date != null && mounted) {
                                      _date = date;
                                      _load();
                                    }
                                  },
                            child: LocalizedText(
                                '${chefDate(current.from)} – ${chefDate(DateTime(current.until.year, current.until.month, current.until.day - 1))}')),
                        IconButton(
                            tooltip: t('nextPeriod'),
                            onPressed: _loading ? null : () => _move(1),
                            icon: const Icon(Icons.chevron_right)),
                      ]),
                  if (_loading)
                    const Center(
                        child: Padding(
                            padding: EdgeInsets.all(24),
                            child: CircularProgressIndicator()))
                  else if (_error != null)
                    Text(t(_error!))
                  else if (_totals != null) ...[
                    _metric('revenue', money(_totals!.revenue)),
                    _metric('profit', money(_totals!.profit)),
                    LocalizedText('${t('saleQuantity')}: ${_totals!.quantity}'),
                    LocalizedText('${t('salesCost')}: ${money(_totals!.cost)}'),
                    const SizedBox(height: 12),
                    Text(t('salesHint'),
                        style: Theme.of(context).textTheme.bodySmall),
                    const SizedBox(height: 20),
                    if (widget.recipeId != null) ...[
                      if (_workspace?.document.sellingPrice == null)
                        Text(t('salesCostRequired')),
                      if (_workspace != null &&
                          _workspace!.document.currency != _currency)
                        Text(t('salesCurrencyHint')),
                      FilledButton.icon(
                          onPressed:
                              _workspace?.document.sellingPrice == null ||
                                      _workspace!.document.currency != _currency
                                  ? null
                                  : () => _edit(),
                          icon: const Icon(Icons.add),
                          label: Text(t('recordSale'))),
                      TextButton(
                          onPressed: () => context.push('/chef-sales'),
                          child: Text(t('allSales'))),
                    ],
                    SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        title: Text(shopText(
                            context, '취소한 매출 보기', 'Show voided sales')),
                        value: _showVoided,
                        onChanged: _loading
                            ? null
                            : (v) {
                                _showVoided = v;
                                _load();
                              }),
                    if (_rows.isEmpty)
                      Padding(
                          padding: const EdgeInsets.all(20),
                          child: Text(t('noSales'))),
                    for (final sale in _rows)
                      Card(
                          child: Padding(
                              padding: const EdgeInsets.all(16),
                              child: Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.stretch,
                                  children: [
                                    Text(sale.title,
                                        style: Theme.of(context)
                                            .textTheme
                                            .titleMedium),
                                    LocalizedText(
                                        '${chefDate(sale.date)} · ${sale.quantity} × ${money(sale.unitPrice)}'),
                                    LocalizedText(
                                        '${t('revenue')}: ${money(sale.revenue)}'),
                                    LocalizedText(
                                        '${t('profit')}: ${money(sale.profit)}'),
                                    Wrap(children: [
                                      TextButton.icon(
                                          onPressed: sale.voided
                                              ? null
                                              : () => _edit(sale),
                                          icon: const Icon(Icons.edit_outlined),
                                          label: Text(t('editSale'))),
                                      RecordManagementMenu(actions: [
                                        RecordManagementAction(
                                            'erase',
                                            shopText(context, '영구 삭제',
                                                'Delete permanently'),
                                            Icons.delete_forever, () async {
                                          if (await manageOwnerRecord(
                                                      context, ref,
                                                      kind: 'sale',
                                                      id: sale.id.toString()) !=
                                                  null &&
                                              mounted) {
                                            await _load();
                                          }
                                        }),
                                        RecordManagementAction(
                                            'history',
                                            shopText(
                                                context, '처리 이력', 'History'),
                                            Icons.history,
                                            () => _history(sale)),
                                        RecordManagementAction(
                                            'void',
                                            shopText(
                                                context,
                                                sale.voided ? '매출 복원' : '매출 취소',
                                                sale.voided
                                                    ? 'Restore sale'
                                                    : 'Void sale'),
                                            sale.voided
                                                ? Icons.restore
                                                : Icons.cancel_outlined,
                                            () => _void(sale)),
                                      ]),
                                    ]),
                                  ]))),
                    if (_more)
                      TextButton(
                          onPressed: _loadingMore ? null : _moreRows,
                          child: Text(t('salesMore'))),
                  ],
                ]))));
  }
}
