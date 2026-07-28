import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import '../../../core/config/env.dart';
import '../../../core/ops/ops_monitor_service.dart';
import '../domain/youtube_search_result.dart';

class YoutubeSearchException implements Exception {
  const YoutubeSearchException({
    required this.code,
    required this.message,
  });

  final String code;
  final String message;

  @override
  String toString() => 'YoutubeSearchException(code: $code, message: $message)';
}

class YoutubeSearchService {
  const YoutubeSearchService();

  static const Duration _timeout = Duration(seconds: 12);
  static const int _maxAttempts = 3;
  static const List<Duration> _retryDelays = <Duration>[
    Duration(milliseconds: 450),
    Duration(milliseconds: 1200),
  ];

  Future<List<YoutubeSearchResult>> search({
    required String query,
    int limit = 5,
    String hl = 'ko',
    String regionCode = 'KR',
  }) async {
    final normalizedQuery = query.trim();
    if (normalizedQuery.isEmpty) {
      return const <YoutubeSearchResult>[];
    }

    final normalizedLimit = limit < 1
        ? 1
        : limit > 10
            ? 10
            : limit;

    final uri = Uri.parse('${Env.supabaseUrl}/functions/v1/youtube_search').replace(
      queryParameters: <String, String>{
        'q': normalizedQuery,
        'limit': normalizedLimit.toString(),
        'hl': hl,
        'regionCode': regionCode,
      },
    );

    final response = await _getWithRetry(uri);

    dynamic decoded;
    try {
      decoded = jsonDecode(response.body);
    } catch (_) {
      decoded = null;
    }

    if (response.statusCode < 200 || response.statusCode >= 300) {
      if (decoded is Map<String, dynamic>) {
        final errorCode =
            (decoded['errorCode'] ?? 'upstream_error').toString();
        await OpsMonitorService.recordEventCounter(
          'youtube.search.failed.$errorCode',
        );
        throw YoutubeSearchException(
          code: errorCode,
          message: (decoded['message'] ?? 'YouTube 검색에 실패했습니다.').toString(),
        );
      }

      await OpsMonitorService.recordEventCounter(
        'youtube.search.failed.upstream_error',
      );

      throw const YoutubeSearchException(
        code: 'upstream_error',
        message: 'YouTube 검색에 실패했습니다.',
      );
    }

    if (decoded is! Map<String, dynamic>) {
      await OpsMonitorService.recordEventCounter(
        'youtube.search.failed.invalid_response',
      );
      throw const YoutubeSearchException(
        code: 'invalid_response',
        message: 'YouTube 검색 응답 형식이 올바르지 않습니다.',
      );
    }

    if ((decoded['status'] ?? '').toString() != 'ok') {
      final errorCode = (decoded['errorCode'] ?? 'upstream_error').toString();
      await OpsMonitorService.recordEventCounter(
        'youtube.search.failed.$errorCode',
      );
      throw YoutubeSearchException(
        code: errorCode,
        message: (decoded['message'] ?? 'YouTube 검색에 실패했습니다.').toString(),
      );
    }

    final data = decoded['data'];
    if (data is! Map<String, dynamic>) {
      return const <YoutubeSearchResult>[];
    }

    final itemsRaw = data['items'];
    if (itemsRaw is! List) {
      return const <YoutubeSearchResult>[];
    }

    final items = itemsRaw
        .whereType<Map<String, dynamic>>()
        .map(YoutubeSearchResult.fromJson)
        .whereType<YoutubeSearchResult>()
        .toList(growable: false);

    await OpsMonitorService.recordEventCounter('youtube.search.success');
    if (items.isEmpty) {
      await OpsMonitorService.recordEventCounter('youtube.search.success.empty');
    } else if (items.length <= 3) {
      await OpsMonitorService.recordEventCounter('youtube.search.success.1_3');
    } else {
      await OpsMonitorService.recordEventCounter('youtube.search.success.4_10');
    }

    return items;
  }

  Future<http.Response> _getWithRetry(Uri uri) async {
    Object? lastError;

    for (var attempt = 1; attempt <= _maxAttempts; attempt++) {
      try {
        final response = await http.get(
          uri,
          headers: <String, String>{
            'apikey': Env.supabaseAnonKey,
          },
        ).timeout(_timeout);

        if (_isRetryableStatus(response.statusCode) && attempt < _maxAttempts) {
          await OpsMonitorService.recordEventCounter(
            'youtube.search.retry.status_${response.statusCode}',
          );
          await Future<void>.delayed(_retryDelays[attempt - 1]);
          continue;
        }

        return response;
      } on TimeoutException catch (error) {
        lastError = error;
        if (attempt >= _maxAttempts) {
          rethrow;
        }
        await OpsMonitorService.recordEventCounter('youtube.search.retry.timeout');
        await Future<void>.delayed(_retryDelays[attempt - 1]);
      } on SocketException catch (error) {
        lastError = error;
        if (attempt >= _maxAttempts) {
          rethrow;
        }
        await OpsMonitorService.recordEventCounter('youtube.search.retry.socket');
        await Future<void>.delayed(_retryDelays[attempt - 1]);
      } on http.ClientException catch (error) {
        lastError = error;
        if (attempt >= _maxAttempts) {
          rethrow;
        }
        await OpsMonitorService.recordEventCounter('youtube.search.retry.client');
        await Future<void>.delayed(_retryDelays[attempt - 1]);
      }
    }

    throw lastError ?? const YoutubeSearchException(
      code: 'unknown_error',
      message: 'YouTube 검색 요청에 실패했습니다.',
    );
  }

  bool _isRetryableStatus(int statusCode) {
    return statusCode == 408 ||
        statusCode == 429 ||
        statusCode == 500 ||
        statusCode == 502 ||
        statusCode == 503 ||
        statusCode == 504;
  }
}
