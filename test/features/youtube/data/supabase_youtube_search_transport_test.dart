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
  test('sends GET request to youtube_search with expected parameters',
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
      },
    );
    expect(request.headers['apikey'], 'anon-key');
    expect(request.headers['Authorization'], 'Bearer anon-key');
  });

  test('returns safe transport error when the request fails', () async {
    final client = _FakeClient(
      (_) async => throw Exception('private network failure'),
    );

    final transport = SupabaseYoutubeSearchTransport(
      httpClient: client,
      supabaseUrl: 'https://project.supabase.co',
      supabaseAnonKey: 'anon-key',
    );

    final response = await transport.get(
      const YoutubeSearchRequest(query: 'pasta'),
    );

    expect(response.statusCode, 503);
    expect(
      response.body,
      <String, Object?>{
        'errorCode': 'youtube_transport_error',
      },
    );
  });
}
