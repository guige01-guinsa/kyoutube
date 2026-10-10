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
          'title': '김치찌개',
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

class _QuotaClient extends http.BaseClient {
  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) {
    return Future<http.StreamedResponse>.value(
      http.StreamedResponse(
        Stream<List<int>>.value(
          utf8.encode(
            jsonEncode(<String, Object?>{
              'status': 'error',
              'code': 'ai_upstream_quota_exceeded',
              'message': 'AI 요청 한도에 도달했습니다.',
            }),
          ),
        ),
        429,
      ),
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
      outputLocale: 'es-419',
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
    expect(body['outputLocale'], 'es-419');
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
        durationSec: 179,
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
    expect(body['outputLocale'], 'ko-KR');
    expect(body['selectedVideo']['videoId'], 'abc123XYZ00');
    expect(body['selectedVideo']['durationSec'], 179);
    expect(
      (body['selectedVideo']['inferredRecipeTitle'] as String).runes.length,
      lessThanOrEqualTo(10),
    );
  });

  test('video analysis uses its protected endpoint and retains video identity',
      () async {
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
        durationSec: 179,
      ),
    );

    await service.createSuggestionFromSelectedYoutubeVideo(
      videoAnalysis: true,
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
      '/functions/v1/ai_youtube_video_assistant',
    );
    final body = jsonDecode(client.lastBody!) as Map<String, dynamic>;
    expect(body.containsKey('selectedVideo'), isTrue);
    expect(body.containsKey('references'), isFalse);
    expect(body['outputLocale'], 'ko-KR');
    expect(body['selectedVideo']['videoId'], 'abc123XYZ00');
    expect(body['selectedVideo']['durationSec'], 179);
    expect(
      (body['selectedVideo']['inferredRecipeTitle'] as String).runes.length,
      lessThanOrEqualTo(10),
    );
  });

  test('English YouTube request keeps an English title and sends en-US',
      () async {
    final client = _RecordingClient();
    final service = RecipeEnrichmentService(
      supabaseClient: SupabaseClient('http://localhost', 'test-key'),
      httpClient: client,
      supabaseUrl: 'https://project.supabase.co',
      supabaseAnonKey: 'anon-key',
      accessTokenProvider: () => 'user-token',
      youtubeContextLoader: (_) async => const YoutubeRecipeContext(
        videoId: 'abc123XYZ00',
        title: 'Easy One Pot Chicken Alfredo Dinner',
        channelTitle: 'Home Kitchen',
        description: 'Ingredients and directions',
        youtubeUrl: 'https://www.youtube.com/watch?v=abc123XYZ00',
        durationSec: 420,
      ),
    );

    await service.createSuggestionFromSelectedYoutubeVideo(
      recipe: Recipe(
        id: 'recipe-en-1',
        title: 'One Pot Chicken Alfredo',
        ingredients: const <String>[],
        steps: const <String>[],
        youtubeUrl: 'https://youtu.be/abc123XYZ00',
      ),
      outputLocale: 'en-US',
    );

    final body = jsonDecode(client.lastBody!) as Map<String, dynamic>;
    expect(body['outputLocale'], 'en-US');
    expect(
      body['selectedVideo']['inferredRecipeTitle'],
      'One Pot Chicken Alfredo',
    );
  });

  test('English draft request removes Korean promotional title words',
      () async {
    final client = _RecordingClient();
    final service = RecipeEnrichmentService(
      supabaseClient: SupabaseClient('http://localhost', 'test-key'),
      httpClient: client,
      supabaseUrl: 'https://project.supabase.co',
      supabaseAnonKey: 'anon-key',
      accessTokenProvider: () => 'user-token',
      youtubeContextLoader: (_) async => const YoutubeRecipeContext(
        videoId: 'abc123XYZ00',
        title: '초간단 황금레시피 Bibimbap',
        channelTitle: 'Test kitchen',
        description: 'Ingredients and steps',
        youtubeUrl: 'https://youtu.be/abc123XYZ00',
        durationSec: 240,
      ),
    );
    await service.createSuggestionFromSelectedYoutubeVideo(
      recipe: Recipe(
          id: 'test',
          title: '초간단 황금레시피 Bibimbap',
          ingredients: const [],
          steps: const [],
          youtubeUrl: 'https://youtu.be/abc123XYZ00'),
      outputLocale: 'en-US',
    );
    final body = jsonDecode(client.lastBody!) as Map<String, dynamic>;
    expect(body['selectedVideo']['inferredRecipeTitle'], 'Bibimbap');
    expect(body['selectedVideo']['originalTitle'], '초간단 황금레시피 Bibimbap');
  });

  test('YouTube request sends pasted transcript when provided', () async {
    final client = _RecordingClient();
    final service = RecipeEnrichmentService(
      supabaseClient: SupabaseClient('http://localhost', 'test-key'),
      httpClient: client,
      supabaseUrl: 'https://project.supabase.co',
      supabaseAnonKey: 'anon-key',
      accessTokenProvider: () => 'user-token',
      youtubeContextLoader: (_) async => const YoutubeRecipeContext(
        videoId: 'abc123XYZ00',
        title: '집에서 만드는 김치찌개',
        channelTitle: '요리 채널',
        description: '',
        youtubeUrl: 'https://www.youtube.com/watch?v=abc123XYZ00',
        durationSec: 179,
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
      transcript: '김치를 썰고 돼지고기와 함께 끓입니다.',
      recipeNameHint: '돼지고기 김치찌개',
      ingredientHints: '김치, 돼지고기, 두부, 대파',
    );

    final body = jsonDecode(client.lastBody!) as Map<String, dynamic>;
    expect(
      body['selectedVideo']['transcript'],
      '김치를 썰고 돼지고기와 함께 끓입니다.',
    );
    expect(body['selectedVideo']['recipeNameHint'], '돼지고기 김치찌개');
    expect(body['selectedVideo']['ingredientHints'], '김치, 돼지고기, 두부, 대파');
  });

  test('rejects a selected YouTube video longer than sixty minutes', () async {
    final service = RecipeEnrichmentService(
      supabaseClient: SupabaseClient('http://localhost', 'test-key'),
      httpClient: _RecordingClient(),
      supabaseUrl: 'https://project.supabase.co',
      supabaseAnonKey: 'anon-key',
      accessTokenProvider: () => 'user-token',
      youtubeContextLoader: (_) async => const YoutubeRecipeContext(
        videoId: 'abc123XYZ00',
        title: '긴 김치찌개 영상',
        channelTitle: '요리 채널',
        description: '김치찌개 설명',
        youtubeUrl: 'https://www.youtube.com/watch?v=abc123XYZ00',
        durationSec: 3601,
      ),
    );

    await expectLater(
      service.createSuggestionFromSelectedYoutubeVideo(
        recipe: Recipe(
          id: 'recipe-1',
          title: '김치찌개',
          ingredients: const <String>[],
          steps: const <String>[],
          youtubeUrl: 'https://youtu.be/abc123XYZ00',
        ),
      ),
      throwsA(
        isA<RecipeEnrichmentException>().having(
          (error) => error.message,
          'message',
          contains('60분 이내'),
        ),
      ),
    );
  });

  test('preserves an AI usage limit error code for the presentation layer',
      () async {
    final service = RecipeEnrichmentService(
      supabaseClient: SupabaseClient('http://localhost', 'test-key'),
      httpClient: _QuotaClient(),
      supabaseUrl: 'https://project.supabase.co',
      supabaseAnonKey: 'anon-key',
      accessTokenProvider: () => 'user-token',
      youtubeContextLoader: (_) async => const YoutubeRecipeContext(
        videoId: 'abc123XYZ00',
        title: '김치찌개',
        channelTitle: '요리 채널',
        description: '김치찌개 설명',
        youtubeUrl: 'https://www.youtube.com/watch?v=abc123XYZ00',
        durationSec: 179,
      ),
    );

    await expectLater(
      service.createSuggestionFromSelectedYoutubeVideo(
        recipe: Recipe(
          id: 'recipe-1',
          title: '김치찌개',
          ingredients: const <String>[],
          steps: const <String>[],
          youtubeUrl: 'https://youtu.be/abc123XYZ00',
        ),
      ),
      throwsA(
        isA<RecipeEnrichmentException>().having(
            (error) => error.code, 'code', 'ai_upstream_quota_exceeded'),
      ),
    );
  });
}
