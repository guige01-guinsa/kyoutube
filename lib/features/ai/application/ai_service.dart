import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/config/env.dart';

class AiSummaryResult {
  const AiSummaryResult({
    required this.summary,
    required this.tips,
    required this.cautions,
    required this.engine,
    required this.degraded,
    required this.errorCode,
  });

  final String summary;
  final List<String> tips;
  final List<String> cautions;
  final String engine;
  final bool degraded;
  final String? errorCode;
}

class AiRecipeDraftResult {
  const AiRecipeDraftResult({
    required this.summary,
    required this.ingredients,
    required this.steps,
    required this.tips,
    required this.cautions,
    required this.engine,
    required this.degraded,
    required this.errorCode,
  });

  final String summary;
  final List<String> ingredients;
  final List<String> steps;
  final List<String> tips;
  final List<String> cautions;
  final String engine;
  final bool degraded;
  final String? errorCode;
}

class AiService {
  static const Duration _timeout = Duration(seconds: 12);
  static const String _endpoint = 'ai_recipe_assistant';
  static const Set<String> _supportedActions = <String>{
    'summarize',
    'regenerate',
    'draft_recipe',
  };

  AiSummaryResult _localFallback(String recipeText) {
    if (recipeText.trim().isEmpty) {
      return const AiSummaryResult(
        summary: '',
        tips: <String>[],
        cautions: <String>[],
        engine: 'local-fallback',
        degraded: true,
        errorCode: null,
      );
    }
    final summary = recipeText.length <= 160
        ? recipeText
        : '${recipeText.substring(0, 160)}...';

    return AiSummaryResult(
      summary: summary,
      tips: const <String>[],
      cautions: const <String>[],
      engine: 'local-fallback',
      degraded: true,
      errorCode: null,
    );
  }

  Uri get _uri => Uri.parse('${Env.supabaseUrl}/functions/v1/$_endpoint');

  Future<AiSummaryResult> summarizeRecipe(
    String recipeText, {
    String action = 'summarize',
    String? title,
    List<String>? ingredients,
    List<String>? steps,
    String? regenerateReason,
    String? previousSummary,
    int? regenerateAttempt,
    String? userFeedbackContext,
  }) async {
    final normalizedAction =
        _supportedActions.contains(action) ? action : 'summarize';
    final normalized = recipeText.trim();
    final normalizedTitle = (title ?? '').trim();
    final normalizedReason = (regenerateReason ?? '').trim();
    final normalizedPreviousSummary = (previousSummary ?? '').trim();
    final normalizedFeedbackContext = (userFeedbackContext ?? '').trim();
    final normalizedIngredients = (ingredients ?? const <String>[])
        .map((String item) => item.trim())
        .where((String item) => item.isNotEmpty)
        .toList();
    final normalizedSteps = (steps ?? const <String>[])
        .map((String item) => item.trim())
        .where((String item) => item.isNotEmpty)
        .toList();

    if (normalized.isEmpty &&
        normalizedTitle.isEmpty &&
        normalizedIngredients.isEmpty &&
        normalizedSteps.isEmpty) {
      return const AiSummaryResult(
        summary: '',
        tips: <String>[],
        cautions: <String>[],
        engine: 'local-fallback',
        degraded: true,
        errorCode: null,
      );
    }

    final accessToken =
        Supabase.instance.client.auth.currentSession?.accessToken;
    try {
      final headers = <String, String>{
        'apikey': Env.supabaseAnonKey,
        'Content-Type': 'application/json',
      };
      if (accessToken != null && accessToken.isNotEmpty) {
        headers['Authorization'] = 'Bearer $accessToken';
      }

      final response = await http
          .post(
            _uri,
            headers: headers,
            body: jsonEncode(<String, dynamic>{
              'action': normalizedAction,
              'title': normalizedTitle,
              'recipeText': normalized,
              'ingredients': normalizedIngredients,
              'steps': normalizedSteps,
              'maxSummaryLength': 180,
              if (normalizedReason.isNotEmpty)
                'regenerate_reason': normalizedReason,
              if (normalizedPreviousSummary.isNotEmpty)
                'previous_summary': normalizedPreviousSummary,
              if (regenerateAttempt != null)
                'regenerate_attempt': regenerateAttempt,
              if (normalizedFeedbackContext.isNotEmpty)
                'user_feedback_context': normalizedFeedbackContext,
            }),
          )
          .timeout(_timeout);

      if (response.statusCode < 200 || response.statusCode >= 300) {
        dynamic decodedError;
        try {
          decodedError = jsonDecode(response.body);
        } catch (_) {
          decodedError = null;
        }
        final errorCode = decodedError is Map<String, dynamic>
            ? (decodedError['code'] as String?)
            : null;
        final fallback = _localFallback(normalized);
        return AiSummaryResult(
          summary: fallback.summary,
          tips: fallback.tips,
          cautions: fallback.cautions,
          engine: fallback.engine,
          degraded: true,
          errorCode: errorCode,
        );
      }

      final decoded = jsonDecode(response.body);
      if (decoded is! Map<String, dynamic>) {
        return _localFallback(normalized);
      }

      final dynamic dataRaw = decoded['data'];
      if (dataRaw is Map<String, dynamic>) {
        final summary = (dataRaw['summary'] ?? '').toString().trim();
        final degraded = dataRaw['degraded'] as bool? ?? false;
        final errorCode = (dataRaw['errorCode'] as String?)?.trim();
        final tips = (dataRaw['tips'] is List)
            ? (dataRaw['tips'] as List)
                .map((dynamic item) => item.toString().trim())
                .where((String item) => item.isNotEmpty)
                .toList()
            : const <String>[];
        final cautions = (dataRaw['cautions'] is List)
            ? (dataRaw['cautions'] as List)
                .map((dynamic item) => item.toString().trim())
                .where((String item) => item.isNotEmpty)
                .toList()
            : const <String>[];
        final engine = (dataRaw['engine'] ?? '').toString().trim();

        if (summary.isNotEmpty) {
          return AiSummaryResult(
            summary: summary,
            tips: tips,
            cautions: cautions,
            engine: engine.isEmpty ? 'unknown' : engine,
            degraded: degraded,
            errorCode: errorCode?.isEmpty == true ? null : errorCode,
          );
        }
      }

      final legacySummary = (decoded['summary'] ?? '').toString().trim();
      if (legacySummary.isNotEmpty) {
        return AiSummaryResult(
          summary: legacySummary,
          tips: const <String>[],
          cautions: const <String>[],
          engine: 'legacy',
          degraded: false,
          errorCode: null,
        );
      }

      return _localFallback(normalized);
    } catch (_) {
      return _localFallback(normalized);
    }
  }

