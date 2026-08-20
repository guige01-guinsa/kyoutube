import 'recipe_identity.dart';
import 'unified_recipe.dart';

abstract interface class UnifiedRecipeRepository {
  Future<UnifiedRecipe?> getRecipe(RecipeIdentity identity);

  /// 사용자가 보유한 모든 레시피를 하나의 목록으로 반환한다.
  ///
  /// 생성 경로는 다를 수 있다.
  /// - public 레시피를 저장한 개인 레시피: user
  /// - 직접 작성한 레시피: creator
  /// - YouTube에서 생성한 레시피: creator + youtubeUrl
  ///
  /// 하지만 출력/사용 관점에서는 모두 UnifiedRecipe로 통일한다.
  Future<List<UnifiedRecipe>> listMyRecipes({
    String? search,
  });
}
