import 'package:supabase_flutter/supabase_flutter.dart';

/// Coarse first-party operational reports only. No message/stack/request data.
/// Collection is best effort, authenticated and bounded; local diagnostics remain
/// available for startup/offline failures. Never recursively report its own errors.
class OpsTelemetry {
  OpsTelemetry(
      {required this.isSignedIn, required this.send, DateTime Function()? now})
      : now = now ?? DateTime.now;
  factory OpsTelemetry.forClient(SupabaseClient client) => OpsTelemetry(
        isSignedIn: () =>
            client.auth.currentUser != null &&
            !client.auth.currentUser!.isAnonymous,
        send: (payload) async {
          await client
              .rpc('record_app_operational_event', params: payload)
              .timeout(const Duration(seconds: 2));
        },
      );
  final bool Function() isSignedIn;
  final Future<void> Function(Map<String, dynamic>) send;
  final DateTime Function() now;
  final Map<String, DateTime> _recent = {};
  static const build =
      String.fromEnvironment('APP_BUILD', defaultValue: 'unknown');

  static String sourceCategory(String source) {
    if (['flutter', 'platform', 'zone'].contains(source)) return source;
    if (source.startsWith('firebase') || source.startsWith('fcm')) {
      return 'firebase';
    }
    if (source.startsWith('auth') || source.startsWith('oauth')) return 'auth';
    return 'app';
  }

  static String errorCategory(Object error) {
    // Runtime type is matched locally, never serialized as an arbitrary string.
    switch (error.runtimeType.toString()) {
      case 'TimeoutException':
        return 'timeout';
      case 'SocketException':
      case 'ClientException':
        return 'network';
      case 'FormatException':
        return 'format';
      case 'StateError':
        return 'state';
      default:
        return 'unknown';
    }
  }

  Future<void> report(Object error, String source, bool fatal) async {
    try {
      if (!isSignedIn()) return;
      final time = now();
      _recent.removeWhere(
          (_, value) => time.difference(value) >= const Duration(minutes: 1));
      final category = sourceCategory(source), code = errorCategory(error);
      final key = '$category/$code/$fatal';
      if (_recent.containsKey(key) || _recent.length >= 10) return;
      _recent[key] = time;
      await send({
        'p_source': category,
        'p_code': code,
        'p_fatal': fatal,
        'p_app_build': build
      });
    } catch (_) {/* Observability must never prevent app recovery. */}
  }
}