  AiRecipeDraftResult _localDraftFallback({
    required String title,
    required String summary,
    required String youtubeUrl,
  }) {
    final normalizedTitle = title.trim();
    final normalizedSummary = summary.trim();

    final ingredients = <String>[
      if (normalizedTitle.contains('볶음밥')) ...<String>[
        '밥 1공기',
        '식용유 1큰술',
        '간장 1큰술',
        '소금 약간',
      ] else ...<String>[
        '주재료 1인분',
        '양념 재료 약간',
        '식용유 1큰술',
      ],
      if (youtubeUrl.isNotEmpty) '참고 영상: $youtubeUrl',
    ];

    final steps = <String>[
      '재료를 손질하고 필요한 양념을 미리 준비합니다.',
      '중불에서 재료를 볶거나 익히며 간을 맞춥니다.',
      '영상 흐름을 참고해 마무리하고 맛을 조정합니다.',
    ];

    return AiRecipeDraftResult(
      summary: normalizedSummary.isNotEmpty
          ? normalizedSummary
          : (normalizedTitle.isNotEmpty ? '$normalizedTitle 레시피 초안' : '유튜브 기반 레시피 초안'),
      ingredients: ingredients,
      steps: steps,
      tips: const <String>[
        '영상 속 불 세기와 재료 투입 순서를 우선 참고하세요.',
      ],
      cautions: const <String>[
        '영상의 계량이 불명확하면 간은 소량부터 맞추세요.',
      ],
      engine: 'local-draft-fallback',
      degraded: true,
      errorCode: null,
    );
  }

