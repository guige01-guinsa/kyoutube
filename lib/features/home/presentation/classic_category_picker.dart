import 'package:flutter/material.dart';
import '../../../core/theme/app_theme.dart';
import '../domain/korean_classics.dart';
import 'classic_recipe_widgets.dart';

/// Filters wrap into equal-width rows instead of squeezing enlarged labels.
class ClassicCategoryPicker extends StatelessWidget {
  const ClassicCategoryPicker(
      {super.key, required this.selected, required this.onSelected});
  final String selected;
  final ValueChanged<String> onSelected;

  @override
  Widget build(BuildContext context) =>
      LayoutBuilder(builder: (context, constraints) {
        final largeText = MediaQuery.textScalerOf(context).scale(1) > 1.3;
        final columns = largeText
            ? constraints.maxWidth >= 600
                ? 2
                : 1
            : constraints.maxWidth >= 640
                ? 5
                : constraints.maxWidth >= 340
                    ? 3
                    : 2;
        final width = (constraints.maxWidth - (columns - 1) * 8) / columns;
        return Wrap(
          key: const Key('classic-category-picker'),
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final id in classicCategories.keys)
              SizedBox(
                width: width,
                child: Semantics(
                  selected: id == selected,
                  button: true,
                  child: Material(
                    color: id == selected ? ScoutStyle.ink : ScoutStyle.mint,
                    borderRadius: BorderRadius.circular(12),
                    clipBehavior: Clip.antiAlias,
                    child: InkWell(
                      key: ValueKey('classic-filter-$id'),
                      onTap: () => onSelected(id),
                      child: Container(
                        constraints: const BoxConstraints(minHeight: 48),
                        alignment: Alignment.center,
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 12),
                        child: Text(
                          homeText(context, classicCategories[id]!),
                          textAlign: TextAlign.center,
                          style:
                              Theme.of(context).textTheme.labelLarge?.copyWith(
                                    color: id == selected
                                        ? Colors.white
                                        : ScoutStyle.ink,
                                    fontWeight: id == selected
                                        ? FontWeight.w700
                                        : FontWeight.w500,
                                  ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
          ],
        );
      });
}
