import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:youtube_recipe_search/youtube_recipe_search.dart';

import '../../../core/config/env.dart';

class YoutubeSearchLocaleProfile {
  const YoutubeSearchLocaleProfile({
    required this.languageCode,
    required this.regionCode,
  });

  final String languageCode;
  final String regionCode;

  static const korean = YoutubeSearchLocaleProfile(
    languageCode: 'ko',
    regionCode: 'KR',
  );

  static const englishUnitedStates = YoutubeSearchLocaleProfile(
    languageCode: 'en',
    regionCode: 'US',
  );
}

class SupabaseYoutubeSearchTransport implements YoutubeSearchTransport {
  SupabaseYoutubeSearchTransport({
    http.Client? httpClient,
    String? supabaseUrl,
    String? supabaseAnonKey,
    String? Function()? accessTokenProvider,
    YoutubeSearchLocaleProfile Function()? localeProfileProvider,
  })  : _httpClient = httpClient ?? http.Client(),
        _supabaseUrl = supabaseUrl ?? Env.supabaseUrl,
        _supabaseAnonKey = supabaseAnonKey ?? Env.supabaseAnonKey,
        _accessTokenProvider = accessTokenProvider ??
            (() {
              try {
                return Supabase
                    .instance.client.auth.currentSession?.accessToken;
              } catch (_) {
                return null;
              }
            }),
        _localeProfileProvider =
            localeProfileProvider ?? (() => YoutubeSearchLocaleProfile.korean);

  final http.Client _httpClient;
  final String _supabaseUrl;
  final String _supabaseAnonKey;
  final String? Function() _accessTokenProvider;
  final YoutubeSearchLocaleProfile Function() _localeProfileProvider;

  @override
  Future<YoutubeTransportResponse> get(
    YoutubeSearchRequest request,
  ) async {
    final accessToken = _accessTokenProvider()?.trim();

    if (accessToken == null || accessToken.isEmpty) {
      return const YoutubeTransportResponse(
        statusCode: 401,
        body: <String, Object?>{
          'status': 'error',
          'errorCode': 'youtube_auth_required',
          'httpStatus': 401,
        },
      );
    }

    final locale = _localeProfileProvider();

    final uri = Uri.parse(
      '$_supabaseUrl/functions/v1/youtube_search',
    ).replace(
      queryParameters: <String, String>{
        'q': request.query.trim(),
        'limit': request.limit.clamp(1, 10).toString(),
        'lang': locale.languageCode,
        'region': locale.regionCode,
      },
    );

    try {
      final response = await _httpClient.get(
        uri,
        headers: <String, String>{
          'apikey': _supabaseAnonKey,
          'Authorization': 'Bearer $accessToken',
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
          'status': 'error',
          'errorCode': 'youtube_transport_error',
          'httpStatus': 503,
        },
      );
    }
  }
}
