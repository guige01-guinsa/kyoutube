import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:youtube_recipe_search/youtube_recipe_search.dart';

class FakeTransport implements YoutubeSearchTransport {
  FakeTransport(this.response, {this.delay = Duration.zero});
  final YoutubeTransportResponse response;
  final Duration delay;
  int calls = 0;
  @override
  Future<YoutubeTransportResponse> get(YoutubeSearchRequest request) async {
    calls++;
    await Future<void>.delayed(delay);
    return response;
  }
}

Map<String, Object?> canonical({List<Object?>? items}) => {
      'status': 'ok',
      'data': {
        'items': items ?? [item()],
        'nextPageToken': null
      }
    };
Map<String, Object?> item() => {
      'videoId': 'abc',
      'title': 'Pasta',
      'channelTitle': 'Chef',
      'publishedAt': '2026-01-01T00:00:00Z',
      'thumbnailUrl': 'https://img',
      'youtubeUrl': 'https://youtube.test',
      'durationSec': 10
    };
void main() {
  test('parses canonical result and optional duration', () {
    final result = YoutubeSearchPage.fromResponse(canonical()).items.single;
    expect(result.videoId, 'abc');
    expect(result.durationSec, 10);
    final without = item()..['durationSec'] = null;
    expect(YoutubeSearchResult.fromJson(without).durationSec, isNull);
  });
  test('rejects malformed root, data, items and required field types', () {
    for (final raw in [
      null,
      <String, Object?>{},
      {'status': 'ok'},
      {'status': 'ok', 'data': <String, Object?>{}},
      {
        'status': 'ok',
        'data': {
          'items': <Object?>[item()..['title'] = 1]
        }
      }
    ]) {
      expect(() => YoutubeSearchPage.fromResponse(raw),
          throwsA(isA<YoutubeSearchException>()));
    }
  });
  test('safe exception does not contain body, query or key', () {
    const e =
        YoutubeSearchException('youtube_transport_error', httpStatus: 502);
    expect(e.toString(), isNot(contains('secret')));
    expect(e.toString(), isNot(contains('pasta')));
    expect(e.toString(), isNot(contains('https')));
  });
  test('decodes display entities without changing identifiers or URLs', () {
    final raw = item()
      ..['title'] = '김치 &amp; 찌개 &#x1F35A; &#127858; &lt;script&gt;'
      ..['channelTitle'] = '&quot;요리&#39; 채널&gt;'
      ..['videoId'] = 'id&amp;unchanged'
      ..['youtubeUrl'] = 'https://youtube.test/?v=id&amp;unchanged';
    final result = YoutubeSearchResult.fromJson(raw);
    expect(result.title, '김치 & 찌개 🍚 🍲 <script>');
    expect(result.channelTitle, '"요리\' 채널>');
    expect(result.videoId, 'id&amp;unchanged');
    expect(result.youtubeUrl, 'https://youtube.test/?v=id&amp;unchanged');
    expect(decodeYoutubeDisplayText('&broken; &#x110000; &#xZZ;'),
        '&broken; &#x110000; &#xZZ;');
  });
  testWidgets('loading, success, empty, error, submit and opener',
      (tester) async {
    final good = FakeTransport(
        YoutubeTransportResponse(statusCode: 200, body: canonical()),
        delay: const Duration(milliseconds: 20));
    var opened = '';
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: YoutubeRecipeSearchView(
                controller: YoutubeSearchController(YoutubeSearchClient(good)),
                onOpenUrl: (url) async => opened = url,
                debounce: const Duration(days: 1)))));
    await tester.enterText(
        find.byKey(const Key('youtube-search-input')), 'pasta');
    await tester.tap(find.byKey(const Key('youtube-search-submit')));
    await tester.pump();
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    await tester.pump(const Duration(milliseconds: 30));
    expect(find.text('Pasta'), findsOneWidget);
    await tester.tap(find.text('Pasta'));
    expect(opened, 'https://youtube.test');
    final empty = FakeTransport(
        YoutubeTransportResponse(statusCode: 200, body: canonical(items: [])));
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: YoutubeRecipeSearchView(
                controller: YoutubeSearchController(YoutubeSearchClient(empty)),
                onOpenUrl: (_) async {}))));
    await tester.enterText(
        find.byKey(const Key('youtube-search-input')), 'pasta');
    await tester.tap(find.byKey(const Key('youtube-search-submit')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('youtube-search-empty')), findsOneWidget);
    final bad = FakeTransport(const YoutubeTransportResponse(
        statusCode: 502, body: {'errorCode': 'youtube_transport_error'}));
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: YoutubeRecipeSearchView(
                controller: YoutubeSearchController(YoutubeSearchClient(bad)),
                onOpenUrl: (_) async {}))));
    await tester.enterText(
        find.byKey(const Key('youtube-search-input')), 'pasta');
    await tester.tap(find.byKey(const Key('youtube-search-submit')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('youtube-search-error')), findsOneWidget);
  });
  testWidgets('debounce and controller prevent duplicate requests',
      (tester) async {
    final fake = FakeTransport(
        YoutubeTransportResponse(statusCode: 200, body: canonical()),
        delay: const Duration(milliseconds: 30));
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: YoutubeRecipeSearchView(
                controller: YoutubeSearchController(YoutubeSearchClient(fake)),
                onOpenUrl: (_) async {},
                debounce: const Duration(milliseconds: 10)))));
    await tester.enterText(
        find.byKey(const Key('youtube-search-input')), 'pasta');
    await tester.pump(const Duration(milliseconds: 11));
    await tester.tap(find.byKey(const Key('youtube-search-submit')));
    await tester.pump(const Duration(milliseconds: 40));
    expect(fake.calls, 1);
  });
  testWidgets('decoded tag text is rendered as ordinary Flutter text',
      (tester) async {
    final tagged = item()
      ..['title'] = '&lt;script&gt;not executable&lt;/script&gt;';
    final transport = FakeTransport(YoutubeTransportResponse(
        statusCode: 200, body: canonical(items: [tagged])));
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: YoutubeRecipeSearchView(
                controller:
                    YoutubeSearchController(YoutubeSearchClient(transport)),
                onOpenUrl: (_) async {}))));
    await tester.enterText(
        find.byKey(const Key('youtube-search-input')), 'pasta');
    await tester.tap(find.byKey(const Key('youtube-search-submit')));
    await tester.pumpAndSettle();
    expect(find.text('<script>not executable</script>'), findsOneWidget);
  });
}
