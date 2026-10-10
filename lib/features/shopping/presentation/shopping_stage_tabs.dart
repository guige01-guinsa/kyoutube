import 'package:flutter/material.dart';
import '../domain/shopping_navigation.dart';
import 'shopping_assistant_dialogs.dart' show shopText;

class ShoppingStageTabs extends StatelessWidget {
  const ShoppingStageTabs(
      {super.key, required this.stage, required this.onChanged});
  final ShoppingStage stage;
  final ValueChanged<ShoppingStage> onChanged;
  @override
  Widget build(BuildContext context) =>
      Wrap(spacing: 8, runSpacing: 6, children: [
        for (final value in ShoppingStage.values)
          ChoiceChip(
              key: ValueKey('shopping-stage-${value.name}'),
              label: Text(switch (value) {
                ShoppingStage.prepare => shopText(context, '구매 준비', 'Prepare'),
                ShoppingStage.active =>
                  shopText(context, '진행 중', 'In progress'),
                ShoppingStage.records => shopText(context, '구매 기록', 'Records'),
              }),
              selected: stage == value,
              onSelected: (_) => onChanged(value))
      ]);
}
