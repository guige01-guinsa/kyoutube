class AiService {
  Future<String> summarizeRecipe(String recipeText) async {
    if (recipeText.trim().isEmpty) return '';
    if (recipeText.length <= 120) return recipeText;
    return '${recipeText.substring(0, 120)}...';
  }
}
