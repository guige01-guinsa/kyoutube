import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:k_youtube/core/ops/ops_telemetry.dart';

void main() {
  test('reports only allowlisted categories and deduplicates bursts', () async {
    final events = <Map<String, dynamic>>[];
    var time = DateTime.utc(2026, 9, 12);
    final telemetry = OpsTelemetry(
        isSignedIn: () => true,
        send: (e) async {
          events.add(e);
        },
        now: () => time);
    await telemetry.report(
        TimeoutException('private recipe'), 'private email', true);
    await telemetry.report(
        TimeoutException('private recipe'), 'private email', true);
    expect(events, [
      {
        'p_source': 'app',
        'p_code': 'timeout',
        'p_fatal': true,
        'p_app_build': 'unknown'
      }
    ]);
    time = time.add(const Duration(minutes: 1));
    await telemetry.report(
        TimeoutException('private recipe'), 'private email', true);
    expect(events.length, 2);
  });
  test('does not collect before sign-in or surface delivery failures',
      () async {
    var signedIn = false, sends = 0;
    final telemetry = OpsTelemetry(
        isSignedIn: () => signedIn,
        send: (e) async {
          sends++;
          throw StateError('transport');
        });
    await telemetry.report(StateError('secret'), 'flutter', false);
    expect(sends, 0);
    signedIn = true;
    await telemetry.report(StateError('secret'), 'flutter', false);
    expect(sends, 1);
  });
}
