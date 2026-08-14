import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:k_youtube/features/recipes/domain/recipe.dart';
import 'package:k_youtube/features/recipes/presentation/widgets/unified_recipe_detail_layout.dart';

void main() {
  testWidgets('renders common recipe content and primary actions', (
    WidgetTester tester,
  ) async {
    final recipe = Recipe(
      id: 'recipe-1',
      title: 'Tomato Soup',
      summary: 'Simple soup',
      ingredients: <String>['Tomato', 'Salt'],
      steps: <String>['Boil', 'Serve'],
    );

    await tester.pumpWidget(
      MaterialApp(
        home: UnifiedRecipeDetailLayout(
          recipe: recipe,
          appBarTitle: 'Recipe',
          primaryActions: <Widget>[
            FilledButton(
              onPressed: () {},
              child: const Text('Prepare shopping'),
            ),
          ],
          extraSections: const <Widget>[
            Text('Extra recipe section'),
          ],
        ),
      ),
    );

    expect(find.text('Tomato Soup'), findsOneWidget);
    expect(find.text('Simple soup'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.text('\u2022 Tomato'),
      200,
    );

    expect(find.text('\u2022 Tomato'), findsOneWidget);

    await tester.scrollUntilVisible(
      find.text('1. Boil'),
      200,
    );

    expect(find.text('1. Boil'), findsOneWidget);
    expect(find.text('Prepare shopping'), findsOneWidget);
    expect(find.text('Extra recipe section'), findsOneWidget);
  });

  testWidgets('shows a fallback when summary is unavailable', (
    WidgetTester tester,
  ) async {
    final recipe = Recipe(
      id: 'recipe-2',
      title: 'Plain Recipe',
      ingredients: const <String>[],
      steps: const <String>[],
    );

    await tester.pumpWidget(
      MaterialApp(
        home: UnifiedRecipeDetailLayout(
          recipe: recipe,
          appBarTitle: 'Recipe',
        ),
      ),
    );

    expect(
      find.text('\uC694\uC57D \uC815\uBCF4\uAC00 \uC5C6\uC2B5\uB2C8\uB2E4.'),
      findsOneWidget,
    );
    expect(
      find.text(
          '\uB4F1\uB85D\uB41C \uC7AC\uB8CC \uC815\uBCF4\uAC00 \uC5C6\uC2B5\uB2C8\uB2E4.'),
      findsOneWidget,
    );
    expect(
      find.text(
          '\uB4F1\uB85D\uB41C \uC870\uB9AC \uC21C\uC11C\uAC00 \uC5C6\uC2B5\uB2C8\uB2E4.'),
      findsOneWidget,
    );
  });
}
