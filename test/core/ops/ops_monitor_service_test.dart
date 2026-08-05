import 'package:flutter_test/flutter_test.dart';
import 'package:k_youtube/core/ops/ops_monitor_service.dart';

void main() {
  test('operations diagnostics redact labelled FCM registration tokens', () {
    const token = 'abcd1234efgh5678ijkl9012';

    final result = OpsMonitorService.redact('registration_token=$token');

    expect(result, isNot(contains(token)));
    expect(result, contains('[REDACTED]'));
  });
}
