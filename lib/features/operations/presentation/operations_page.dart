import '../../../core/format/user_number.dart';
import '../../../core/localization/localized_text.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:go_router/go_router.dart';
import '../../../core/router/app_router.dart';
import '../../../core/localization/app_localizations.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/scout_page.dart';
import '../data/operations_repository.dart';
import '../domain/operations_overview.dart';
import 'growth_summary_card.dart';
import 'integration_readiness_card.dart';

String _label(BuildContext context, String key) =>
    AppLocalizations.of(context).bilingual(opsCopy[key]!.ko,opsCopy[key]!.en);

class OperationsPage extends ConsumerStatefulWidget {
  const OperationsPage({super.key});
  @override
  ConsumerState<OperationsPage> createState() => _OperationsPageState();
}

class _OperationsPageState extends ConsumerState<OperationsPage> {
  int _days = 7;
  @override
  Widget build(BuildContext context) {
    final state = ref.watch(operationsOverviewProvider(_days));
    return Scaffold(
        appBar: AppBar(title: Text(_label(context, 'title')), actions: [
          IconButton(
              tooltip: AppLocalizations.of(context).isEnglish
                  ? 'Operations inbox'
                  : '운영 알림함',
              onPressed: () => context.push(AppRoutes.operationsInbox),
              icon: const Icon(Icons.notifications_outlined)),
          IconButton(
              tooltip: _label(context, 'retry'),
              onPressed: () =>
                  ref.invalidate(operationsOverviewProvider(_days)),
              icon: const Icon(Icons.refresh)),
        ]),
        body: Align(
            alignment: Alignment.topCenter,
            child: ConstrainedBox(
              constraints:
                  const BoxConstraints(maxWidth: ScoutStyle.contentWidth),
              child: state.when(
                loading: () => const Center(child: CircularProgressIndicator()),
                error: (_, __) => Center(
                    child: Padding(
                        padding: const EdgeInsets.all(24),
                        child:
                            Column(mainAxisSize: MainAxisSize.min, children: [
                          Text(_label(context, 'unavailable')),
                          const SizedBox(height: 12),
                          FilledButton(
                              onPressed: () => ref.invalidate(
                                  operationsOverviewProvider(_days)),
                              child: Text(_label(context, 'retry'))),
                        ]))),
                data: (data) => RefreshIndicator(
                    onRefresh: () async {
                      ref.invalidate(operationsOverviewProvider(_days));
                      await ref.read(operationsOverviewProvider(_days).future);
                    },
                    child: ListView(
                        padding: const EdgeInsets.all(20),
                        physics: const AlwaysScrollableScrollPhysics(),
                        children: [
                          ScoutPageHeading(
                            title: _label(context, 'title'),
                            subtitle: _label(context, 'intro'),
                            icon: Icons.monitor_heart_outlined,
                            trailing: OutlinedButton.icon(
                              onPressed: () =>
                                  context.push(AppRoutes.operationsInbox),
                              icon: const Icon(Icons.notifications_outlined),
                              label: LocalizedText(AppLocalizations.of(context).isEnglish
                                  ? 'Operations inbox'
                                  : '운영 알림함'),
                            ),
                          ),
                          const SizedBox(height: 24),
                          const GrowthSummaryCard(),
                          const IntegrationReadinessCard(),
                          const SizedBox(height: 12),
                          Wrap(spacing: 8, children: [
                            for (final days in [1, 7, 30])
                              ChoiceChip(
                                label: LocalizedText('$days ${_label(context, 'days')}'),
                                selected: days == _days,
                                onSelected: (_) => setState(() => _days = days),
                              )
                          ]),
                          const SizedBox(height: 16),
                          if (data.count('total') == 0)
                            _notice(context, _label(context, 'empty')),
                          Wrap(spacing: 12, runSpacing: 12, children: [
                            _metric(
                                context, 'requests', '${data.count('total')}'),
                            _metric(
                                context, 'failures', '${data.count('failed')}'),
                            _metric(context, 'rejected',
                                '${data.count('rejected')}'),
                            _metric(context, 'client',
                                '${data.count('client_errors')}'),
                            _metric(
                                context,
                                'success',
                                data.aiSuccessRate == null
                                    ? '—'
                                    : '${data.aiSuccessRate!.toStringAsFixed(1)}%'),
                            _metric(
                                context,
                                'latency',
                                data.aiP95Seconds == null
                                    ? '—'
                                    : '${data.aiP95Seconds!.toStringAsFixed(1)} s'),
                          ]),
                          const SizedBox(height: 12),
                          Text(_label(context, 'latencyNote'),
                              style: Theme.of(context).textTheme.bodySmall),
                          Text(_label(context, 'coverage'),
                              style: Theme.of(context).textTheme.bodySmall),
                          if (data.alerts.isNotEmpty) ...[
                            _heading(context, 'alerts'),
                            for (final alert in data.alerts)
                              _notice(context, _label(context, alert)),
                          ],
                          _heading(context, 'breakdown'),
                          if (data.failures.isEmpty)
                            Text(_label(context, 'noFailures')),
                          for (final row in data.failures)
                            Card(
                                child: ListTile(
                              title: LocalizedText('${row['source']} · ${row['code']}'),
                              subtitle: LocalizedText('${row['kind']}'),
                              trailing: LocalizedText('${row['count']}'),
                            )),
                          _heading(context, 'usage'),
                          Wrap(spacing: 12, runSpacing: 12, children: [
                            _metric(context, 'input',
                                '${data.usageCount('input_tokens')}'),
                            _metric(context, 'output',
                                '${data.usageCount('output_tokens')}'),
                            _metric(context, 'unknownUsage',
                                '${data.usageCount('unknown_usage')}'),
                          ]),
                          const SizedBox(height: 12),
                          Text(_label(context, 'usageNote'),
                              style: Theme.of(context).textTheme.bodySmall),
                          _heading(context, 'costs'),
                          LocalizedText('${data.usage['month']} · UTC'),
                          if (data.costs?['updated_at'] != null)
                            LocalizedText(
                                '${_label(context, 'asOf')}: ${data.costs!['updated_at']}',
                                style: Theme.of(context).textTheme.bodySmall),
                          const SizedBox(height: 12),
                          _metric(
                              context,
                              'total',
                              data.totalCost == null
                                  ? _label(context, 'unknown')
                                  : '\$${data.totalCost!.toStringAsFixed(2)}'),
                          if (data.totalCost != null)
                            _metric(context, 'remaining',
                                '\$${((data.costs!['budget_usd'] as num) - data.totalCost!).toStringAsFixed(2)}'),
                          const SizedBox(height: 12),
                          Text(_label(context, 'costNote')),
                          _CostForm(
                              key: ValueKey(
                                  '${data.usage['month']}-${data.costs?['updated_at']}'),
                              data: data,
                              onSaved: () => ref.invalidate(
                                  operationsOverviewProvider(_days))),
                          const SizedBox(height: 20),
                          LocalizedText(
                              '${_label(context, 'asOf')}: ${DateFormat('yyyy-MM-dd HH:mm').format(data.generatedAt.toLocal())}',
                              style: Theme.of(context).textTheme.bodySmall),
                        ])),
              ),
            )));
  }
}

