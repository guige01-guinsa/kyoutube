import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:k_youtube/core/localization/localized_text.dart';

import '../../../../core/theme/app_theme.dart';
import '../../../../core/widgets/scout_section_heading.dart';
import '../../domain/recipe.dart';
import '../../domain/recipe_content_style.dart';
import '../recipe_thumbnail.dart';

/// Shared reading experience for public, saved and authored recipes.
class RecipeOverview extends StatelessWidget {
  const RecipeOverview({super.key, required this.recipe});
  final Recipe recipe;
  @override
  Widget build(BuildContext context) {
    final summary = (recipe.summary ?? '').trim();
    final styles = decodeRecipeContentStyles(
      recipe.contentStyles,
      legacyFieldLengths: <String, int>{
        'title': recipe.title.length,
        'summary': summary.length,
      },
    );
    final description = Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Text.rich(buildRecipeStyledTextSpan(
            context: context,
            text: recipe.title,
            ranges: styles['title'] ?? const <RecipeContentStyleRange>[],
            baseStyle: Theme.of(context).textTheme.headlineSmall,
          )),
          const SizedBox(height: 10),
          if (summary.isEmpty)
            LocalizedText(
              '요약 정보가 없습니다.',
              style: Theme.of(context)
                  .textTheme
                  .bodyLarge
                  ?.copyWith(color: ScoutStyle.muted),
            )
          else
            Text.rich(buildRecipeStyledTextSpan(
              context: context,
              text: summary,
              ranges: styles['summary'] ?? const <RecipeContentStyleRange>[],
              baseStyle: Theme.of(context)
                  .textTheme
                  .bodyLarge
                  ?.copyWith(color: ScoutStyle.muted),
            )),
          const SizedBox(height: 16),
          Wrap(spacing: 8, runSpacing: 8, children: <Widget>[
            Chip(
                avatar: const Icon(Icons.restaurant_outlined, size: 17),
                label: LocalizedText('재료 ${recipe.ingredients.length}개')),
            Chip(
                avatar:
                    const Icon(Icons.format_list_numbered_rounded, size: 17),
                label: LocalizedText('조리 ${recipe.steps.length}단계')),
            if ((recipe.youtubeUrl ?? '').trim().isNotEmpty)
              const Chip(
                  avatar: Icon(Icons.play_circle_outline, size: 17),
                  label: LocalizedText('영상 레시피')),
          ]),
        ]);
    if ((recipe.imageUrl ?? '').trim().isEmpty) return description;
    return LayoutBuilder(builder: (context, constraints) {
      final wide = constraints.maxWidth >= 720 &&
          MediaQuery.textScalerOf(context).scale(1) <= 1.3;
      final imageWidth =
          wide ? constraints.maxWidth * 0.4 : constraints.maxWidth;
      final image = ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: RecipeThumbnail(
          imageUrl: recipe.imageUrl,
          width: imageWidth,
          height: (imageWidth * 9 / 16).clamp(120.0, 320.0),
        ),
      );
      if (wide) {
        return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              image,
              const SizedBox(width: 24),
              Expanded(child: description),
            ]);
      }
      return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            image,
            const SizedBox(height: 22),
            description,
          ]);
    });
  }
}

class RecipeIngredientsSection extends StatelessWidget {
  const RecipeIngredientsSection({
    super.key,
    required this.ingredients,
    this.contentStyle,
  });
  final List<String> ingredients;
  final List<RecipeContentStyleRange>? contentStyle;
  @override
  Widget build(BuildContext context) =>
      Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: <Widget>[
        const ScoutSectionHeading(
            title: '재료', subtitle: '요리를 시작하기 전에 준비해 주세요.'),
        const SizedBox(height: 14),
        if (ingredients.isEmpty)
          const LocalizedText('등록된 재료 정보가 없습니다.')
        else
          Card(
              child: Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 18, vertical: 4),
                  child: Column(children: <Widget>[
                    for (var i = 0; i < ingredients.length; i++) ...<Widget>[
                      if (i > 0) const Divider(height: 1),
                      Padding(
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: <Widget>[
                                const Padding(
                                    padding: EdgeInsets.only(top: 10),
                                    child: Icon(Icons.check_rounded,
                                        size: 18, color: ScoutStyle.forest)),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Text.rich(
                                    buildRecipeStyledTextSpan(
                                      context: context,
                                      text: ingredients[i],
                                      ranges: _rangesForListItem(
                                        ingredients,
                                        i,
                                        contentStyle ??
                                            const <RecipeContentStyleRange>[],
                                      ),
                                      baseStyle:
                                          Theme.of(context).textTheme.bodyLarge,
                                    ),
                                  ),
                                ),
                              ])),
                    ],
                  ]))),
      ]);
}

