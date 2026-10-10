import '../../../core/localization/localized_text.dart';
import 'package:flutter/material.dart';
import 'shopping_assistant_dialogs.dart';

class PurchaseProgress extends StatelessWidget {
  const PurchaseProgress({super.key, required this.step});
  final int step;
  @override
  Widget build(BuildContext context) {
    final labels = [
      shopText(context, '재료 선택', 'Ingredients'),
      shopText(context, '업체·기준', 'Suppliers & priority'),
      shopText(context, '요청서 검토', 'Review request'),
      shopText(context, '저장·보내기', 'Save & share'),
    ];
    return Padding(
        padding: const EdgeInsets.only(bottom: 20),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          LocalizedText('${step + 1} / 4 · ${labels[step]}',
              style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 10),
          LinearProgressIndicator(
              value: (step + 1) / 4,
              minHeight: 4,
              borderRadius: BorderRadius.circular(4)),
        ]));
  }
}
