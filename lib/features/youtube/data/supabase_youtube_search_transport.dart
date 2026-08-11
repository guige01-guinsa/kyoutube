import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:youtube_recipe_search/youtube_recipe_search.dart';

import '../../../core/config/env.dart';

class SupabaseYoutubeSearchTransport implements YoutubeSearchTransport {
  SupabaseYoutubeSearchTransport({
    http.Client? httpClient,
    String? supabaseUrl,
    String? supabaseAnonKey,
  })  : _httpClient = httpClient ?? http.Client(),
        _supabaseUrl = supabaseUrl ?? Env.supabaseUrl,
        _supabaseAnonKey = supabaseAnonKey ?? Env.supabaseAnonKey;

  final http.Client _httpClient;
  final String _supabaseUrl;
  final String _supabaseAnonKey;

  @override
  Future<YoutubeTransportResponse> get(
    YoutubeSearchRequest request,
  ) async {
    final uri = Uri.parse(
      '$_supabaseUrl/functions/v1/youtube_search',
    ).replace(
      queryParameters: <String, String>{
        'q': request.query.trim(),
        'limit': request.limit.clamp(1, 10).toString(),
      },
    );

    try {
      final response = await _httpClient.get(
        uri,
        headers: <String, String>{
          'apikey': _supabaseAnonKey,
          'Authorization': 'Bearer $_supabaseAnonKey',
        },
      );

      Object? body;
      try {
        body = jsonDecode(response.body);
      } catch (_) {
        body = null;
      }

      return YoutubeTransportResponse(
        statusCode: response.statusCode,
        body: body,
      );
    } catch (_) {
      return const YoutubeTransportResponse(
        statusCode: 503,
        body: <String, Object?>{
          'errorCode': 'youtube_transport_error',
        },
      );
    }
  }
}