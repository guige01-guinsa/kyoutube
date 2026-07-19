import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../config/env.dart';

class OpsErrorEvent {
  const OpsErrorEvent({
    required this.source,
    required this.message,
    required this.timestamp,
    this.stackTrace,
    this.isFatal = false,
  });

  final String source;
  final String message;
  final DateTime timestamp;
  final String? stackTrace;
  final bool isFatal;

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'source': source,
      'message': message,
      'timestamp': timestamp.toIso8601String(),
      'stackTrace': stackTrace,
      'isFatal': isFatal,
    };
  }

  static OpsErrorEvent? fromJson(dynamic value) {
    if (value is! Map<String, dynamic>) {
      return null;
    }

    final timestamp = DateTime.tryParse(value['timestamp'] as String? ?? '');
    if (timestamp == null) {
      return null;
    }

    return OpsErrorEvent(
      source: value['source'] as String? ?? 'unknown',
      message: value['message'] as String? ?? 'Unknown error',
      timestamp: timestamp,
      stackTrace: value['stackTrace'] as String?,
      isFatal: value['isFatal'] as bool? ?? false,
    );
  }
}

class OpsMonitorState {
  const OpsMonitorState({
    required this.appEnv,
    required this.phase,
    required this.isReady,
    required this.recentErrors,
    this.startupError,
  });

  final String appEnv;
  final String phase;
  final bool isReady;
  final String? startupError;
  final List<OpsErrorEvent> recentErrors;

  OpsMonitorState copyWith({
    String? appEnv,
    String? phase,
    bool? isReady,
    String? startupError,
    List<OpsErrorEvent>? recentErrors,
    bool clearStartupError = false,
  }) {
    return OpsMonitorState(
      appEnv: appEnv ?? this.appEnv,
      phase: phase ?? this.phase,
      isReady: isReady ?? this.isReady,
      startupError: clearStartupError ? null : (startupError ?? this.startupError),
      recentErrors: recentErrors ?? this.recentErrors,
    );
  }
}

class OpsMonitorService {
  OpsMonitorService._();

  static const int _maxStoredErrors = 12;
  static const String _recentErrorsKey = 'ops.recent_errors';
  static const String _startupErrorKey = 'ops.startup_error';

  static final ValueNotifier<OpsMonitorState> state =
      ValueNotifier<OpsMonitorState>(
    const OpsMonitorState(
      appEnv: Env.appEnv,
      phase: '초기화 전',
      isReady: false,
      recentErrors: <OpsErrorEvent>[],
    ),
  );

  static final List<RegExp> _sensitivePatterns = <RegExp>[
    RegExp(r'Bearer\s+[A-Za-z0-9\-._~+/]+=*', caseSensitive: false),
    RegExp(
      r'(access|refresh|id)_token\s*[:=]\s*[^\s,;]+',
      caseSensitive: false,
    ),
    RegExp(
      r'(apikey|api_key|service_role_key|anon_key|secret|password)\s*[:=]\s*[^\s,;]+',
      caseSensitive: false,
    ),
    RegExp(r'eyJ[a-zA-Z0-9_-]{10,}\.[a-zA-Z0-9._-]+\.[a-zA-Z0-9._-]+'),
  ];

  static String redact(String input) {
    var output = input;

    for (final pattern in _sensitivePatterns) {
      output = output.replaceAllMapped(pattern, (Match match) {
        final text = match.group(0) ?? '';
        if (text.toLowerCase().startsWith('bearer ')) {
          return 'Bearer [REDACTED]';
        }

        final separatorIndex = text.contains(':')
          ? text.indexOf(':')
          : text.indexOf('=');
        if (separatorIndex > 0) {
          return '${text.substring(0, separatorIndex + 1)} [REDACTED]';
        }

        return '[REDACTED]';
      });
    }

    return output;
  }

  static Future<void> initialize() async {
    final prefs = await SharedPreferences.getInstance();
    final recentErrors = _loadRecentErrors(prefs);
    final startupError = prefs.getString(_startupErrorKey);

    state.value = state.value.copyWith(
      appEnv: Env.appEnv,
      phase: '초기화 전',
      isReady: false,
      startupError: startupError,
      recentErrors: recentErrors,
    );
  }

  static Future<void> markPhase(String phase) async {
    state.value = state.value.copyWith(
      appEnv: Env.appEnv,
      phase: phase,
    );
  }

  static Future<void> markReady() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_startupErrorKey);
    state.value = state.value.copyWith(
      appEnv: Env.appEnv,
      phase: '준비 완료',
      isReady: true,
      clearStartupError: true,
    );
  }

  static Future<void> markStartupFailure({
    required Object error,
    StackTrace? stackTrace,
    String phase = '시작',
  }) async {
    await recordError(
      error,
      source: phase,
      stackTrace: stackTrace,
      isFatal: true,
    );

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_startupErrorKey, redact(error.toString()));
    state.value = state.value.copyWith(
      appEnv: Env.appEnv,
      phase: phase,
      isReady: false,
      startupError: redact(error.toString()),
    );
  }

  static Future<void> recordError(
    Object error, {
    String source = 'unknown',
    StackTrace? stackTrace,
    bool isFatal = false,
  }) async {
    final entry = OpsErrorEvent(
      source: source,
      message: redact(error.toString()),
      timestamp: DateTime.now(),
      stackTrace: stackTrace == null ? null : redact(stackTrace.toString()),
      isFatal: isFatal,
    );

    final updated = <OpsErrorEvent>[entry, ...state.value.recentErrors]
        .take(_maxStoredErrors)
        .toList(growable: false);

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _recentErrorsKey,
      jsonEncode(updated.map((OpsErrorEvent event) => event.toJson()).toList()),
    );

    state.value = state.value.copyWith(
      appEnv: Env.appEnv,
      recentErrors: updated,
    );
  }

  static Future<void> clearRecentErrors() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_recentErrorsKey);
    state.value = state.value.copyWith(
      appEnv: Env.appEnv,
      recentErrors: const <OpsErrorEvent>[],
    );
  }

  static List<OpsErrorEvent> _loadRecentErrors(SharedPreferences prefs) {
    final raw = prefs.getString(_recentErrorsKey);
    if (raw == null || raw.isEmpty) {
      return const <OpsErrorEvent>[];
    }

    final decoded = jsonDecode(raw);
    if (decoded is! List<dynamic>) {
      return const <OpsErrorEvent>[];
    }

    return decoded
        .map(OpsErrorEvent.fromJson)
        .whereType<OpsErrorEvent>()
        .toList(growable: false);
  }
}
