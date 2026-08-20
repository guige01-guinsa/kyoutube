import 'youtube_search_exception.dart';
import 'youtube_display_text.dart';

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

  factory YoutubeSearchResult.fromJson(Object? value) {
    if (value is! Map<String, Object?>) {
      throw const YoutubeSearchException('youtube_item_invalid');
    }
    String requiredString(String name) {
      final field = value[name];
      if (field is! String || field.trim().isEmpty) {
        throw const YoutubeSearchException('youtube_item_invalid');
      }
      return field.trim();
    }

    final publishedValue = value['publishedAt'];
    if (publishedValue != null && publishedValue is! String) {
      throw const YoutubeSearchException('youtube_item_invalid');
    }
    final publishedRaw = publishedValue as String?;
    final parsedPublished = publishedRaw == null || publishedRaw.isEmpty
        ? null
        : DateTime.tryParse(publishedRaw);
    if (publishedRaw != null &&
        publishedRaw.isNotEmpty &&
        parsedPublished == null) {
      throw const YoutubeSearchException('youtube_item_invalid');
    }
    final duration = value['durationSec'];
    if (duration != null && (duration is! int || duration < 0)) {
      throw const YoutubeSearchException('youtube_item_invalid');
    }
    return YoutubeSearchResult(
      videoId: requiredString('videoId'),
      title: decodeYoutubeDisplayText(requiredString('title')),
      channelTitle: decodeYoutubeDisplayText(requiredString('channelTitle')),
      publishedAt: parsedPublished,
      thumbnailUrl: requiredString('thumbnailUrl'),
      youtubeUrl: requiredString('youtubeUrl'),
      durationSec: duration as int?,
    );
  }
}
