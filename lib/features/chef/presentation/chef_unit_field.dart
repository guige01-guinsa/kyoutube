import '../../../core/localization/localized_text.dart';
import '../../../core/localization/app_localizations.dart';
import 'package:flutter/material.dart';
import '../domain/chef_recipe.dart';

/// Same category vocabulary as shopping; free text is retained as a distinct unit.
class ChefUnitField extends StatefulWidget {
  const ChefUnitField(
      {super.key,
      required this.label,
      required this.value,
      required this.onChanged});
  final String label;
  final ChefUnit value;
  final ValueChanged<ChefUnit> onChanged;
  @override
  State<ChefUnitField> createState() => _ChefUnitFieldState();
}

class _ChefUnitFieldState extends State<ChefUnitField> {
  late ChefUnit selected = widget.value;
  late bool custom = selected.isCustom;
  bool get en => Localizations.localeOf(context).languageCode != 'ko';
  String categoryLabel(String value) => AppLocalizations(Localizations.localeOf(context)).translate(en
      ? const {
          '무게': 'Weight',
          '부피': 'Volume',
          '개수': 'Count',
          '포장': 'Pack',
        }[value]!
      : value);
  void choose(ChefUnit value) {
    setState(() {
      selected = value;
      custom = value.isCustom;
    });
    widget.onChanged(value);
  }

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 14),
        child:
            Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text(widget.label, style: Theme.of(context).textTheme.labelLarge),
          const SizedBox(height: 6),
          Wrap(spacing: 4, runSpacing: 2, children: [
            for (final category in const ['무게', '부피', '개수', '포장'])
              ChoiceChip(
                  label: Text(categoryLabel(category)),
                  padding: const EdgeInsets.symmetric(horizontal: 2),
                  selected: !custom && selected.category == category,
                  onSelected: (enabled) {
                    if (enabled) {
                      choose(ChefUnit.values
                          .firstWhere((u) => u.category == category));
                    }
                  }),
          ]),
          const SizedBox(height: 6),
          if (!custom)
            DropdownButtonFormField<ChefUnit>(
              key: ValueKey('${widget.label}-${selected.category}'),
              initialValue: selected,
              isExpanded: true,
              decoration:
                  InputDecoration(labelText: widget.label, isDense: true),
              items: ChefUnit.values
                  .where((u) => u.category == selected.category)
                  .map((u) => DropdownMenuItem(
                      value: u, child: Text(u.isCustom ? u.displayLabel(en) : AppLocalizations(Localizations.localeOf(context)).translate(u.displayLabel(en)))))
                  .toList(),
              onChanged: (u) {
                if (u != null) choose(u);
              },
            ),
          if (custom)
            TextFormField(
              key: ValueKey('${widget.label}-custom'),
              initialValue: selected.isCustom ? selected.label : '',
              maxLength: 20,
              decoration: InputDecoration(
                  labelText: en ? 'Your unit' : '직접 입력 단위',
                  hintText: en ? 'e.g. ladle, serving' : '예: 국자, 인분, 대접',
                  isDense: true),
              validator: (s) => s == null ||
                      s.trim().isEmpty ||
                      s.trim().runes.length > 20 ||
                      RegExp(r'[\x00-\x1f\x7f]').hasMatch(s)
                  ? (en
                      ? 'Enter a unit (1–20 characters).'
                      : '단위를 1~20자로 입력해 주세요.')
                  : null,
              onChanged: (s) {
                selected = ChefUnit.custom(s);
                widget.onChanged(selected);
              },
            ),
          if (!custom)
            Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  onPressed: () => choose(ChefUnit.custom('')),
                  icon: const Icon(Icons.edit_outlined, size: 16),
                  label: LocalizedText(en ? 'Enter another unit' : '필요한 단위 직접 입력'),
                )),
        ]),
      );
}
