import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:k_youtube/core/auth/oauth_redirect.dart';

void main() {
  test('OAuth redirect URI has the expected Android callback shape', () {
    final uri = Uri.parse(oauthRedirectUri);

    expect(uri.scheme, 'io.supabase.kyoutube');
    expect(uri.host, 'login-callback');
    expect(uri.path, isEmpty);
  });

  test('AndroidManifest declares the OAuth callback intent filter', () {
    final manifest = File(
      'android/app/src/main/AndroidManifest.xml',
    ).readAsStringSync();

    expect(
      manifest,
      contains('android:scheme="io.supabase.kyoutube"'),
    );

    expect(
      manifest,
      contains('android:host="login-callback"'),
    );

    expect(
      manifest,
      contains('android.intent.action.VIEW'),
    );

    expect(
      manifest,
      contains('android.intent.category.BROWSABLE'),
    );
  });

  test('LoginPage uses the shared redirect URI for OAuth and email signup', () {
    final loginPage = File(
      'lib/features/auth/presentation/login_page.dart',
    ).readAsStringSync();

    expect(loginPage, contains('redirectTo: oauthRedirectUri'));
    expect(loginPage, contains('emailRedirectTo: oauthRedirectUri'));
  });

  test('release bootstrap explicitly configures PKCE auth flow', () {
    final app = File('lib/app.dart').readAsStringSync();

    expect(app, contains('authFlowType: AuthFlowType.pkce'));
  });
}
