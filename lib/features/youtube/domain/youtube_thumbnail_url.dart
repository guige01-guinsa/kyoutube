const _youtubeHosts = <String>{
  'youtube.com',
  'www.youtube.com',
  'm.youtube.com',
  'music.youtube.com',
};

const _youtubeShortHosts = <String>{
  'youtu.be',
  'www.youtu.be',
};

final _youtubeVideoIdPattern = RegExp(r'^[A-Za-z0-9_-]{11}$');

String? youtubeThumbnailUrlFromUrl(String rawUrl) {
  final normalizedUrl = rawUrl.trim();

  if (normalizedUrl.isEmpty) {
    return null;
  }

  final uri = Uri.tryParse(normalizedUrl);

  if (uri == null || (uri.scheme != 'https' && uri.scheme != 'http')) {
    return null;
  }

  final host = uri.host.toLowerCase();
  String? videoId;

  if (_youtubeShortHosts.contains(host)) {
    if (uri.pathSegments.isNotEmpty) {
      videoId = uri.pathSegments.first;
    }
  } else if (_youtubeHosts.contains(host)) {
    if (uri.path == '/watch') {
      videoId = uri.queryParameters['v'];
    } else if (uri.pathSegments.length >= 2 &&
        <String>{'shorts', 'embed', 'live'}.contains(uri.pathSegments.first)) {
      videoId = uri.pathSegments[1];
    }
  }

  final normalizedVideoId = videoId?.trim();

  if (normalizedVideoId == null ||
      !_youtubeVideoIdPattern.hasMatch(normalizedVideoId)) {
    return null;
  }

  return 'https://i.ytimg.com/vi/$normalizedVideoId/hqdefault.jpg';
}
