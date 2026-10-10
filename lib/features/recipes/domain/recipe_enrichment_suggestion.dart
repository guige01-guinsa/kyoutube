import 'recipe.dart';

enum RecipeEvidenceStatus {
  confirmed,
  inferred,
  unverified;

  static RecipeEvidenceStatus parse(Object? value) {
    return switch (value) {
      'confirmed' => RecipeEvidenceStatus.confirmed,
      'inferred' => RecipeEvidenceStatus.inferred,
      _ => RecipeEvidenceStatus.unverified,
    };
  }

  String get label => switch (this) {
        RecipeEvidenceStatus.confirmed => '확인됨',
        RecipeEvidenceStatus.inferred => '추정',
        RecipeEvidenceStatus.unverified => '확인 필요',
      };
}

class RecipeIngredientDetail {
  const RecipeIngredientDetail({
    required this.name,
    required this.status,
    this.quantity,
    this.unit,
    this.preparation,
  });

  final String name;
  final String? quantity;
  final String? unit;
  final String? preparation;
  final RecipeEvidenceStatus status;

  factory RecipeIngredientDetail.fromJson(Map<String, dynamic> json) {
    String? optionalText(Object? value) {
      final normalized = value?.toString().trim() ?? '';
      return normalized.isEmpty ? null : normalized;
    }

    return RecipeIngredientDetail(
      name: optionalText(json['name']) ?? '영상에서 확인 필요',
      quantity: optionalText(json['quantity']),
      unit: optionalText(json['unit']),
      preparation: optionalText(json['preparation']),
      status: RecipeEvidenceStatus.parse(json['status']),
    );
  }
}

class RecipeStepDetail {
  const RecipeStepDetail({
    required this.instruction,
    required this.status,
    this.durationMinutes,
    this.ingredientNames = const <String>[],
  });

  final String instruction;
  final int? durationMinutes;
  final List<String> ingredientNames;
  final RecipeEvidenceStatus status;

  factory RecipeStepDetail.fromJson(Map<String, dynamic> json) {
    final rawDuration = json['durationMinutes'];
    final rawNames = json['ingredientNames'];
    return RecipeStepDetail(
      instruction: (json['instruction'] as String? ?? '').trim(),
      durationMinutes: rawDuration is num ? rawDuration.toInt() : null,
      ingredientNames: rawNames is List<dynamic>
          ? rawNames
              .map((item) => item.toString().trim())
              .where((item) => item.isNotEmpty)
              .toList(growable: false)
          : const <String>[],
      status: RecipeEvidenceStatus.parse(json['status']),
    );
  }
}

class RecipeEnrichmentReference {
  const RecipeEnrichmentReference({
    required this.type,
    required this.title,
    this.id,
    this.channelName,
    this.youtubeUrl,
  });

  final String type;
  final String title;
  final String? id;
  final String? channelName;
  final String? youtubeUrl;

  factory RecipeEnrichmentReference.fromJson(Map<String, dynamic> json) {
    return RecipeEnrichmentReference(
      type: json['type'] as String? ?? 'public',
      id: json['id'] as String?,
      title: json['title'] as String? ?? '참고 레시피',
      channelName: json['channelName'] as String?,
      youtubeUrl: json['youtubeUrl'] as String?,
    );
  }
}

class RecipeEnrichmentSuggestion {
  const RecipeEnrichmentSuggestion({
    required this.title,
    required this.summary,
    required this.ingredients,
    required this.steps,
    required this.references,
    required this.warnings,
    this.tips,
    this.servings,
    this.prepTimeMinutes,
    this.cookTimeMinutes,
    this.ingredientDetails = const <RecipeIngredientDetail>[],
    this.stepDetails = const <RecipeStepDetail>[],
  });

  final String title;
  final String summary;
  final List<String> ingredients;
  final List<String> steps;
  final String? tips;
  final List<String> warnings;
  final List<RecipeEnrichmentReference> references;
  final int? servings;
  final int? prepTimeMinutes;
  final int? cookTimeMinutes;
  final List<RecipeIngredientDetail> ingredientDetails;
  final List<RecipeStepDetail> stepDetails;

  bool get hasItemsRequiringReview =>
      ingredientDetails.any(
        (item) => item.status != RecipeEvidenceStatus.confirmed,
      ) ||
      stepDetails.any(
        (item) => item.status != RecipeEvidenceStatus.confirmed,
      );

  factory RecipeEnrichmentSuggestion.fromJson(Map<String, dynamic> json) {
    List<String> stringList(Object? value) {
      if (value is! List<dynamic>) {
        return const <String>[];
      }

      return value
          .map((item) => item.toString().trim())
          .where((item) => item.isNotEmpty)
          .toList(growable: false);
    }

    final referencesRaw = json['references'];
    final ingredientDetailsRaw = json['ingredientDetails'];
    final stepDetailsRaw = json['stepDetails'];

    int? positiveInt(Object? value) {
      if (value is num && value > 0) {
        return value.toInt();
      }
      return null;
    }

    return RecipeEnrichmentSuggestion(
      title: (json['title'] as String? ?? '').trim(),
      summary: (json['summary'] as String? ?? '').trim(),
      ingredients: stringList(json['ingredients']),
      steps: stringList(json['steps']),
      tips: (json['tips'] as String?)?.trim(),
      warnings: stringList(json['warnings']),
      servings: positiveInt(json['servings']),
      prepTimeMinutes: positiveInt(json['prepTimeMinutes']),
      cookTimeMinutes: positiveInt(json['cookTimeMinutes']),
      ingredientDetails: ingredientDetailsRaw is List<dynamic>
          ? ingredientDetailsRaw
              .whereType<Map<String, dynamic>>()
              .map(RecipeIngredientDetail.fromJson)
              .toList(growable: false)
          : const <RecipeIngredientDetail>[],
      stepDetails: stepDetailsRaw is List<dynamic>
          ? stepDetailsRaw
              .whereType<Map<String, dynamic>>()
              .map(RecipeStepDetail.fromJson)
              .where((item) => item.instruction.isNotEmpty)
              .toList(growable: false)
          : const <RecipeStepDetail>[],
      references: referencesRaw is List<dynamic>
          ? referencesRaw
              .whereType<Map<String, dynamic>>()
              .map(RecipeEnrichmentReference.fromJson)
              .toList(growable: false)
          : const <RecipeEnrichmentReference>[],
    );
  }

  Recipe toDraftRecipe({
    required Recipe sourceRecipe,
    bool isEnglish = false,
  }) {
    final editableTips = <String>[
      if ((tips ?? '').trim().isNotEmpty) tips!.trim(),
      if (warnings.isNotEmpty)
        '${isEnglish ? 'Review notes' : '확인사항'}: ${warnings.join(' / ')}',
    ].join('\n');

    return Recipe(
      id: '',
      title: title.isEmpty ? sourceRecipe.title : title,
      summary: summary,
      tips: editableTips.isEmpty ? null : editableTips,
      ingredients: ingredients,
      steps: steps,
      imageUrl: sourceRecipe.imageUrl,
      youtubeUrl: sourceRecipe.youtubeUrl,
      notes: sourceRecipe.notes,
      sourceType: 'ai_enrichment_draft',
    );
  }
}
