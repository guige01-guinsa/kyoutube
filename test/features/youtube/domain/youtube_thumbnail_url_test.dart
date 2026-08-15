import 'package:flutter_test/flutter_test.dart';
import 'package:k_youtube/features/youtube/domain/youtube_thumbnail_url.dart';

void main() {
  group('youtubeThumbnailUrlFromUrl', () {
    test('creates a thumbnail URL from a standard watch URL', () {
      expect(
        youtubeThumbnailUrlFromUrl(
          'https://www.youtube.com/watch?v=dQw4w9WgXcQ',
        ),
        'https://i.ytimg.com/vi/dQw4w9WgXcQ/hqdefault.jpg',
      );
    });

    test('creates a thumbnail URL from a short YouTube URL', () {
      expect(
        youtubeThumbnailUrlFromUrl('https://youtu.be/dQw4w9WgXcQ'),
        'https://i.ytimg.com/vi/dQw4w9WgXcQ/hqdefault.jpg',
      );
    });

    test('creates a thumbnail URL from a Shorts URL', () {
      expect(
        youtubeThumbnailUrlFromUrl(
          'https://www.youtube.com/shorts/dQw4w9WgXcQ',
        ),
        'https://i.ytimg.com/vi/dQw4w9WgXcQ/hqdefault.jpg',
      );
    });

    test('returns null for a non-YouTube URL', () {
      expect(
        youtubeThumbnailUrlFromUrl('https://example.com/watch?v=dQw4w9WgXcQ'),
        isNull,
      );
    });

    test('returns null when the video ID is missing', () {
      expect(
        youtubeThumbnailUrlFromUrl('https://www.youtube.com/watch'),
        isNull,
      );
    });
  });
}
