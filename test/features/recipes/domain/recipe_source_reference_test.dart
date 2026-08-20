import 'package:flutter_test/flutter_test.dart';
import 'package:k_youtube/features/recipes/domain/recipe_source_reference.dart';

void main() {
  test('round trips typed public, creator, and user references', () {
    for (final type in <String>['public', 'creator', 'user']) {
      final parsed = RecipeSourceReference.parse('$type:recipe-1');
      expect(parsed.type, type);
      expect(parsed.id, 'recipe-1');
      expect(parsed.value, '$type:recipe-1');
    }
  });

  test('rejects untyped or unsupported references', () {
    expect(
        () => RecipeSourceReference.parse('recipe-1'), throwsFormatException);
    expect(() => RecipeSourceReference.parse('admin:recipe-1'),
        throwsFormatException);
    expect(() => RecipeSourceReference.parse('public:'), throwsFormatException);
  });
}
