import '../../../core/localization/localized_text.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../auth/application/auth_providers.dart';
import '../data/shopping_assistant_repository.dart';
import '../domain/shopping_assistant.dart';
import 'shopping_assistant_dialogs.dart';

class ShoppingCostImportButton extends ConsumerWidget {
  const ShoppingCostImportButton(
      {super.key,
      required this.ingredientName,
      required this.currency,
      required this.onSelected});
  final String ingredientName, currency;
  final ValueChanged<ShoppingPurchaseRecord> onSelected;
  @override
  Widget build(BuildContext context, WidgetRef ref) => Align(
      alignment: Alignment.centerLeft,
      child: TextButton.icon(
          icon: const Icon(Icons.receipt_long_outlined, size: 18),
          label: Text(
              shopText(context, '장보기 구매 단가 불러오기', 'Import a shopping cost')),
          onPressed: () async {
            final account = ref.read(activeAccountIdProvider);
            ref.invalidate(shoppingRecordsProvider(ingredientName));
            final selected = await showDialog<ShoppingPurchaseRecord>(
                context: context,
                builder: (ctx) => ShoppingAccountGuard(
                        child: AlertDialog(
                            scrollable: true,
                            title: Text(shopText(
                                ctx, '구매 기록 선택', 'Choose a purchase record')),
                            content: SizedBox(
                                width: 420,
                                child: Consumer(
                                    builder: (ctx, ref, _) => ref
                                        .watch(shoppingRecordsProvider(
                                            ingredientName))
                                        .when(
                                            loading: () => const Center(
                                                child:
                                                    CircularProgressIndicator()),
                                            error: (_, __) => TextButton(
                                                onPressed: () => ref.invalidate(
                                                    shoppingRecordsProvider(
                                                        ingredientName)),
                                                child: Text(shopText(
                                                    ctx,
                                                    '불러오지 못했습니다. 다시 시도',
                                                    'Could not load. Retry'))),
                                            data: (rows) {
                                              final records = rows
                                                  .where((r) =>
                                                      r.quantity > 0 &&
                                                      r.amount != null &&
                                                      r.currency == currency)
                                                  .toList();
                                              return Column(
                                                  mainAxisSize:
                                                      MainAxisSize.min,
                                                  children: [
                                                    Text(shopText(
                                                        ctx,
                                                        '같은 재료명과 통화($currency)의 기록입니다. 선택 후 단위와 환산 기준을 확인하세요.',
                                                        'Records for this ingredient in $currency. Check the units and conversion after selecting.')),
                                                    if (records.isEmpty)
                                                      Padding(
                                                          padding:
                                                              const EdgeInsets
                                                                  .all(12),
                                                          child: Text(shopText(
                                                              ctx,
                                                              '불러올 구매 기록이 없습니다.',
                                                              'No matching purchase records.'))),
                                                    for (final record
                                                        in records)
                                                      ListTile(
                                                          title: LocalizedText(
                                                              '$currency ${shoppingNumber(record.amount)} / ${shoppingNumber(record.quantity)} ${shopUnit(ctx, record.unit)}'),
                                                          subtitle: LocalizedText(
                                                              '${record.createdAt.toLocal().toString().substring(0, 10)} ${record.productName}'),
                                                          onTap: () =>
                                                              Navigator.pop(
                                                                  ctx, record)),
                                                  ]);
                                            }))),
                            actions: [
                          TextButton(
                              onPressed: () => Navigator.pop(ctx),
                              child: Text(shopText(ctx, '닫기', 'Close')))
                        ])));
            if (context.mounted &&
                selected != null &&
                ref.read(activeAccountIdProvider) == account) {
              onSelected(selected);
            }
          }));
}