  Future<AiRecipeDraftResult> generateRecipeDraftFromYoutube({
    required String title,
    String? summary,
    required String youtubeUrl,
    String? channelTitle,
  }) async {
    final normalizedTitle = title.trim();
    final normalizedSummary = (summary ?? '').trim();
    final normalizedYoutubeUrl = youtubeUrl.trim();
    final normalizedChannelTitle = (channelTitle ?? '').trim();

    if (normalizedTitle.isEmpty && normalizedYoutubeUrl.isEmpty) {
      return _localDraftFallback(
        title: normalizedTitle,
        summary: normalizedSummary,
        youtubeUrl: normalizedYoutubeUrl,
      );
    }

    final accessToken = Supabase.instance.client.auth.currentSession?.accessToken;
    try {
      final headers = <String, String>{
        'apikey': Env.supabaseAnonKey,
        'Content-Type': 'application/json',
      };
      if (accessToken != null && accessToken.isNotEmpty) {
        headers['Authorization'] = 'Bearer $accessToken';
      }

      final response = await http
          .post(
            _uri,
            headers: headers,
            body: jsonEncode(<String, dynamic>{
              'action': 'draft_recipe',
              'title': normalizedTitle,
              'recipeText': [
                if (normalizedSummary.isNotEmpty) normalizedSummary,
                if (normalizedChannelTitle.isNotEmpty) '채널: $normalizedChannelTitle',
                if (normalizedYoutubeUrl.isNotEmpty) 'YouTube: $normalizedYoutubeUrl',
              ].join('\n'),
              'ingredients': const <String>[],
              'steps': const <String>[],
              'maxSummaryLength': 220,
            }),
          )
          .timeout(_timeout);

      if (response.statusCode < 200 || response.statusCode >= 300) {
        dynamic decodedError;
        try {
          decodedError = jsonDecode(response.body);
        } catch (_) {
          decodedError = null;
        }

        return AiRecipeDraftResult(
          summary: _localDraftFallback(
            title: normalizedTitle,
            summary: normalizedSummary,
            youtubeUrl: normalizedYoutubeUrl,
          ).summary,
          ingredients: _localDraftFallback(
            title: normalizedTitle,
            summary: normalizedSummary,
            youtubeUrl: normalizedYoutubeUrl,
          ).ingredients,
          steps: _localDraftFallback(
            title: normalizedTitle,
            summary: normalizedSummary,
            youtubeUrl: normalizedYoutubeUrl,
          ).steps,
          tips: const <String>[],
          cautions: const <String>[],
          engine: 'local-draft-fallback',
          degraded: true,
          errorCode: decodedError is Map<String, dynamic>
              ? (decodedError['code'] as String?)
              : null,
        );
      }

      final decoded = jsonDecode(response.body);
      if (decoded is! Map<String, dynamic>) {
        return _localDraftFallback(
          title: normalizedTitle,
          summary: normalizedSummary,
          youtubeUrl: normalizedYoutubeUrl,
        );
      }

      final dataRaw = decoded['data'];
      if (dataRaw is! Map<String, dynamic>) {
        return _localDraftFallback(
          title: normalizedTitle,
          summary: normalizedSummary,
          youtubeUrl: normalizedYoutubeUrl,
        );
      }

      final draftSummary = (dataRaw['summary'] ?? '').toString().trim();
      final draftIngredients = (dataRaw['ingredients'] is List)
          ? (dataRaw['ingredients'] as List)
              .map((dynamic item) => item.toString().trim())
              .where((String item) => item.isNotEmpty)
              .toList()
          : const <String>[];
      final draftSteps = (dataRaw['steps'] is List)
          ? (dataRaw['steps'] as List)
              .map((dynamic item) => item.toString().trim())
              .where((String item) => item.isNotEmpty)
              .toList()
          : const <String>[];
      final draftTips = (dataRaw['tips'] is List)
          ? (dataRaw['tips'] as List)
              .map((dynamic item) => item.toString().trim())
              .where((String item) => item.isNotEmpty)
              .toList()
          : const <String>[];
      final draftCautions = (dataRaw['cautions'] is List)
          ? (dataRaw['cautions'] as List)
              .map((dynamic item) => item.toString().trim())
              .where((String item) => item.isNotEmpty)
              .toList()
          : const <String>[];

      if (draftSummary.isEmpty || draftIngredients.isEmpty || draftSteps.isEmpty) {
        return _localDraftFallback(
          title: normalizedTitle,
          summary: normalizedSummary,
          youtubeUrl: normalizedYoutubeUrl,
        );
      }

      return AiRecipeDraftResult(
        summary: draftSummary,
        ingredients: draftIngredients,
        steps: draftSteps,
        tips: draftTips,
        cautions: draftCautions,
        engine: (dataRaw['engine'] ?? 'unknown').toString(),
        degraded: dataRaw['degraded'] as bool? ?? false,
        errorCode: (dataRaw['errorCode'] as String?)?.trim(),
      );
    } catch (_) {
      return _localDraftFallback(
        title: normalizedTitle,
        summary: normalizedSummary,
        youtubeUrl: normalizedYoutubeUrl,
      );
    }
  }

  Future<bool> submitSummaryFeedback({
    required String summary,
    required bool liked,
    String? note,
    String? recipeId,
  }) async {
    final normalizedSummary = summary.trim();
    if (normalizedSummary.isEmpty) {
      return false;
    }

    final accessToken =
        Supabase.instance.client.auth.currentSession?.accessToken;
    final headers = <String, String>{
      'apikey': Env.supabaseAnonKey,
      'Content-Type': 'application/json',
    };
    if (accessToken != null && accessToken.isNotEmpty) {
      headers['Authorization'] = 'Bearer $accessToken';
    }

    try {
      final response = await http
          .post(
            _uri,
            headers: headers,
            body: jsonEncode(<String, dynamic>{
              'action': 'feedback',
              'liked': liked,
              'summary': normalizedSummary,
              'note': (note ?? '').trim(),
              'recipeId': (recipeId ?? '').trim(),
            }),
          )
          .timeout(_timeout);

      return response.statusCode >= 200 && response.statusCode < 300;
    } catch (_) {
      return false;
    }
  }
}
