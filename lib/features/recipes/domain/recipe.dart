class Recipe {
  Recipe({
    required this.id,
    required this.title,
    required this.ingredients,
    required this.steps,
    this.summary,
    this.imageUrl,
    this.youtubeUrl,
  });

  final String id;
  final String title;
  final List<String> ingredients;
  final List<String> steps;
  final String? summary;
  final String? imageUrl;
  final String? youtubeUrl;
}
