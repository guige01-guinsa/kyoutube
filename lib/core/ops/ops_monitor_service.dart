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
    this.startupTotalMs,
    this.startupPhaseDurationsMs = const <String, int>{},
    this.lastStartupMeasuredAt,
    this.startupError,
  });

  final String appEnv;
  final String phase;
  final bool isReady;
  final String? startupError;
  final List<OpsErrorEvent> recentErrors;
  final int? startupTotalMs;
  final Map<String, int> startupPhaseDurationsMs;
  final DateTime? lastStartupMeasuredAt;

  OpsMonitorState copyWith({
    String? appEnv,
    String? phase,
    bool? isReady,
    String? startupError,
    List<OpsErrorEvent>? recentErrors,
    int? startupTotalMs,
    Map<String, int>? startupPhaseDurationsMs,
    DateTime? lastStartupMeasuredAt,
    bool clearStartupMetrics = false,
    bool clearStartupError = false,
  }) {
    return OpsMonitorState(
      appEnv: appEnv ?? this.appEnv,
      phase: phase ?? this.phase,
      isReady: isReady ?? this.isReady,
      startupError:
          clearStartupError ? null : (startupError ?? this.startupError),
      recentErrors: recentErrors ?? this.recentErrors,
      startupTotalMs:
          clearStartupMetrics ? null : (startupTotalMs ?? this.startupTotalMs),
      startupPhaseDurationsMs: clearStartupMetrics
          ? const <String, int>{}
          : (startupPhaseDurationsMs ?? this.startupPhaseDurationsMs),
      lastStartupMeasuredAt: clearStartupMetrics
          ? null
          : (lastStartupMeasuredAt ?? this.lastStartupMeasuredAt),
    );
  }
}

class OpsMonitorService {
  OpsMonitorService._();

  static const int _maxStoredErrors = 12;
  static const String _recentErrorsKey = 'ops.recent_errors';
  static const String _startupErrorKey = 'ops.startup_error';
  static const String _startupTotalMsKey = 'ops.startup_total_ms';
  static const String _startupPhaseDurationsKey =
      'ops.startup_phase_durations_ms';
  static const String _lastStartupMeasuredAtKey =
      'ops.last_startup_measured_at';
  static const String _eventCountersKey = 'ops.event_counters';
  static const Duration _duplicateErrorCooldown = Duration(seconds: 15);

  static DateTime? _startupStartedAt;
  static DateTime? _currentPhaseStartedAt;
  static String? _currentPhaseName;
  static Map<String, int> _startupPhaseDurations = <String, int>{};
  static String? _lastErrorSignature;
  static DateTime? _lastErrorRecordedAt;

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

        final separatorIndex =
            text.contains(':') ? text.indexOf(':') : text.indexOf('=');
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
    final startupTotalMs = prefs.getInt(_startupTotalMsKey);
    final startupPhaseDurations = _loadStartupPhaseDurations(prefs);
    final lastStartupMeasuredAt = DateTime.tryParse(
      prefs.getString(_lastStartupMeasuredAtKey) ?? '',
    );

    _startupPhaseDurations = Map<String, int>.from(startupPhaseDurations);
    _startupStartedAt = null;
    _currentPhaseStartedAt = null;
    _currentPhaseName = null;

