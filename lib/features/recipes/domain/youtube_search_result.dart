class YoutubeSearchResult {
  const YoutubeSearchResult({
    required this.videoId,
    required this.title,
    required this.channelTitle,
    required this.publishedAt,
    required this.thumbnailUrl,
    required this.youtubeUrl,
    required this.durationSec,
  });

  final String videoId;
  final String title;
  final String channelTitle;
  final DateTime? publishedAt;
  final String thumbnailUrl;
  final String youtubeUrl;
  final int? durationSec;

  static YoutubeSearchResult? fromJson(Map<String, dynamic> json) {
    final videoId = (json['videoId'] ?? '').toString().trim();
    final title = (json['title'] ?? '').toString().trim();
    final channelTitle = (json['channelTitle'] ?? '').toString().trim();
    final thumbnailUrl = (json['thumbnailUrl'] ?? '').toString().trim();
    final youtubeUrl = (json['youtubeUrl'] ?? '').toString().trim();

    if (videoId.isEmpty || title.isEmpty || youtubeUrl.isEmpty) {
      return null;
    }

    final publishedRaw = (json['publishedAt'] ?? '').toString().trim();
    final publishedAt =
        publishedRaw.isEmpty ? null : DateTime.tryParse(publishedRaw);

    final durationRaw = json['durationSec'];
    int? durationSec;
    if (durationRaw is int) {
      durationSec = durationRaw;
    } else if (durationRaw is num) {
      durationSec = durationRaw.toInt();
    }

    return YoutubeSearchResult(
      videoId: videoId,
      title: title,
      channelTitle: channelTitle,
      publishedAt: publishedAt,
      thumbnailUrl: thumbnailUrl,
      youtubeUrl: youtubeUrl,
      durationSec: durationSec,
    );
  }
}
