import '../domain/recipe.dart';

enum RecipeCapabilityState {
  ready,
  partial,
  blocked,
}

class RecipeActionCapability {
  const RecipeActionCapability({
    required this.enabled,
    this.reason,
  });

  final bool enabled;
  final String? reason;
}

class RecipeCapabilityReport {
  const RecipeCapabilityReport({
    required this.state,
    required this.quickCook,
    required this.aiSummary,
    required this.shoppingList,
    required this.cookFeedback,
    required this.cookRecord,
  });

  final RecipeCapabilityState state;
  final RecipeActionCapability quickCook;
  final RecipeActionCapability aiSummary;
  final RecipeActionCapability shoppingList;
  final RecipeActionCapability cookFeedback;
  final RecipeActionCapability cookRecord;

  String get stateLabel {
    switch (state) {
      case RecipeCapabilityState.ready:
        return '기능 상태: 준비됨';
      case RecipeCapabilityState.partial:
        return '기능 상태: 일부 제한';
      case RecipeCapabilityState.blocked:
        return '기능 상태: 사용 제한';
    }
  }

  String get stateMessage {
    switch (state) {
      case RecipeCapabilityState.ready:
        return '상세 핵심 액션 5개를 모두 사용할 수 있습니다.';
      case RecipeCapabilityState.partial:
        return '일부 액션은 데이터 또는 로그인 상태에 따라 제한됩니다.';
      case RecipeCapabilityState.blocked:
        return '핵심 데이터 또는 로그인 조건이 부족해 액션 사용이 제한됩니다.';
    }
  }
}

class RecipeCapabilityEvaluator {
  static RecipeCapabilityReport evaluateCreatorDetail({
    required Recipe recipe,
    required bool isLoggedIn,
  }) {
    final hasIngredients = recipe.ingredients.isNotEmpty;
    final hasSteps = recipe.steps.isNotEmpty;
    final hasAnyCookData = hasIngredients || hasSteps;

    final quickCook = RecipeActionCapability(
      enabled: hasSteps,
      reason: hasSteps ? null : '조리 순서가 없어 바로 요리 시작을 사용할 수 없습니다.',
    );

    final aiSummary = RecipeActionCapability(
      enabled: hasAnyCookData,
      reason: hasAnyCookData ? null : '재료/조리 순서 데이터가 없어 AI 요약 생성이 제한됩니다.',
    );

    final shoppingList = RecipeActionCapability(
      enabled: isLoggedIn && hasIngredients,
      reason: isLoggedIn
          ? (hasIngredients ? null : '재료가 없어 장보기 리스트를 만들 수 없습니다.')
          : '로그인 후 장보기 리스트를 만들 수 있습니다.',
    );

    final cookFeedback = RecipeActionCapability(
      enabled: isLoggedIn,
      reason: isLoggedIn ? null : '로그인 후 조리 완료 피드백을 남길 수 있습니다.',
    );

    final cookRecord = RecipeActionCapability(
      enabled: isLoggedIn,
      reason: isLoggedIn ? null : '로그인 후 조리 완료 기록을 저장할 수 있습니다.',
    );

    final enabledCount = <bool>[
      quickCook.enabled,
      aiSummary.enabled,
      shoppingList.enabled,
      cookFeedback.enabled,
      cookRecord.enabled,
    ].where((bool value) => value).length;

    final state = enabledCount == 5
        ? RecipeCapabilityState.ready
        : (enabledCount == 0 ? RecipeCapabilityState.blocked : RecipeCapabilityState.partial);

    return RecipeCapabilityReport(
      state: state,
      quickCook: quickCook,
      aiSummary: aiSummary,
      shoppingList: shoppingList,
      cookFeedback: cookFeedback,
      cookRecord: cookRecord,
    );
  }
}
