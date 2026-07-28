import '../firebase/firebase_messaging_service.dart';
import 'ops_monitor_service.dart';

class OpsReportFormatter {
  OpsReportFormatter._();

  static String buildStandardReport({
    required OpsMonitorState opsState,
    FirebaseMessagingDebugState? fcmState,
    String? backendStatus,
    String? backendDetails,
    Map<String, int>? eventCounters,
    DateTime? capturedAt,
  }) {
    final timestamp = (capturedAt ?? DateTime.now()).toUtc().toIso8601String();
    final buffer = StringBuffer()
      ..writeln('ops_report_version=1')
      ..writeln('captured_at_utc=$timestamp')
      ..writeln('env=${opsState.appEnv}')
      ..writeln('phase=${opsState.phase}')
      ..writeln('ready=${opsState.isReady}')
      ..writeln('startup_total_ms=${opsState.startupTotalMs ?? '-'}')
      ..writeln(
        'startup_measured_at=${opsState.lastStartupMeasuredAt?.toUtc().toIso8601String() ?? '-'}',
      )
      ..writeln('startup_error=${opsState.startupError == null ? '-' : OpsMonitorService.redact(opsState.startupError!)}')
      ..writeln('recent_error_count=${opsState.recentErrors.length}');

    opsState.startupPhaseDurationsMs.forEach((String phase, int durationMs) {
      buffer.writeln('startup_phase.${_sanitizeKey(phase)}=$durationMs');
    });

    if (fcmState != null) {
      buffer
        ..writeln('fcm_supported=${fcmState.isSupportedPlatform}')
        ..writeln('fcm_initialized=${fcmState.isInitialized}')
        ..writeln('fcm_permission=${fcmState.permissionStatus}')
        ..writeln('fcm_token=${fcmState.token == null ? '-' : '[REDACTED]'}')
        ..writeln('fcm_error=${fcmState.errorMessage == null ? '-' : OpsMonitorService.redact(fcmState.errorMessage!)}');
    }

    if (backendStatus != null) {
      buffer.writeln('backend_check=$backendStatus');
    }
    if (backendDetails != null) {
      buffer.writeln('backend_details=${OpsMonitorService.redact(backendDetails)}');
    }

    if (eventCounters != null && eventCounters.isNotEmpty) {
      int counter(String key) => eventCounters[key] ?? 0;
      final youtubeSearchFailedTotal = eventCounters.entries
          .where((entry) => entry.key.startsWith('youtube.search.failed.'))
          .fold<int>(0, (sum, entry) => sum + entry.value);

      buffer
        ..writeln('kpi.search.submitted.youtube=${counter('search.submitted.youtube')}')
        ..writeln('kpi.search.submitted.public=${counter('search.submitted.public')}')
        ..writeln('kpi.youtube.search.success=${counter('youtube.search.success')}')
        ..writeln('kpi.youtube.search.failed_total=$youtubeSearchFailedTotal')
        ..writeln('kpi.youtube.result.open.clicked=${counter('youtube.result.open.clicked')}')
        ..writeln('kpi.youtube.result.open.success=${counter('youtube.result.open.success')}')
        ..writeln('kpi.youtube.result.open.failed=${counter('youtube.result.open.failed')}')
        ..writeln('kpi.youtube.import.clicked=${counter('youtube.import.clicked')}')
        ..writeln('kpi.youtube.import.completed=${counter('youtube.import.completed')}')
        ..writeln('kpi.youtube.import.failed=${counter('youtube.import.failed')}');
    }

    for (var i = 0; i < opsState.recentErrors.length; i++) {
      final error = opsState.recentErrors[i];
      buffer
        ..writeln('error.$i.timestamp=${error.timestamp.toUtc().toIso8601String()}')
        ..writeln('error.$i.source=${error.source}')
        ..writeln('error.$i.fatal=${error.isFatal}')
        ..writeln('error.$i.message=${OpsMonitorService.redact(error.message)}')
        ..writeln('error.$i.stack=${error.stackTrace == null ? '-' : OpsMonitorService.redact(error.stackTrace!)}');
    }

    return buffer.toString();
  }

  static String _sanitizeKey(String input) {
    return input
        .replaceAll(RegExp(r'\s+'), '_')
        .replaceAll(RegExp(r'[^A-Za-z0-9_가-힣]'), '');
  }
}