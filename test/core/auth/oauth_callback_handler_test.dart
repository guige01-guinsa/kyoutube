import 'package:flutter_test/flutter_test.dart';
import 'package:k_youtube/core/auth/oauth_callback_handler.dart';

void main() {
  test('ignores non OAuth deep links', () async {
    final handler = OAuthCallbackHandler(
      exchangeSessionFromUri: (_) async => null,
    );

    final result = await handler.handle(
      Uri.parse('https://example.com/callback?code=test'),
    );

    expect(result.outcome, OAuthCallbackOutcome.ignored);
  });

  test('reports missing OAuth authorization code', () async {
    final handler = OAuthCallbackHandler(
      exchangeSessionFromUri: (_) async => null,
    );

    final result = await handler.handle(
      Uri.parse('io.supabase.kyoutube://login-callback'),
    );

    expect(result.outcome, OAuthCallbackOutcome.missingCode);
  });

  test('reports provider callback error without session exchange', () async {
    var exchanges = 0;

    final handler = OAuthCallbackHandler(
      exchangeSessionFromUri: (_) async {
        exchanges += 1;
        return null;
      },
    );

    final result = await handler.handle(
      Uri.parse('io.supabase.kyoutube://login-callback?error=access_denied'),
    );

    expect(result.outcome, OAuthCallbackOutcome.providerError);
    expect(result.providerError, 'access_denied');
    expect(exchanges, 0);
  });

  test('returns recovery redirect type from recovery-aware exchange', () async {
    final handler = OAuthCallbackHandler(
      exchangeSessionFromUri: (_) async => 'passwordRecovery',
    );

    final result = await handler.handle(
      Uri.parse('io.supabase.kyoutube://login-callback?code=recovery-code'),
    );

    expect(result.outcome, OAuthCallbackOutcome.exchanged);
    expect(result.redirectType, 'passwordRecovery');
  });

  test(
    'deduplicates successful callback but retries failed callback',
    () async {
      var attempts = 0;

      final handler = OAuthCallbackHandler(
        exchangeSessionFromUri: (_) async {
          attempts += 1;

          if (attempts == 1) {
            throw StateError('temporary exchange failure');
          }

          return null;
        },
      );

      final uri = Uri.parse(
        'io.supabase.kyoutube://login-callback?code=retry-code',
      );

      final first = await handler.handle(uri);
      final retry = await handler.handle(uri);
      final duplicate = await handler.handle(uri);

      expect(first.outcome, OAuthCallbackOutcome.exchangeFailed);
      expect(retry.outcome, OAuthCallbackOutcome.exchanged);
      expect(duplicate.outcome, OAuthCallbackOutcome.duplicate);
      expect(attempts, 2);
    },
  );
}
