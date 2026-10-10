import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('deleting a managed recipe returns to the existing recipe list', () {
    for (final path in <String>[
      'lib/features/recipes/presentation/creator_recipe_detail_page.dart',
      'lib/features/recipes/presentation/subscriber_recipe_detail_page.dart',
    ]) {
      final source = File(path).readAsStringSync();

      expect(source, contains('if (context.canPop())'));
      expect(source, contains('context.pop(true)'));
      expect(source, contains("context.go('/my-recipes')"));
    }
  });

  test('my recipe list refreshes after a detail page reports deletion', () {
    final source = File(
      'lib/features/recipes/presentation/my_recipes_page.dart',
    ).readAsStringSync();

    expect(source, contains('final deleted = await context.push<bool>(location)'));
    expect(
      source,
      contains('ref.invalidate(myUnifiedRecipesProvider(_searchQuery))'),
    );
  });
}