    state.value = state.value.copyWith(
      appEnv: Env.appEnv,
      phase: '초기화 전',
      isReady: false,
      startupError: startupError,
      recentErrors: recentErrors,
      startupTotalMs: startupTotalMs,
      startupPhaseDurationsMs: startupPhaseDurations,
      lastStartupMeasuredAt: lastStartupMeasuredAt,
    );
  }

  static Future<void> beginStartupRun() async {
    _startupStartedAt = DateTime.now();
    _currentPhaseStartedAt = null;
    _currentPhaseName = null;
    _startupPhaseDurations = <String, int>{};

    state.value = state.value.copyWith(
      appEnv: Env.appEnv,
      phase: '초기화 전',
      isReady: false,
      clearStartupMetrics: true,
    );
  }

  static Future<void> markPhase(String phase) async {
    _finishCurrentPhase();
    _currentPhaseName = phase;
    _currentPhaseStartedAt = DateTime.now();

    state.value = state.value.copyWith(
      appEnv: Env.appEnv,
      phase: phase,
      startupPhaseDurationsMs:
          Map<String, int>.unmodifiable(_startupPhaseDurations),
    );
  }

  static Future<void> markReady() async {
    final prefs = await SharedPreferences.getInstance();
    _finishCurrentPhase();
    final completedAt = DateTime.now();
    final startupTotalMs = _startupStartedAt == null
        ? null
        : completedAt.difference(_startupStartedAt!).inMilliseconds;

    await prefs.remove(_startupErrorKey);
    if (startupTotalMs != null) {
      await prefs.setInt(_startupTotalMsKey, startupTotalMs);
    } else {
      await prefs.remove(_startupTotalMsKey);
    }
    await prefs.setString(
      _startupPhaseDurationsKey,
      jsonEncode(_startupPhaseDurations),
    );
    await prefs.setString(
      _lastStartupMeasuredAtKey,
      completedAt.toIso8601String(),
    );

    state.value = state.value.copyWith(
      appEnv: Env.appEnv,
      phase: '준비 완료',
      isReady: true,
      startupTotalMs: startupTotalMs,
      startupPhaseDurationsMs:
          Map<String, int>.unmodifiable(_startupPhaseDurations),
      lastStartupMeasuredAt: completedAt,
      clearStartupError: true,
    );

    _startupStartedAt = null;
    _currentPhaseStartedAt = null;
    _currentPhaseName = null;
  }

  static Future<void> markStartupFailure({
    required Object error,
    StackTrace? stackTrace,
    String phase = '시작',
  }) async {
    _finishCurrentPhase();

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
      startupPhaseDurationsMs:
          Map<String, int>.unmodifiable(_startupPhaseDurations),
    );

    _startupStartedAt = null;
    _currentPhaseStartedAt = null;
    _currentPhaseName = null;
  }

  static Future<void> recordError(
    Object error, {
    String source = 'unknown',
    StackTrace? stackTrace,
    bool isFatal = false,
  }) async {
    final now = DateTime.now();
    final sanitizedMessage = redact(error.toString());
    final signature = '$source|$sanitizedMessage';
    final lastRecordedAt = _lastErrorRecordedAt;
    if (_lastErrorSignature == signature &&
        lastRecordedAt != null &&
        now.difference(lastRecordedAt) < _duplicateErrorCooldown) {
      return;
    }

    _lastErrorSignature = signature;
    _lastErrorRecordedAt = now;

    final entry = OpsErrorEvent(
      source: source,
      message: sanitizedMessage,
      timestamp: now,
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

  static Future<void> recordEventCounter(
    String key, {
    int delta = 1,
  }) async {
    final normalizedKey = key.trim();
    if (normalizedKey.isEmpty || delta == 0) {
      return;
    }

    final prefs = await SharedPreferences.getInstance();
    final counters = _loadEventCounters(prefs);
    final nextValue = (counters[normalizedKey] ?? 0) + delta;
    counters[normalizedKey] = nextValue < 0 ? 0 : nextValue;
    await prefs.setString(_eventCountersKey, jsonEncode(counters));
  }

  static Future<Map<String, int>> getEventCounters() async {
    final prefs = await SharedPreferences.getInstance();
    return _loadEventCounters(prefs);
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

  static Map<String, int> _loadStartupPhaseDurations(SharedPreferences prefs) {
    final raw = prefs.getString(_startupPhaseDurationsKey);
    if (raw == null || raw.isEmpty) {
      return const <String, int>{};
    }

    final decoded = jsonDecode(raw);
    if (decoded is! Map<String, dynamic>) {
      return const <String, int>{};
    }

    final result = <String, int>{};
    decoded.forEach((String key, dynamic value) {
      if (value is int) {
        result[key] = value;
      } else if (value is num) {
        result[key] = value.toInt();
      }
    });
    return result;
  }

  static Map<String, int> _loadEventCounters(SharedPreferences prefs) {
    final raw = prefs.getString(_eventCountersKey);
    if (raw == null || raw.isEmpty) {
      return <String, int>{};
    }

    final decoded = jsonDecode(raw);
    if (decoded is! Map<String, dynamic>) {
      return <String, int>{};
    }

    final result = <String, int>{};
    decoded.forEach((String key, dynamic value) {
      if (value is int) {
        result[key] = value;
      } else if (value is num) {
        result[key] = value.toInt();
      }
    });
    return result;
  }

  static void _finishCurrentPhase() {
    final phaseName = _currentPhaseName;
    final startedAt = _currentPhaseStartedAt;
    if (phaseName == null || startedAt == null) {
      return;
    }

    _startupPhaseDurations[phaseName] =
        DateTime.now().difference(startedAt).inMilliseconds;
    _currentPhaseName = null;
    _currentPhaseStartedAt = null;
  }
}
