import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:k_youtube/features/youtube/data/supabase_youtube_search_transport.dart';
import 'package:youtube_recipe_search/youtube_recipe_search.dart';

class _FakeClient extends http.BaseClient {
  _FakeClient(this.handler);

  final Future<http.Response> Function(http.BaseRequest request) handler;

  http.BaseRequest? lastRequest;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    lastRequest = request;

    final response = await handler(request);

    return http.StreamedResponse(
      Stream<List<int>>.value(response.bodyBytes),
      response.statusCode,
      headers: response.headers,
      request: request,
    );
  }
}

void main() {
  const userAccessToken = 'test-user-access-token';

  test('sends authenticated GET request to youtube_search', () async {
    final client = _FakeClient(
      (_) async => http.Response(
        jsonEncode(<String, Object?>{
          'status': 'ok',
          'data': <String, Object?>{
            'items': <Object?>[],
            'nextPageToken': null,
          },
        }),
        200,
      ),
    );

    final transport = SupabaseYoutubeSearchTransport(
      httpClient: client,
      supabaseUrl: 'https://project.supabase.co',
      supabaseAnonKey: 'anon-key',
      accessTokenProvider: () => userAccessToken,
    );

    final response = await transport.get(
      const YoutubeSearchRequest(
        query: 'pasta recipe',
        limit: 99,
      ),
    );

    expect(response.statusCode, 200);

    final request = client.lastRequest!;
    expect(request.method, 'GET');
    expect(request.url.host, 'project.supabase.co');
    expect(request.url.path, '/functions/v1/youtube_search');

    expect(
      request.url.queryParameters,
      <String, String>{
        'q': 'pasta recipe',
        'limit': '10',
        'lang': 'ko',
        'region': 'KR',
      },
    );

    expect(request.headers['apikey'], 'anon-key');
    expect(
      request.headers['Authorization'],
      'Bearer test-user-access-token',
    );
  });

  test('returns safe transport error when authenticated request fails',
      () async {
    final client = _FakeClient(
      (_) async => throw Exception('private network failure'),
    );

    final transport = SupabaseYoutubeSearchTransport(
      httpClient: client,
      supabaseUrl: 'https://project.supabase.co',
      supabaseAnonKey: 'anon-key',
      accessTokenProvider: () => userAccessToken,
    );

    final response = await transport.get(
      const YoutubeSearchRequest(query: 'pasta'),
    );

    expect(response.statusCode, 503);
    expect(
      response.body,
      <String, Object?>{
        'status': 'error',
        'errorCode': 'youtube_transport_error',
        'httpStatus': 503,
      },
    );
  });

  test('returns 401 without a logged-in user access token', () async {
    var requestWasSent = false;

    final client = _FakeClient(
      (_) async {
        requestWasSent = true;
        return http.Response('unexpected request', 500);
      },
    );

    final transport = SupabaseYoutubeSearchTransport(
      httpClient: client,
      supabaseUrl: 'https://project.supabase.co',
      supabaseAnonKey: 'anon-key',
      accessTokenProvider: () => null,
    );

    final response = await transport.get(
      const YoutubeSearchRequest(query: 'pasta'),
    );

    expect(requestWasSent, isFalse);
    expect(response.statusCode, 401);
    expect(
      response.body,
      <String, Object?>{
        'status': 'error',
        'errorCode': 'youtube_auth_required',
        'httpStatus': 401,
      },
    );
  });
  test('supports a future English locale profile without changing auth flow',
      () async {
    final client = _FakeClient(
      (_) async => http.Response(
        jsonEncode(<String, Object?>{
          'status': 'ok',
          'data': <String, Object?>{
            'items': <Object?>[],
            'nextPageToken': null,
          },
        }),
        200,
      ),
    );

    final transport = SupabaseYoutubeSearchTransport(
      httpClient: client,
      supabaseUrl: 'https://project.supabase.co',
      supabaseAnonKey: 'anon-key',
      accessTokenProvider: () => userAccessToken,
      localeProfileProvider: () =>
          YoutubeSearchLocaleProfile.englishUnitedStates,
    );

    await transport.get(
      const YoutubeSearchRequest(query: 'pasta'),
    );

    final request = client.lastRequest!;
    expect(request.url.queryParameters['lang'], 'en');
    expect(request.url.queryParameters['region'], 'US');
  });
}
