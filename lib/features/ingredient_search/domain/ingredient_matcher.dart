class IngredientRequirement {
  const IngredientRequirement({
    required this.rawText,
    required this.normalizedName,
    required this.isAvailable,
    required this.requiresReview,
  });

  final String rawText;
  final String normalizedName;
  final bool isAvailable;
  final bool requiresReview;
}

class IngredientMatchResult {
  const IngredientMatchResult({
    required this.requirements,
  });

  final List<IngredientRequirement> requirements;

  List<IngredientRequirement> get available =>
      requirements.where((item) => item.isAvailable).toList(growable: false);

  List<IngredientRequirement> get missing =>
      requirements.where((item) => !item.isAvailable).toList(growable: false);

  int get totalCount => requirements.length;
  int get availableCount => available.length;
  int get missingCount => missing.length;

  bool get canCookNow => totalCount > 0 && missingCount == 0;

  bool get needsOnlyOneIngredient => missingCount == 1;
}

class IngredientMatcher {
  const IngredientMatcher._();

  static final RegExp _numericQuantityWithUnit = RegExp(
    r'(?:\d{1,3}(?:,\d{3})+|\d+|[¼½¾⅓⅔])(?:\.\d+)?(?:\s+\d+/\d+|/\d+)?\s*'
    r'(?:킬로그램|키로그램|밀리리터|리터|그램|'
    r'큰술|큰스푼|밥숟가락|작은술|작은스푼|티스푼|스푼|숟가락|'
    r'종이컵|컵|개|알|모|통|대|줄기|쪽|장|봉지|봉|팩|포|병|캔|'
    r'줌|꼬집|단|망|묶음|인분|'
    r'tablespoons?|tbsp|teaspoons?|tsp|spoons?|cups?|ounces?|oz|'
    r'pounds?|lbs?|lb|cloves?|pieces?|packs?|bags?|bottles?|cans?|'
    r'cucharadas?|cucharaditas?|tazas?|gramos?|mililitros?|litros?|unidades?|'
    r'kg|ml|cc|g|l|T|t)',
    caseSensitive: false,
  );

  static final RegExp _numericRangeWithUnit = RegExp(
    r'(?:\d{1,3}(?:,\d{3})+|\d+)(?:\.\d+)?\s*(?:~|-|–|—)\s*'
    r'(?:\d{1,3}(?:,\d{3})+|\d+)(?:\.\d+)?\s*'
    r'(?:킬로그램|키로그램|밀리리터|리터|그램|'
    r'큰술|큰스푼|밥숟가락|작은술|작은스푼|티스푼|스푼|숟가락|'
    r'종이컵|컵|개|알|모|통|대|줄기|쪽|장|봉지|봉|팩|포|병|캔|'
    r'줌|꼬집|단|망|묶음|인분|tbsp|tsp|cups?|oz|lbs?|lb|kg|ml|cc|g|l|T|t)',
    caseSensitive: false,
  );

  static final RegExp _wordQuantityWithUnit = RegExp(
    r'(?:반|한|두|세|네|다섯|여섯|일곱|여덟|아홉|열)\s*'
    r'(?:개|알|모|통|대|줄기|쪽|장|봉지|봉|팩|포|병|캔|줌|꼬집|단|망|묶음|'
    r'큰술|큰스푼|작은술|작은스푼|티스푼|스푼|숟가락|컵|종이컵)',
    caseSensitive: false,
  );

  static final RegExp _qualitativeAmount = RegExp(
    r'\s*(?:약간|적당량|조금|소량|기호에\s*따라|취향껏|한\s*줌|한\s*꼬집)\s*$',
    caseSensitive: false,
  );

  static bool requiresManualReview(String raw) => RegExp(
        r'(확인\s*필요|\[\s*추정\s*\]|영상에서\s*확인)',
        caseSensitive: false,
      ).hasMatch(raw);

  static String normalize(String raw) {
    var value = raw.trim().toLowerCase();

    if (value.isEmpty) {
      return '';
    }

    // Recipe notes remain in the original text. Names used for searching do
    // not include preparation notes or optional package sizes in parentheses.
    value = value.replaceAll(RegExp(r'\([^)]*\)'), ' ');
    value = value.replaceAll(
      RegExp(r'\[\s*(확인\s*필요|추정)\s*\]', caseSensitive: false),
      ' ',
    );
    value = value.replaceAll(
      RegExp(r'영상에서\s*확인\s*필요', caseSensitive: false),
      ' ',
    );
    value = value.replaceAll(_numericRangeWithUnit, ' ');
    value = value.replaceAll(_numericQuantityWithUnit, ' ');
    value = value.replaceAll(_wordQuantityWithUnit, ' ');
    value = value.replaceAll(_qualitativeAmount, ' ');

    // Keep numbers that are part of a product name, such as "3분 카레".
    // Accented Latin characters are retained for Spanish ingredient names.
    value = value.replaceAll(RegExp(r'[^0-9a-zÀ-ÖØ-öø-ÿ가-힣\s]'), ' ');
    value = value.replaceAll(RegExp(r'\s+'), ' ').trim();

    return value;
  }

  static bool matches(String left, String right) {
    final normalizedLeft = normalize(left);
    final normalizedRight = normalize(right);

    if (normalizedLeft.isEmpty || normalizedRight.isEmpty) {
      return false;
    }

    return normalizedLeft == normalizedRight ||
        normalizedLeft.contains(normalizedRight) ||
        normalizedRight.contains(normalizedLeft);
  }

  static IngredientMatchResult match({
    required List<String> recipeIngredients,
    required List<String> availableIngredients,
  }) {
    final available = availableIngredients
        .map(normalize)
        .where((item) => item.isNotEmpty)
        .toList(growable: false);

    final requirements = recipeIngredients
        .map((raw) {
          final requiresReview = requiresManualReview(raw);
          var normalized = normalize(raw);

          if (normalized.isEmpty && requiresReview) {
            normalized = '미확인 재료';
          }

          if (normalized.isEmpty) {
            return null;
          }

          final isAvailable = !requiresReview &&
              available.any(
                (ingredient) => matches(normalized, ingredient),
              );

          return IngredientRequirement(
            rawText: raw.trim(),
            normalizedName: normalized,
            isAvailable: isAvailable,
            requiresReview: requiresReview,
          );
        })
        .whereType<IngredientRequirement>()
        .toList(growable: false);

    return IngredientMatchResult(requirements: requirements);
  }
}
