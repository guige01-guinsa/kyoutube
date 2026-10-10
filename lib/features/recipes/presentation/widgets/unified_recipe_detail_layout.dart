import 'package:flutter/material.dart';
import 'package:k_youtube/core/localization/localized_text.dart';

import '../../domain/recipe.dart';
import '../../domain/recipe_content_style.dart';
import '../../../../core/widgets/scout_page.dart';
import 'recipe_reading_sections.dart';

class UnifiedRecipeDetailLayout extends StatelessWidget {
  const UnifiedRecipeDetailLayout({
    super.key,
    required this.recipe,
    required this.appBarTitle,
    this.appBarActions = const <Widget>[],
    this.primaryActions = const <Widget>[],
    this.extraSections = const <Widget>[],
    this.footer,
  });

  final Recipe recipe;
  final String appBarTitle;
  final List<Widget> appBarActions;
  final List<Widget> primaryActions;
  final List<Widget> extraSections;
  final Widget? footer;

  @override
  Widget build(BuildContext context) {
    final contentStyles = decodeRecipeContentStyles(
      recipe.contentStyles,
      legacyFieldLengths: <String, int>{
        'ingredients': recipe.ingredients.join('\n').length,
        'steps': recipe.steps.join('\n').length,
      },
    );
    return Scaffold(
      appBar: AppBar(
        title: LocalizedText(appBarTitle),
        actions: appBarActions,
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 32),
          child: ScoutPageBody(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                ScoutPanel(child: RecipeOverview(recipe: recipe)),
                if (primaryActions.isNotEmpty) ...<Widget>[
                  const SizedBox(height: 16),
                  Wrap(spacing: 10, runSpacing: 10, children: primaryActions),
                ],
                const SizedBox(height: 28),
                LayoutBuilder(builder: (context, constraints) {
                  final ingredients = RecipeIngredientsSection(
                    ingredients: recipe.ingredients,
                    contentStyle: contentStyles['ingredients'],
                  );
                  final steps = RecipeStepsSection(
                    steps: recipe.steps,
                    contentStyle: contentStyles['steps'],
                  );
                  if (constraints.maxWidth >= 900 &&
                      MediaQuery.textScalerOf(context).scale(1) <= 1.3) {
                    return Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Expanded(flex: 2, child: ingredients),
                        const SizedBox(width: 28),
                        Expanded(flex: 3, child: steps),
                      ],
                    );
                  }
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: <Widget>[
                      ingredients,
                      const SizedBox(height: 28),
                      steps,
                    ],
                  );
                }),
                if (extraSections.isNotEmpty) ...<Widget>[
                  const SizedBox(height: 24),
                  ...extraSections,
                ],
                if (footer != null) ...<Widget>[
                  const SizedBox(height: 28),
                  footer!,
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
