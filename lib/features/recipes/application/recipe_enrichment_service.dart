import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/config/env.dart';
import '../../youtube/data/youtube_recipe_context_service.dart';
import '../domain/recipe.dart';
import '../domain/recipe_enrichment_suggestion.dart';

class RecipeEnrichmentException implements Exception {
  const RecipeEnrichmentException(this.message);

  final String message;

  @override
  String toString() => message;
}

class RecipeEnrichmentService {
  RecipeEnrichmentService({
    SupabaseClient? supabaseClient,
    http.Client? httpClient,
    String? supabaseUrl,
    String? supabaseAnonKey,
    String? Function()? accessTokenProvider,
    Future<YoutubeRecipeContext> Function(String youtubeUrl)?
        youtubeContextLoader,
  })  : _supabaseClient = supabaseClient ?? Supabase.instance.client,
        _httpClient = httpClient ?? http.Client(),
        _supabaseUrl = supabaseUrl ?? Env.supabaseUrl,
        _supabaseAnonKey = supabaseAnonKey ?? Env.supabaseAnonKey,
        _accessTokenProvider = accessTokenProvider,
        _youtubeContextLoader = youtubeContextLoader;

  final SupabaseClient _supabaseClient;
  final http.Client _httpClient;
  final String _supabaseUrl;
  final String _supabaseAnonKey;
  final String? Function()? _accessTokenProvider;
  final Future<YoutubeRecipeContext> Function(String youtubeUrl)?
      _youtubeContextLoader;

  Future<RecipeEnrichmentSuggestion> createSuggestion({
    required Recipe recipe,
    required List<Recipe> references,
  }) async {
    if (references.isEmpty) {
      throw const RecipeEnrichmentException(
        '참고할 레시피를 하나 이상 선택해 주세요.',
      );
    }

    final accessToken = _accessTokenProvider?.call() ??
        _supabaseClient.auth.currentSession?.accessToken;

    if (accessToken == null || accessToken.isEmpty) {
      throw const RecipeEnrichmentException('로그인이 필요합니다.');
    }

    final uri = Uri.parse(
      '$_supabaseUrl/functions/v1/ai_recipe_assistant',
    );

    final response = await _httpClient.post(
      uri,
      headers: <String, String>{
        'Content-Type': 'application/json',
        'apikey': _supabaseAnonKey,
        'Authorization': 'Bearer $accessToken',
      },
      body: jsonEncode(
        <String, dynamic>{
          'recipe': _recipePayload(recipe),
          'references': references
              .map(
                (reference) => <String, dynamic>{
                  'type': 'public',
                  'id': reference.id,
                  'title': reference.title,
                  'summary': reference.summary,
                  'ingredients': reference.ingredients,
                  'steps': reference.steps,
                  'youtubeUrl': reference.youtubeUrl,
                },
              )
              .toList(growable: false),
        },
      ),
    );

    Object? decoded;

    try {
      decoded = jsonDecode(response.body);
    } catch (_) {
      decoded = null;
    }

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw RecipeEnrichmentException(
        _extractMessage(decoded) ?? 'AI 레시피 보강을 처리하지 못했습니다.',
      );
    }

    if (decoded is! Map<String, dynamic>) {
      throw const RecipeEnrichmentException(
        'AI 레시피 보강 응답 형식이 올바르지 않습니다.',
      );
    }

    if (decoded['status'] != 'ok') {
      throw RecipeEnrichmentException(
        _extractMessage(decoded) ?? 'AI 레시피 보강을 처리하지 못했습니다.',
      );
    }

    final data = decoded['data'];

    if (data is! Map<String, dynamic>) {
      throw const RecipeEnrichmentException(
        'AI 레시피 보강 결과가 올바르지 않습니다.',
      );
    }

    final suggestion = RecipeEnrichmentSuggestion.fromJson(data);

    if (suggestion.summary.isEmpty ||
        suggestion.ingredients.isEmpty ||
        suggestion.steps.isEmpty) {
      throw const RecipeEnrichmentException(
        'AI가 충분한 레시피 정보를 만들지 못했습니다.',
      );
    }