/// A local reading aid. Checkmarks are deliberately not persisted as cooking history.
class RecipeStepsSection extends StatefulWidget {
  const RecipeStepsSection({
    super.key,
    required this.steps,
    this.contentStyle,
  });
  final List<String> steps;
  final List<RecipeContentStyleRange>? contentStyle;
  @override
  State<RecipeStepsSection> createState() => _RecipeStepsSectionState();
}

class _RecipeStepsSectionState extends State<RecipeStepsSection> {
  final Set<int> _completed = <int>{};
  @override
  void didUpdateWidget(covariant RecipeStepsSection oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!listEquals(oldWidget.steps, widget.steps)) _completed.clear();
  }

  @override
  Widget build(BuildContext context) =>
      Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: <Widget>[
        ScoutSectionHeading(
            title: '조리 순서',
            subtitle: widget.steps.isEmpty
                ? null
                : '끝낸 단계를 눌러 체크하세요. 이 화면에서만 표시됩니다.'),
        const SizedBox(height: 14),
        if (widget.steps.isEmpty)
          const LocalizedText('등록된 조리 순서가 없습니다.')
        else ...<Widget>[
          LocalizedText('${_completed.length} / ${widget.steps.length}단계 완료',
              style: Theme.of(context).textTheme.labelLarge),
          const SizedBox(height: 8),
          LinearProgressIndicator(
              value: _completed.length / widget.steps.length,
              minHeight: 5,
              borderRadius: BorderRadius.circular(8),
              semanticsLabel: context.tr('조리 단계 진행률')),
          const SizedBox(height: 16),
          for (var i = 0; i < widget.steps.length; i++)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Semantics(
                checked: _completed.contains(i),
                label: '${i + 1}단계',
                child: Card(
                  color: _completed.contains(i) ? ScoutStyle.mint : null,
                  clipBehavior: Clip.antiAlias,
                  child: InkWell(
                    key: ValueKey('recipe-step-$i'),
                    onTap: () => setState(() {
                      if (!_completed.add(i)) _completed.remove(i);
                    }),
                    child: Padding(
                        padding: const EdgeInsets.all(18),
                        child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: <Widget>[
                              Container(
                                  constraints: const BoxConstraints(
                                      minWidth: 32, minHeight: 32),
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 8, vertical: 4),
                                  alignment: Alignment.center,
                                  decoration: BoxDecoration(
                                      color: _completed.contains(i)
                                          ? ScoutStyle.forest
                                          : ScoutStyle.mint,
                                      borderRadius: BorderRadius.circular(10)),
                                  child: _completed.contains(i)
                                      ? const Icon(Icons.check,
                                          size: 20, color: Colors.white)
                                      : LocalizedText('${i + 1}',
                                          style: const TextStyle(
                                              fontWeight: FontWeight.w800,
                                              color: ScoutStyle.forest))),
                              const SizedBox(width: 14),
                              Expanded(
                                child: Text.rich(
                                  buildRecipeStyledTextSpan(
                                    context: context,
                                    text: widget.steps[i],
                                    ranges: _rangesForListItem(
                                      widget.steps,
                                      i,
                                      widget.contentStyle ??
                                          const <RecipeContentStyleRange>[],
                                    ),
                                    baseStyle:
                                        Theme.of(context).textTheme.bodyLarge,
                                  ),
                                ),
                              ),
                            ])),
                  ),
                ),
              ),
            ),
        ],
      ]);
}

List<RecipeContentStyleRange> _rangesForListItem(
  List<String> items,
  int index,
  List<RecipeContentStyleRange> ranges,
) {
  var start = 0;
  for (var itemIndex = 0; itemIndex < index; itemIndex++) {
    start += items[itemIndex].length + 1;
  }
  return styleRangesForSlice(ranges, start, start + items[index].length);
}