Widget _heading(BuildContext context, String key) => Padding(
    padding: const EdgeInsets.only(top: 28, bottom: 12),
    child: Text(_label(context, key),
        style: Theme.of(context).textTheme.titleLarge));
Widget _notice(BuildContext context, String text) => Container(
    margin: const EdgeInsets.only(bottom: 12),
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
        color: ScoutStyle.peach.withValues(alpha: .4),
        borderRadius: BorderRadius.circular(14)),
    child: Text(text));
Widget _metric(BuildContext context, String key, String value) =>
    ConstrainedBox(
        constraints: const BoxConstraints(minWidth: 145),
        child: Card(
            margin: EdgeInsets.zero,
            child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(_label(context, key),
                          style: Theme.of(context).textTheme.bodySmall),
                      const SizedBox(height: 6),
                      Text(value,
                          style: Theme.of(context).textTheme.titleLarge),
                    ]))));

class _CostForm extends ConsumerStatefulWidget {
  const _CostForm({super.key, required this.data, required this.onSaved});
  final OperationsOverview data;
  final VoidCallback onSaved;
  @override
  ConsumerState<_CostForm> createState() => _CostFormState();
}

class _CostFormState extends ConsumerState<_CostForm> {
  late final _ai = TextEditingController(
      text: widget.data.costs?['openai_usd']?.toString() ?? '');
  late final _other = TextEditingController(
      text: widget.data.costs?['other_usd']?.toString() ?? '');
  late final _budget = TextEditingController(
      text: widget.data.costs?['budget_usd']?.toString() ?? '700');
  bool _saving = false;
  String? _error;
  @override
  void dispose() {
    _ai.dispose();
    _other.dispose();
    _budget.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    double? parse(TextEditingController c) => parseUserNumber(c.text.trim());
    final ai = parse(_ai), other = parse(_other), budget = parse(_budget);
    bool invalid(TextEditingController c, double? v) =>
        c.text.trim().isNotEmpty &&
        (v == null || !v.isFinite || v < 0 || v > 9999999999);
    if (invalid(_ai, ai) ||
        invalid(_other, other) ||
        invalid(_budget, budget) ||
        budget == null ||
        budget <= 0) {
      setState(() => _error = 'invalid');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await ref.read(operationsRepositoryProvider).saveCosts(
          month: widget.data.usage['month'] as String,
          openai: ai,
          other: other,
          budget: budget);
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(_label(context, 'saved'))));
      widget.onSaved();
    } catch (_) {
      if (mounted) setState(() => _error = 'saveFailed');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) =>
      Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        for (final entry in [
          ('aiCost', _ai),
          ('otherCost', _other),
          ('budget', _budget)
        ])
          Padding(
              padding: const EdgeInsets.only(top: 12),
              child: TextField(
                  controller: entry.$2,
                  enabled: !_saving,
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  decoration:
                      InputDecoration(labelText: _label(context, entry.$1)))),
        if (_error != null)
          Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Text(_label(context, _error!))),
        const SizedBox(height: 12),
        FilledButton(
            onPressed: _saving ? null : _save,
            child: Text(_label(context, 'save'))),
      ]);
}
