import 'package:flutter_test/flutter_test.dart';
import 'package:k_youtube/core/auth/oauth_callback_handler.dart';

void main() {
  test('ignores non OAuth deep links', () async {
    final handler = OAuthCallbackHandler(
      exchangeCode: (_) async {},
    );

    final result = await handler.handle(
      Uri.parse('https://example.com/callback?code=test'),
    );

    expect(result.outcome, OAuthCallbackOutcome.ignored);
  });

  test('reports missing OAuth authorization code', () async {
    final handler = OAuthCallbackHandler(
      exchangeCode: (_) async {},
    );

    final result = await handler.handle(
      Uri.parse('io.supabase.kyoutube://login-callback'),
    );

    expect(result.outcome, OAuthCallbackOutcome.missingCode);
  });

  test('reports provider callback error without exchanging code', () async {
    var exchanges = 0;

    final handler = OAuthCallbackHandler(
      exchangeCode: (_) async {
        exchanges += 1;
      },
    );

    final result = await handler.handle(
      Uri.parse(
        'io.supabase.kyoutube://login-callback?error=access_denied',
      ),
    );

    expect(result.outcome, OAuthCallbackOutcome.providerError);
    expect(result.providerError, 'access_denied');
    expect(exchanges, 0);
  });

  test('exchanges each OAuth authorization code once', () async {
    final handledCodes = <String>[];

    final handler = OAuthCallbackHandler(
      exchangeCode: (String code) async {
        handledCodes.add(code);
      },
    );

    final uri = Uri.parse(
      'io.supabase.kyoutube://login-callback?code=one-time-code',
    );

    final first = await handler.handle(uri);
    final duplicate = await handler.handle(uri);

    expect(first.outcome, OAuthCallbackOutcome.exchanged);
    expect(duplicate.outcome, OAuthCallbackOutcome.duplicate);
    expect(handledCodes, <String>['one-time-code']);
  });

  test('reports authorization code exchange failure', () async {
    final handler = OAuthCallbackHandler(
      exchangeCode: (_) async {
        throw StateError('exchange failed');
      },
    );

    final result = await handler.handle(
      Uri.parse(
        'io.supabase.kyoutube://login-callback?code=failing-code',
      ),
    );

    expect(result.outcome, OAuthCallbackOutcome.exchangeFailed);
    expect(result.error, isA<StateError>());
  });
}
