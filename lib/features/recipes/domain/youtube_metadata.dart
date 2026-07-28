class RecipeYoutubeMetadata {
  const RecipeYoutubeMetadata({
    required this.recipeCreatorId,
    required this.youtubeUrl,
    this.youtubeVideoId,
    this.title,
    this.channelName,
    this.authorUrl,
    this.thumbnailUrl,
    this.providerName,
    this.fetchedAt,
    required this.lastStatus,
    this.lastError,
  });

  final String recipeCreatorId;
  final String youtubeUrl;
  final String? youtubeVideoId;
  final String? title;
  final String? channelName;
  final String? authorUrl;
  final String? thumbnailUrl;
  final String? providerName;
  final DateTime? fetchedAt;
  final String lastStatus;
  final String? lastError;

  bool get hasError => lastStatus.toLowerCase() != 'ok' ||
      (lastError ?? '').trim().isNotEmpty;

  static RecipeYoutubeMetadata? fromJson(Map<String, dynamic> json) {
    final recipeCreatorId = (json['recipe_creator_id'] ?? '').toString().trim();
    final youtubeUrl = (json['youtube_url'] ?? '').toString().trim();
    if (recipeCreatorId.isEmpty || youtubeUrl.isEmpty) {
      return null;
    }

    final fetchedAtRaw = json['fetched_at']?.toString();
    final parsedFetchedAt =
        fetchedAtRaw == null || fetchedAtRaw.isEmpty ? null : DateTime.tryParse(fetchedAtRaw);

    return RecipeYoutubeMetadata(
      recipeCreatorId: recipeCreatorId,
      youtubeUrl: youtubeUrl,
      youtubeVideoId: json['youtube_video_id']?.toString(),
      title: json['title']?.toString(),
      channelName: json['channel_name']?.toString(),
      authorUrl: json['author_url']?.toString(),
      thumbnailUrl: json['thumbnail_url']?.toString(),
      providerName: json['provider_name']?.toString(),
      fetchedAt: parsedFetchedAt,
      lastStatus: (json['last_status'] ?? 'ok').toString(),
      lastError: json['last_error']?.toString(),
    );
  }
}