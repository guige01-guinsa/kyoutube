import 'package:flutter_test/flutter_test.dart';
import 'package:k_youtube/features/recipes/domain/recipe_identity.dart';

void main() {
  group('RecipeIdentity', () {
    test('parses a typed public recipe reference', () {
      final identity = RecipeIdentity.parse('public:recipe-1');

      expect(identity.sourceType, 'public');
      expect(identity.sourceId, 'recipe-1');
      expect(identity.reference, 'public:recipe-1');
      expect(identity.isPublic, isTrue);
      expect(identity.isCreator, isFalse);
      expect(identity.isUser, isFalse);
    });

    test('normalizes source type and trims source id', () {
      final identity = RecipeIdentity.parse(' Creator : abc ');

      expect(identity.sourceType, 'creator');
      expect(identity.sourceId, 'abc');
      expect(identity.reference, 'creator:abc');
    });

    test('rejects unsupported source types', () {
      expect(
        () => RecipeIdentity.parse('external:abc'),
        throwsA(isA<FormatException>()),
      );
    });

    test('rejects untyped references', () {
      expect(
        () => RecipeIdentity.parse('abc'),
        throwsA(isA<FormatException>()),
      );
    });

    test('uses value equality', () {
      expect(
        const RecipeIdentity(sourceType: 'user', sourceId: '1'),
        const RecipeIdentity(sourceType: 'user', sourceId: '1'),
      );
    });
  });
}
