import 'recipe.dart';

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
    required this.summary,
    required this.ingredients,
    required this.steps,
    required this.references,
    required this.warnings,
    this.tips,
  });

  final String summary;
  final List<String> ingredients;
  final List<String> steps;
  final String? tips;
  final List<String> warnings;
  final List<RecipeEnrichmentReference> references;

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

    return RecipeEnrichmentSuggestion(
      summary: (json['summary'] as String? ?? '').trim(),
      ingredients: stringList(json['ingredients']),
      steps: stringList(json['steps']),
      tips: (json['tips'] as String?)?.trim(),
      warnings: stringList(json['warnings']),
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
  }) {
    return Recipe(
      id: '',
      title: sourceRecipe.title,
      summary: summary,
      tips: tips,
      ingredients: ingredients,
      steps: steps,
      imageUrl: sourceRecipe.imageUrl,
      youtubeUrl: sourceRecipe.youtubeUrl,
      notes: sourceRecipe.notes,
      sourceType: 'ai_enrichment_draft',
    );
  }
}
