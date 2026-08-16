class Recipe {
  Recipe({
    required this.id,
    required this.title,
    required this.ingredients,
    required this.steps,
    this.summary,
    this.tips,
    this.imageUrl,
    this.youtubeUrl,
    this.notes,
    this.visibility,
    this.sourceType,
  });

  final String id;
  final String title;
  final List<String> ingredients;
  final List<String> steps;
  final String? summary;
  final String? tips;
  final String? imageUrl;
  final String? youtubeUrl;
  final String? notes;
  final String? visibility;

  /// 레시피가 생성되거나 저장된 원천 정보.
  ///
  /// 예: manual, public_import, youtube_import, creator_copy
  final String? sourceType;
}
