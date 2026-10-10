import 'recipe.dart';

class RecipeSearchExclusion {
  const RecipeSearchExclusion({
    required this.id,
    required this.sourceType,
    required this.sourceId,
    required this.title,
    required this.ingredients,
    required this.steps,
    required this.reasonCodes,
    required this.status,
    required this.createdAt,
    this.summary,
    this.imageUrl,
    this.youtubeUrl,
  });

  factory RecipeSearchExclusion.fromJson(Map<String, dynamic> json) {
    List<String> strings(Object? value) {
      if (value is! List<dynamic>) return const <String>[];
      return value
          .map((item) => item.toString().trim())
          .where((item) => item.isNotEmpty)
          .toList(growable: false);
    }

    return RecipeSearchExclusion(
      id: json['id'] as String? ?? '',
      sourceType: json['source_type'] as String? ?? 'public',
      sourceId: json['source_id']?.toString() ?? '',
      title: json['title'] as String? ?? '제목 없는 레시피',
      summary: json['summary'] as String?,
      ingredients: strings(json['ingredients']),
      steps: strings(json['steps']),
      imageUrl: json['image_url'] as String?,
      youtubeUrl: json['youtube_url'] as String?,
      reasonCodes: strings(json['reason_codes']),
      status: json['status'] as String? ?? 'hidden',
      createdAt: DateTime.tryParse(json['created_at'] as String? ?? '') ??
          DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
    );
  }

  final String id;
  final String sourceType;
  final String sourceId;
  final String title;
  final String? summary;
  final List<String> ingredients;
  final List<String> steps;
  final String? imageUrl;
  final String? youtubeUrl;
  final List<String> reasonCodes;
  final String status;
  final DateTime createdAt;

  String get sourceKey => '$sourceType:$sourceId';
  bool get needsEdit => status == 'needs_edit';

  Recipe toEditableDraft() => Recipe(
        id: '',
        title: title,
        summary: summary,
        ingredients: ingredients,
        steps: steps,
        imageUrl: imageUrl,
        youtubeUrl: youtubeUrl,
        sourceType: 'ai_enrichment_draft',
      );
}
