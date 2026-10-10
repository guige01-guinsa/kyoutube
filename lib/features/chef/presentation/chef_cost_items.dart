import 'package:flutter/material.dart';
import '../../../core/localization/chef_localizations.dart';
import '../domain/chef_recipe.dart';

class ChefCostItems extends StatelessWidget {
  const ChefCostItems(
      {super.key,
      required this.document,
      required this.money,
      required this.onItemsChanged,
      required this.onLegacyChanged});
  final ChefRecipe document;
  final String Function(double?) money;
  final ValueChanged<List<ChefCostItem>> onItemsChanged;
  final ValueChanged<double> onLegacyChanged;

  Future<void> _edit(BuildContext context,
      {ChefCostItem? original, bool legacy = false}) async {
    String t(String key) => chefText(context, key);
    if (!legacy && original == null && document.costItems.length >= 100) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(t('costLimit'))));
      return;
    }
    var name = legacy ? t('legacyCost') : original?.name ?? '';
    double? amount = legacy ? document.extraCost : original?.amount;
    var nameEpoch = 0;
    final form = GlobalKey<FormState>();
    final accepted = await showDialog<bool>(
        context: context,
        builder: (ctx) => StatefulBuilder(
            builder: (ctx, update) => AlertDialog(
                  title: Text(
                      t(original == null && !legacy ? 'addCost' : 'editCost')),
                  scrollable: true,
                  content: SizedBox(
                      width: 400,
                      child: Form(
                          key: form,
                          child: Column(
                              mainAxisSize: MainAxisSize.min,
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                if (!legacy) ...[
                                  Wrap(spacing: 6, children: [
                                    for (final preset in [
                                      'labor',
                                      'packaging',
                                      'utilities',
                                      'delivery'
                                    ])
                                      ActionChip(
                                          label: Text(t(preset)),
                                          onPressed: () => update(() {
                                                name = t(preset);
                                                nameEpoch++;
                                              })),
                                  ]),
                                  const SizedBox(height: 12),
                                  TextFormField(
                                      key: ValueKey(nameEpoch),
                                      initialValue: name,
                                      maxLength: 80,
                                      decoration: InputDecoration(
                                          labelText: t('costName')),
                                      validator: (v) =>
                                          v == null || v.trim().isEmpty
                                              ? t('required')
                                              : null,
                                      onChanged: (v) => name = v.trim()),
                                ] else
                                  Text(name),
                                const SizedBox(height: 12),
                                TextFormField(
                                    initialValue: amount == null
                                        ? ''
                                        : chefFormat(amount),
                                    decoration: InputDecoration(
                                        labelText: t('costAmount'),
                                        suffixText: document.currency),
                                    keyboardType:
                                        const TextInputType.numberWithOptions(
                                            decimal: true),
                                    validator: (v) {
                                      final n = chefInputNumber(v ?? '');
                                      if (n == null ||
                                          !n.isFinite ||
                                          n < 0 ||
                                          n > 1e12) {
                                        return t('number');
                                      }
                                      final total = document.totalExtraCost -
                                          (legacy
                                              ? document.extraCost
                                              : original?.amount ?? 0) +
                                          n;
                                      return total > 1e12
                                          ? t('costTotalLimit')
                                          : null;
                                    },
                                    onChanged: (v) =>
                                        amount = chefInputNumber(v)),
                                const SizedBox(height: 12),
                                Text(t('extraHint'),
                                    style:
                                        Theme.of(context).textTheme.bodySmall),
                              ]))),
                  actions: [
                    TextButton(
                        onPressed: () => Navigator.pop(ctx, false),
                        child: Text(t('cancel'))),
                    FilledButton(
                        onPressed: () {
                          if (form.currentState!.validate()) {
                            Navigator.pop(ctx, true);
                          }
                        },
                        child: Text(t('confirm'))),
                  ],
                )));
    if (accepted != true || !context.mounted) return;
    if (legacy) {
      onLegacyChanged(amount!);
    } else {
      final item = ChefCostItem(
          id: original?.id ?? DateTime.now().microsecondsSinceEpoch.toString(),
          name: name,
          amount: amount!);
      onItemsChanged(original == null
          ? [...document.costItems, item]
          : document.costItems
              .map((old) => old.id == item.id ? item : old)
              .toList());
    }
  }

  Future<void> _remove(BuildContext context, ChefCostItem? item) async {
    String t(String key) => chefText(context, key);
    final accepted = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
                title: Text(item?.name ?? t('legacyCost')),
                content: Text(t('deleteCostConfirm')),
                actions: [
                  TextButton(
                      onPressed: () => Navigator.pop(ctx, false),
                      child: Text(t('cancel'))),
                  FilledButton(
                      onPressed: () => Navigator.pop(ctx, true),
                      child: Text(t('removeCost'))),
                ]));
    if (accepted != true || !context.mounted) return;
    if (item == null) {
      onLegacyChanged(0);
    } else {
      onItemsChanged(
          document.costItems.where((old) => old.id != item.id).toList());
    }
  }

  @override
  Widget build(BuildContext context) {
    String t(String key) => chefText(context, key);
    Widget row(String name, double amount, ChefCostItem? item) => Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
            border: Border.all(color: const Color(0xffdce5dd)),
            borderRadius: BorderRadius.circular(16)),
        child:
            Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text(name, style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 6),
          Text(money(amount), style: Theme.of(context).textTheme.titleLarge),
          Text(t('costAmount'), style: Theme.of(context).textTheme.bodySmall),
          Wrap(spacing: 8, children: [
            TextButton.icon(
                onPressed: () =>
                    _edit(context, original: item, legacy: item == null),
                icon: const Icon(Icons.edit_outlined),
                label: Text(t('editCost'))),
            IconButton(
                tooltip: t('removeCost'),
                icon: const Icon(Icons.delete_outline),
                onPressed: () => _remove(context, item)),
          ]),
        ]));
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      if (document.extraCost > 0)
        row(t('legacyCost'), document.extraCost, null),
      for (final item in document.costItems) row(item.name, item.amount, item),
      if (document.extraCost == 0 && document.costItems.isEmpty)
        Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Text(t('costEmpty'))),
      OutlinedButton.icon(
          onPressed: () => _edit(context),
          icon: const Icon(Icons.add),
          label: Text(t('addCost'))),
      const SizedBox(height: 16),
      Text(t('costTotal'), style: Theme.of(context).textTheme.labelLarge),
      Text(money(document.totalExtraCost),
          style: Theme.of(context).textTheme.headlineSmall),
    ]);
  }
}