    return suggestion;
  }

  Future<RecipeEnrichmentSuggestion>
      createSuggestionFromSelectedYoutubeVideo({
    required Recipe recipe,
  }) async {
    final youtubeUrl = (recipe.youtubeUrl ?? '').trim();

    if (youtubeUrl.isEmpty) {
      throw const RecipeEnrichmentException(
        'YouTube 영상 링크가 없는 레시피입니다.',
      );
    }

    final accessToken = _accessTokenProvider?.call() ??
        _supabaseClient.auth.currentSession?.accessToken;

    if (accessToken == null || accessToken.isEmpty) {
      throw const RecipeEnrichmentException('로그인이 필요합니다.');
    }

    final context = await (_youtubeContextLoader?.call(youtubeUrl) ??
        YoutubeRecipeContextService(
          httpClient: _httpClient,
          supabaseClient: _supabaseClient,
        ).loadFromYoutubeUrl(youtubeUrl));

    if (!context.hasDescription) {
      throw const RecipeEnrichmentException(
        '이 영상의 설명란에 레시피 보강에 사용할 정보가 없습니다.',
      );
    }

    final response = await _httpClient.post(
      Uri.parse('$_supabaseUrl/functions/v1/ai_youtube_recipe_assistant'),
      headers: <String, String>{
        'Content-Type': 'application/json',
        'apikey': _supabaseAnonKey,
        'Authorization': 'Bearer $accessToken',
      },
      body: jsonEncode(
        <String, dynamic>{
          'recipe': <String, dynamic>{
            'title': recipe.title,
            'youtubeUrl': youtubeUrl,
          },
          'selectedVideo': <String, dynamic>{
            'videoId': context.videoId,
            'youtubeUrl': context.youtubeUrl,
            'originalTitle': context.title,
            'inferredRecipeTitle': _inferRecipeTitle(
              recipe.title,
              context.title,
            ),
            'channelName': context.channelTitle,
            'description': context.description,
          },
        },
      ),
    );

    Object? decoded;

    try {
      decoded = jsonDecode(response.body);
    } catch (_) {
      decoded = null;
    }

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw RecipeEnrichmentException(
        _extractMessage(decoded) ?? '영상 설명란 기반 AI 보강을 처리하지 못했습니다.',
      );
    }

    if (decoded is! Map<String, dynamic>) {
      throw const RecipeEnrichmentException(
        '영상 설명란 AI 보강 응답 형식이 올바르지 않습니다.',
      );
    }

    if (decoded['status'] != 'ok') {
      throw RecipeEnrichmentException(
        _extractMessage(decoded) ?? '영상 설명란 AI 보강을 처리하지 못했습니다.',
      );
    }

    final data = decoded['data'];

    if (data is! Map<String, dynamic>) {
      throw const RecipeEnrichmentException(
        '영상 설명란 AI 보강 결과가 올바르지 않습니다.',
      );
    }

    final suggestion = RecipeEnrichmentSuggestion.fromJson(data);

    if (suggestion.summary.isEmpty ||
        suggestion.ingredients.isEmpty ||
        suggestion.steps.isEmpty) {
      throw const RecipeEnrichmentException(
        '영상 설명란에서 충분한 레시피 정보를 찾지 못했습니다.',
      );
    }

    return suggestion;
  }

  String _inferRecipeTitle(String recipeTitle, String videoTitle) {
    var value = recipeTitle.trim().isNotEmpty
        ? recipeTitle.trim()
        : videoTitle.trim();
    value = value
        .replaceAll(RegExp(r'[\[\(【].*?[\]\)】]'), ' ')
        .replaceAll(
          RegExp(
            r'(초간단|대박|역대급|무조건|강력추천|필수시청|레전드|맛있는|만드는|만들기|황금레시피|레시피)',
          ),
          ' ',
        )
        .replaceAll(RegExp(r'[^가-힣A-Za-z0-9\s]'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();

    if (value.isEmpty) {
      value = '영상레시피';
    }

    final words = value.split(' ').where((word) => word.isNotEmpty).toList();
    if (words.length > 1) {
      final lastTwo = words.sublist(words.length - 2).join(' ');
      value = lastTwo.runes.length <= 10 ? lastTwo : words.last;
    }

    return String.fromCharCodes(value.runes.take(10));
  }

  Map<String, dynamic> _recipePayload(Recipe recipe) {
    return <String, dynamic>{
      'title': recipe.title,
      'summary': recipe.summary,
      'ingredients': recipe.ingredients,
      'steps': recipe.steps,
      'tips': recipe.tips,
      'youtubeUrl': recipe.youtubeUrl,
    };
  }

  String? _extractMessage(Object? payload) {
    if (payload is! Map<String, dynamic>) {
      return null;
    }

    final message = payload['message'];

    if (message is String && message.trim().isNotEmpty) {
      return message.trim();
    }

    return null;
  }
}
