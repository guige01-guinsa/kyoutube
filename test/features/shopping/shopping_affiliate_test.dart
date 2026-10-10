import 'package:flutter_test/flutter_test.dart';
import 'package:k_youtube/features/shopping/domain/shopping_affiliate.dart';

void main() {
  test('issued Naver links preserve attribution parameters', () {
    const link = 'https://naver.me/Example1?campaign=a%2Bb&source=creator';
    expect(affiliateUri('naver', link).toString(), link);
  });
  test('only approved program destinations are accepted', () {
    for (final link in [
      'http://naver.me/a',
      'https://naver.me.evil.com/a',
      'https://naver.me@evil.com/a',
      'https://naver.me:443/a',
      'https://search.shopping.naver.com/search/all?query=a',
      'https://localhost/a',
      'javascript:alert(1)',
      'https://naver.me/a\n'
    ]) {
      expect(affiliateUri('naver', link), isNull, reason: link);
    }
    expect(
        affiliateUri('google', 'https://www.google.com/search?q=rice'), isNull);
  });
  test('YouTube route is a tagged content destination, not search', () {
    expect(
        affiliateUri('youtube', 'https://www.youtube.com/watch?v=abcdefghijk'),
        isNotNull);
    expect(affiliateUri('youtube', 'https://youtu.be/abcdefghijk?si=test'),
        isNotNull);
    expect(
        affiliateUri('youtube', 'https://www.youtube.com/shorts/abcdefghijk'),
        isNotNull);
    expect(
        affiliateUri(
            'youtube', 'https://www.youtube.com/results?search_query=rice'),
        isNull);
    expect(affiliateUri('youtube', 'https://youtu.be/short'), isNull);
  });
}
