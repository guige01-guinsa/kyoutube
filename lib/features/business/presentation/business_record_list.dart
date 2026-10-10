import '../../../core/localization/localized_text.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../workspace/presentation/workspace_menu.dart';
import '../domain/business_workspace.dart';

/// Presentation only: the caller keeps permission checks, filtering and paging.
class BusinessRecordList extends StatelessWidget {
  const BusinessRecordList(
      {super.key,
      required this.records,
      required this.statusLabel,
      required this.onOpen});
  final List<BusinessRecord> records;
  final String Function(BusinessRecord) statusLabel;
  final ValueChanged<BusinessRecord> onOpen;

  @override
  Widget build(BuildContext context) {
    String tr(String ko, String en) => workspaceText(context, ko, en);
    final theme = Theme.of(context);
    String date(BusinessRecord record) => record.updatedAt == null
        ? '—'
        : DateFormat.yMMMd(Localizations.localeOf(context).languageCode)
            .format(record.updatedAt!.toLocal());
    Widget status(BusinessRecord record) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
            color: theme.colorScheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(8)),
        child: Text(statusLabel(record), style: theme.textTheme.labelMedium));
    Widget cell(Widget child, int flex) => Expanded(
        flex: flex,
        child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8), child: child));
    return LayoutBuilder(builder: (context, constraints) {
      final wide = constraints.maxWidth >= 760 &&
          MediaQuery.textScalerOf(context).scale(1) <= 1.3;
      if (!wide) {
        return Column(key: const Key('business-record-cards'), children: [
          for (final record in records)
            Card(
                margin: const EdgeInsets.only(bottom: 12),
                child: InkWell(
                    onTap: () => onOpen(record),
                    borderRadius: BorderRadius.circular(16),
                    child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(children: [
                                Expanded(
                                    child: Text(record.title,
                                        style: theme.textTheme.titleMedium)),
                                const SizedBox(width: 8),
                                const Icon(Icons.chevron_right)
                              ]),
                              const SizedBox(height: 12),
                              Wrap(
                                  spacing: 10,
                                  runSpacing: 8,
                                  crossAxisAlignment: WrapCrossAlignment.center,
                                  children: [
                                    status(record),
                                    LocalizedText('v${record.revision}',
                                        style: theme.textTheme.bodySmall),
                                    if (record.updatedAt != null)
                                      Text(date(record),
                                          style: theme.textTheme.bodySmall)
                                  ])
                            ]))))
        ]);
      }
      return Card(
          key: const Key('business-record-table'),
          clipBehavior: Clip.antiAlias,
          child: Column(children: [
            ColoredBox(
                color: theme.colorScheme.surfaceContainerLow,
                child: Padding(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 14),
                    child: Row(children: [
                      cell(
                          Text(tr('제목', 'Title'),
                              style: theme.textTheme.labelLarge),
                          4),
                      cell(
                          Text(tr('상태', 'Status'),
                              style: theme.textTheme.labelLarge),
                          2),
                      cell(
                          Text(tr('버전', 'Version'),
                              style: theme.textTheme.labelLarge),
                          1),
                      cell(
                          Text(tr('수정일', 'Updated'),
                              style: theme.textTheme.labelLarge),
                          2),
                      const SizedBox(width: 24)
                    ]))),
            for (final record in records) ...[
              const Divider(height: 1),
              InkWell(
                  onTap: () => onOpen(record),
                  child: Padding(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 16),
                      child: Row(children: [
                        cell(
                            Text(record.title,
                                style: theme.textTheme.titleSmall),
                            4),
                        cell(
                            Align(
                                alignment: Alignment.centerLeft,
                                child: status(record)),
                            2),
                        cell(LocalizedText('v${record.revision}'), 1),
                        cell(
                            Text(date(record),
                                style: theme.textTheme.bodySmall),
                            2),
                        const Icon(Icons.chevron_right)
                      ])))
            ]
          ]));
    });
  }
}

class BusinessWorkflowStrip extends StatelessWidget {
  const BusinessWorkflowStrip({super.key, required this.business});
  final BusinessContext business;
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final steps = [
      if (business.can('recipes.read')) ...[
        ('레시피 개발', 'Recipe development'),
        ('메뉴판 관리', 'Menu management'),
      ],
      if (business.can('purchasing.read')) ('구매·입고', 'Purchasing'),
      if (business.can('finance.read')) ('경영관리', 'Management'),
    ];
    return Wrap(spacing: 8, runSpacing: 8, children: [
      for (final (index, step) in steps.indexed)
        Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
                color: theme.colorScheme.surfaceContainerLow,
                border: Border.all(color: theme.colorScheme.outlineVariant),
                borderRadius: BorderRadius.circular(10)),
            child: LocalizedText(
                '${index + 1}  ${workspaceText(context, step.$1, step.$2)}',
                style: theme.textTheme.labelLarge))
    ]);
  }
}
