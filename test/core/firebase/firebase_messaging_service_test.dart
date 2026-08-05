import 'package:flutter_test/flutter_test.dart';
import 'package:k_youtube/core/firebase/firebase_messaging_service.dart';

void main() {
  test('FCM diagnostics keep only a short token preview', () {
    const token = 'abcd1234efgh5678ijkl9012';

    final preview = FirebaseMessagingService.tokenPreviewForDiagnostics(token);

    expect(preview, 'abcd…9012');
    expect(preview, isNot(contains(token)));
    expect(FirebaseMessagingService.tokenPreviewForDiagnostics(null), isNull);
    expect(
      FirebaseMessagingService.tokenPreviewForDiagnostics('short'),
      '[MASKED]',
    );
  });
}
