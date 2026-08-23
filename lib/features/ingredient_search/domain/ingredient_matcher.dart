class IngredientRequirement {
  const IngredientRequirement({
    required this.rawText,
    required this.normalizedName,
    required this.isAvailable,
  });

  final String rawText;
  final String normalizedName;
  final bool isAvailable;
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

  static String normalize(String raw) {
    var value = raw.trim().toLowerCase();

    if (value.isEmpty) {
      return '';
    }

    value = value.replaceAll(RegExp(r'\([^)]*\)'), ' ');
    value = value.replaceAll(
      RegExp(
        r'\b\d+(?:\.\d+)?(?:/\d+)?\s*(kg|g|ml|l|개|큰술|작은술|컵|대|쪽|알|장|봉|팩|줌|꼬집|인분)?\b',
        caseSensitive: false,
      ),
      ' ',
    );

    value = value.replaceAll(
      RegExp(
        r'\d+(?:\.\d+)?(?:/\d+)?\s*(kg|g|ml|l|개|큰술|작은술|컵|대|쪽|알|장|봉|팩|줌|꼬집|인분)?',
        caseSensitive: false,
      ),
      ' ',
    );

    value = value.replaceAll(
      RegExp(
        r'(^|\s)(kg|g|ml|l|개|큰술|작은술|컵|대|쪽|알|장|봉|팩|줌|꼬집|인분)(?=\s|$)',
        caseSensitive: false,
      ),
      r'$1',
    );

    value = value.replaceAll(RegExp(r'[^0-9a-z가-힣\s]'), ' ');
    // 수량/단위 제거 후 남는 숫자나 분수 표기를 마지막으로 정리한다.
    value = value.replaceAll(RegExp(r'[0-9./]+'), ' ');
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
          final normalized = normalize(raw);

          if (normalized.isEmpty) {
            return null;
          }

          final isAvailable = available.any(
            (ingredient) => matches(normalized, ingredient),
          );

          return IngredientRequirement(
            rawText: raw.trim(),
            normalizedName: normalized,
            isAvailable: isAvailable,
          );
        })
        .whereType<IngredientRequirement>()
        .toList(growable: false);

    return IngredientMatchResult(requirements: requirements);
  }
}
