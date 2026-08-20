import 'youtube_search_exception.dart';
import 'youtube_search_result.dart';

class YoutubeSearchRequest {
  const YoutubeSearchRequest({required this.query, this.limit = 5});
  final String query;
  final int limit;
}

class YoutubeSearchPage {
  const YoutubeSearchPage({required this.items, required this.nextPageToken});
  final List<YoutubeSearchResult> items;
  final String? nextPageToken;

  factory YoutubeSearchPage.fromResponse(Object? value) {
    if (value is! Map<String, Object?> || value['status'] != 'ok') {
      throw const YoutubeSearchException('youtube_response_invalid');
    }
    final data = value['data'];
    if (data is! Map<String, Object?> || data['items'] is! List<Object?>) {
      throw const YoutubeSearchException('youtube_response_invalid');
    }
    final token = data['nextPageToken'];
    if (token != null && token is! String) {
      throw const YoutubeSearchException('youtube_response_invalid');
    }
    return YoutubeSearchPage(
      items: (data['items'] as List<Object?>)
          .map(YoutubeSearchResult.fromJson)
          .toList(growable: false),
      nextPageToken: token as String?,
    );
  }
}
