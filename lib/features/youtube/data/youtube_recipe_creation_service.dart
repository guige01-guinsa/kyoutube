import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/config/env.dart';
import '../domain/youtube_thumbnail_url.dart';

class YoutubeRecipeDraftInput {
  const YoutubeRecipeDraftInput({
    required this.title,
    required this.channelTitle,
    required this.youtubeUrl,
  });

  final String title;
  final String channelTitle;
  final String youtubeUrl;
}

class YoutubeRecipeCreationResult {
  const YoutubeRecipeCreationResult({
    required this.recipeId,
    required this.raw,
  });

  final String recipeId;
  final Map<String, Object?> raw;
}

class YoutubeRecipeCreationService {
  YoutubeRecipeCreationService({
    http.Client? httpClient,
    SupabaseClient? supabaseClient,
    String? supabaseUrl,
    String? supabaseAnonKey,
  })  : _httpClient = httpClient ?? http.Client(),
        _supabaseClient = supabaseClient ?? Supabase.instance.client,
        _supabaseUrl = supabaseUrl ?? Env.supabaseUrl,
        _supabaseAnonKey = supabaseAnonKey ?? Env.supabaseAnonKey;

  final http.Client _httpClient;
  final SupabaseClient _supabaseClient;
  final String _supabaseUrl;
  final String _supabaseAnonKey;

  Future<YoutubeRecipeCreationResult> createDraftFromYoutube(
    YoutubeRecipeDraftInput input,
  ) async {
    final session = _supabaseClient.auth.currentSession;
    final accessToken = session?.accessToken;

    if (accessToken == null || accessToken.isEmpty) {
      throw const YoutubeRecipeCreationException('로그인이 필요합니다.');
    }

    final title = input.title.trim();
    final channelTitle = input.channelTitle.trim();
    final youtubeUrl = input.youtubeUrl.trim();

    if (title.isEmpty) {
      throw const YoutubeRecipeCreationException('영상 제목이 비어 있습니다.');
    }

    if (youtubeUrl.isEmpty) {
      throw const YoutubeRecipeCreationException('YouTube URL이 비어 있습니다.');
    }

    final uri = Uri.parse(
      '$_supabaseUrl/functions/v1/recipe_api',
    ).replace(
      queryParameters: <String, String>{
        'type': 'creator',
      },
    );

    final response = await _httpClient.post(
      uri,
      headers: <String, String>{
        'apikey': _supabaseAnonKey,
        'Authorization': 'Bearer $accessToken',
        'Content-Type': 'application/json',
      },
      body: jsonEncode(<String, Object?>{
        'title': title,
        'summary': channelTitle.isEmpty
            ? 'YouTube 영상 기반으로 만든 임시 레시피입니다.'
            : 'YouTube 영상 기반으로 만든 임시 레시피입니다.\n채널: $channelTitle',
        'ingredients': <String>[],
        'steps': <String>[
          'YouTube 영상을 참고해 재료와 조리 순서를 정리해 주세요.',
        ],
        'tips': '원본 YouTube 영상을 확인한 뒤 레시피 내용을 보완해 주세요.',
        'youtube_url': youtubeUrl,
        'source_type': 'youtube_import',
        'image_path': youtubeThumbnailUrlFromUrl(youtubeUrl),
        'is_published': false,
      }),
    );

    Object? decoded;
    try {
      decoded = jsonDecode(response.body);
    } catch (_) {
      decoded = null;
    }

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw YoutubeRecipeCreationException(
        _extractErrorMessage(decoded) ??
            '레시피 생성에 실패했습니다. (${response.statusCode})',
      );
    }

    if (decoded is! Map<String, Object?>) {
      throw const YoutubeRecipeCreationException(
        '레시피 생성 응답 형식이 올바르지 않습니다.',
      );
    }

    final data = decoded['data'];

    if (data is! Map<String, Object?>) {
      throw const YoutubeRecipeCreationException(
        '생성된 레시피 데이터가 없습니다.',
      );
    }

    final recipeId = data['id'];

    if (recipeId is! String || recipeId.isEmpty) {
      throw const YoutubeRecipeCreationException(
        '생성된 레시피 ID가 없습니다.',
      );
    }

    return YoutubeRecipeCreationResult(
      recipeId: recipeId,
      raw: data,
    );
  }

  String? _extractErrorMessage(Object? decoded) {
    if (decoded is Map<String, Object?>) {
      final message = decoded['message'];
      if (message is String && message.trim().isNotEmpty) {
        return message;
      }

      final error = decoded['error'];
      if (error is String && error.trim().isNotEmpty) {
        return error;
      }
    }

    return null;
  }
}

class YoutubeRecipeCreationException implements Exception {
  const YoutubeRecipeCreationException(this.message);

  final String message;

  @override
  String toString() => message;
}
