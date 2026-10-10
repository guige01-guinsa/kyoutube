import 'package:flutter/material.dart';

import '../../../../core/localization/localized_text.dart';
import '../../../../core/theme/app_theme.dart';

/// Equal priority, stable touch targets, and no overlap with recipe content.
class RecipeWorkActions extends StatelessWidget {
  const RecipeWorkActions(
      {super.key, required this.onChef, required this.onShopping});
  final VoidCallback onChef;
  final VoidCallback onShopping;

  @override
  Widget build(BuildContext context) => LayoutBuilder(builder: (context, size) {
        final stacked = size.maxWidth < 300 ||
            MediaQuery.textScalerOf(context).scale(1) > 1.3;
        final width = stacked ? size.maxWidth : (size.maxWidth - 12) / 2;
        final textStyle = Theme.of(context).textTheme.labelLarge!;
        // Size both cards from the longer translated label, including large text.
        var height = 48.0;
        for (final label in ['전문 도구', '장보기 준비']) {
          final painter = TextPainter(
            text: TextSpan(text: context.tr(label), style: textStyle),
            textDirection: Directionality.of(context),
            textScaler: MediaQuery.textScalerOf(context),
            locale: Localizations.localeOf(context),
          )..layout(maxWidth: (width - 60).clamp(1, double.infinity));
          final requiredHeight =
              painter.height + 20; // Compact inline icon and label.
          if (requiredHeight > height) height = requiredHeight;
          painter.dispose();
        }
        Widget action(
                String key, String label, IconData icon, VoidCallback onTap) =>
            SizedBox(
              width: width,
              child: FilledButton.tonal(
                key: ValueKey(key),
                onPressed: onTap,
                style: FilledButton.styleFrom(
                  backgroundColor: ScoutStyle.mint,
                  foregroundColor: ScoutStyle.forest,
                  minimumSize: Size(0, height),
                  textStyle: textStyle,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                    side: const BorderSide(color: ScoutStyle.line),
                  ),
                ),
                child:
                    Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                  Icon(icon, size: 22),
                  const SizedBox(width: 8),
                  Flexible(
                      child: LocalizedText(label, textAlign: TextAlign.center)),
                ]),
              ),
            );
        return Wrap(spacing: 12, runSpacing: 8, children: [
          action('recipe-chef-action', '전문 도구', Icons.balance_outlined, onChef),
          action('recipe-shopping-action', '장보기 준비',
              Icons.shopping_cart_outlined, onShopping),
        ]);
      });
}
