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
  final String? sourceType;
}

class RecipeSourceType {
  static const String manual = 'manual';
  static const String publicImport = 'public_import';
  static const String youtubeImport = 'youtube_import';
  static const String creatorCopy = 'creator_copy';
}
