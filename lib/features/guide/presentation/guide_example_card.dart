import '../../../core/localization/localized_text.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../../core/localization/app_localizations.dart';
import '../../../core/theme/app_theme.dart';
import '../domain/guide_curriculum.dart';
import '../domain/guide_example.dart';

class GuideExampleCard extends StatefulWidget {
  const GuideExampleCard({super.key, required this.practice, this.onPracticed});
  final GuidePractice practice;
  final VoidCallback? onPracticed;
  @override
  State<GuideExampleCard> createState() => _GuideExampleCardState();
}

class _GuideExampleCardState extends State<GuideExampleCard> {
  int _servings = 4;
  double _yield = 80, _markup = 50;
  String label(String key) {
    final copy = guideLabels[key]!;
    return AppLocalizations.of(context).bilingual(copy.ko, copy.en);
  }

  String amount(num value) => NumberFormat('#,##0.#', 'en').format(value);
  Widget metric(String title, String value, String key) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(title, style: Theme.of(context).textTheme.bodySmall),
        const SizedBox(height: 4),
        Text(value,
            key: Key(key), style: Theme.of(context).textTheme.headlineSmall),
      ]));
  @override
  Widget build(BuildContext context) {
    final example = GuideExample(
        servings: _servings, yieldPercent: _yield, markup: _markup);
    return Container(
        key: const Key('guide-example'),
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
            color: ScoutStyle.mint, borderRadius: BorderRadius.circular(22)),
        child:
            Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text(label('example'), style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 8),
          Text(label('sampleMenu')),
          const SizedBox(height: 12),
          if (widget.practice == GuidePractice.scale) ...[
            Text(label('scaleIntro')),
            const SizedBox(height: 12),
            Wrap(spacing: 8, runSpacing: 4, children: [
              for (final servings in [4, 10, 20])
                ChoiceChip(
                    key: Key('guide-example-servings-$servings'),
                    label: LocalizedText('$servings ${label('servings')}'),
                    selected: _servings == servings,
                    onSelected: (_) {
                      setState(() => _servings = servings);
                      widget.onPracticed?.call();
                    }),
            ]),
            metric(label('usage'), '${amount(example.usage)} g',
                'guide-example-usage'),
          ] else if (widget.practice == GuidePractice.yieldLoss) ...[
            Text(label('yieldIntro')),
            const SizedBox(height: 12),
            LocalizedText('${label('yield')} · ${amount(_yield)}%'),
            Slider(
                key: const Key('guide-example-yield'),
                value: _yield,
                min: 50,
                max: 100,
                divisions: 10,
                label: '${amount(_yield)}%',
                semanticFormatterCallback: (v) => '${amount(v)}%',
                onChanged: (value) {
                  setState(() => _yield = value);
                  widget.onPracticed?.call();
                }),
            metric(label('purchase'), '${amount(example.purchase)} g',
                'guide-example-purchase'),
          ] else if (widget.practice == GuidePractice.pricing) ...[
            Text(label('pricingIntro')),
            const SizedBox(height: 12),
            LocalizedText('${label('markup')} · ${amount(_markup)}%'),
            Slider(
                key: const Key('guide-example-markup'),
                value: _markup,
                min: 0,
                max: 100,
                divisions: 20,
                label: '${amount(_markup)}%',
                semanticFormatterCallback: (v) => '${amount(v)}%',
                onChanged: (value) {
                  setState(() => _markup = value);
                  widget.onPracticed?.call();
                }),
            metric(label('price'), 'KRW ${amount(example.price)}',
                'guide-example-price'),
            const Divider(),
            metric(label('revenue'), 'KRW ${amount(example.revenueForTen)}',
                'guide-example-revenue'),
            metric(
                label('difference'),
                'KRW ${amount(example.differenceForTen)}',
                'guide-example-difference'),
            Text(label('marginNote'),
                style: Theme.of(context).textTheme.bodySmall),
          ],
          const SizedBox(height: 12),
          Text(label('exampleNote'),
              style: Theme.of(context).textTheme.bodySmall),
        ]));
  }
}
