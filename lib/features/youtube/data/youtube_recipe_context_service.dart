import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/config/env.dart';

class YoutubeRecipeContext {
  const YoutubeRecipeContext({
    required this.videoId,
    required this.title,
    required this.channelTitle,
    required this.description,
    required this.youtubeUrl,
  });

  final String videoId;
  final String title;
  final String channelTitle;
  final String description;
  final String youtubeUrl;

  factory YoutubeRecipeContext.fromJson(Map<String, dynamic> json) {
    return YoutubeRecipeContext(
      videoId: (json['videoId'] as String? ?? '').trim(),
      title: (json['title'] as String? ?? '').trim(),
      channelTitle: (json['channelTitle'] as String? ?? '').trim(),
      description: (json['description'] as String? ?? '').trim(),
      youtubeUrl: (json['youtubeUrl'] as String? ?? '').trim(),
    );
  }

  bool get hasDescription => description.isNotEmpty;
}

class YoutubeRecipeContextException implements Exception {
  const YoutubeRecipeContextException(this.message);

  final String message;

  @override
  String toString() => message;
}

class YoutubeRecipeContextService {
  YoutubeRecipeContextService({
    http.Client? httpClient,
    SupabaseClient? supabaseClient,
  })  : _httpClient = httpClient ?? http.Client(),
        _supabaseClient = supabaseClient ?? Supabase.instance.client;

  final http.Client _httpClient;
  final SupabaseClient _supabaseClient;

  Future<YoutubeRecipeContext> loadFromYoutubeUrl(String youtubeUrl) async {
    final session = _supabaseClient.auth.currentSession;

    if (session == null) {
      throw const YoutubeRecipeContextException('로그인이 필요합니다.');
    }

    final response = await _httpClient.post(
      Uri.parse('${Env.supabaseUrl}/functions/v1/youtube_recipe_context'),
      headers: <String, String>{
        'Content-Type': 'application/json',
        'apikey': Env.supabaseAnonKey,
        'Authorization': 'Bearer ${session.accessToken}',
      },
      body: jsonEncode(<String, String>{
        'youtubeUrl': youtubeUrl.trim(),
      }),
    );

    Object? decoded;

    try {
      decoded = jsonDecode(response.body);
    } catch (_) {
      decoded = null;
    }

    if (decoded is! Map<String, dynamic>) {
      throw const YoutubeRecipeContextException(
        'YouTube 영상 정보를 처리하지 못했습니다.',
      );
    }

    if (response.statusCode < 200 || response.statusCode >= 300) {
      final message = decoded['message'];

      throw YoutubeRecipeContextException(
        message is String && message.trim().isNotEmpty
            ? message.trim()
            : 'YouTube 영상 설명란을 불러오지 못했습니다.',
      );
    }

    final data = decoded['data'];

    if (decoded['status'] != 'ok' || data is! Map<String, dynamic>) {
      throw const YoutubeRecipeContextException(
        'YouTube 영상 설명란 응답이 올바르지 않습니다.',
      );
    }

    final context = YoutubeRecipeContext.fromJson(data);

    if (context.videoId.isEmpty || context.title.isEmpty) {
      throw const YoutubeRecipeContextException(
        'YouTube 영상 정보가 충분하지 않습니다.',
      );
    }

    return context;
  }
}
