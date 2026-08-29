import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:k_youtube/features/recipes/application/recipe_enrichment_service.dart';
import 'package:k_youtube/features/recipes/domain/recipe.dart';
import 'package:k_youtube/features/youtube/data/youtube_recipe_context_service.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class _RecordingClient extends http.BaseClient {
  http.BaseRequest? lastRequest;
  String? lastBody;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    lastRequest = request;
    if (request is http.Request) lastBody = request.body;
    return http.StreamedResponse(
      Stream<List<int>>.value(utf8.encode(jsonEncode(<String, Object?>{
        'status': 'ok',
        'data': <String, Object?>{
          'summary': '영상 설명 기반 초안',
          'ingredients': <String>['김치'],
          'steps': <String>['끓인다'],
          'warnings': <String>['영상 확인 필요'],
          'references': <Object?>[],
        },
      }))),
      200,
    );
  }
}

void main() {
  test('public reference request still uses the existing endpoint and contract',
      () async {
    final client = _RecordingClient();
    final service = RecipeEnrichmentService(
      supabaseClient: SupabaseClient('http://localhost', 'test-key'),
      httpClient: client,
      supabaseUrl: 'https://project.supabase.co',
      supabaseAnonKey: 'anon-key',
      accessTokenProvider: () => 'user-token',
    );

    await service.createSuggestion(
      recipe: Recipe(
        id: 'creator-1',
        title: '김치찌개',
        ingredients: const <String>['김치'],
        steps: const <String>['끓인다'],
      ),
      references: <Recipe>[
        Recipe(
          id: 'public-1',
          title: '공공 김치찌개',
          ingredients: const <String>['김치'],
          steps: const <String>['끓인다'],
        ),
      ],
    );

    expect(client.lastRequest!.url.path, '/functions/v1/ai_recipe_assistant');
    final body = jsonDecode(client.lastBody!) as Map<String, dynamic>;
    expect(body.containsKey('references'), isTrue);
    expect(body.containsKey('selectedVideo'), isFalse);
    expect(body['references'][0]['type'], 'public');
  });

  test('YouTube-only request sends selectedVideo without references', () async {
    final client = _RecordingClient();
    final service = RecipeEnrichmentService(
      supabaseClient: SupabaseClient('http://localhost', 'test-key'),
      httpClient: client,
      supabaseUrl: 'https://project.supabase.co',
      supabaseAnonKey: 'anon-key',
      accessTokenProvider: () => 'user-token',
      youtubeContextLoader: (_) async => const YoutubeRecipeContext(
        videoId: 'abc123XYZ00',
        title: '초간단! 집에서 만드는 김치찌개',
        channelTitle: '요리 채널',
        description: '김치와 돼지고기를 끓입니다.',
        youtubeUrl: 'https://www.youtube.com/watch?v=abc123XYZ00',
      ),
    );

    await service.createSuggestionFromSelectedYoutubeVideo(
      recipe: Recipe(
        id: 'recipe-1',
        title: '김치찌개',
        ingredients: const <String>[],
        steps: const <String>[],
        youtubeUrl: 'https://youtu.be/abc123XYZ00',
      ),
    );

    expect(
      client.lastRequest!.url.path,
      '/functions/v1/ai_youtube_recipe_assistant',
    );
    final body = jsonDecode(client.lastBody!) as Map<String, dynamic>;
    expect(body.containsKey('selectedVideo'), isTrue);
    expect(body.containsKey('references'), isFalse);
    expect(body['selectedVideo']['videoId'], 'abc123XYZ00');
    expect(
      (body['selectedVideo']['inferredRecipeTitle'] as String).runes.length,
      lessThanOrEqualTo(10),
    );
  });
}
