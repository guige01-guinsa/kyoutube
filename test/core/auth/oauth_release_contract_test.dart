import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:k_youtube/core/auth/oauth_redirect.dart';

void main() {
  test('OAuth redirect URI has the expected Android callback shape', () {
    final uri = Uri.parse(oauthRedirectUri);

    expect(uri.scheme, 'io.supabase.kyoutube');
    expect(uri.host, 'login-callback');
    expect(uri.path, isEmpty);
    expect(
      googleOAuthQueryParams,
      const <String, String>{'prompt': 'select_account'},
    );
  });

  test('AndroidManifest delegates OAuth deep links to app_links', () {
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
      contains('android.intent.category.BROWSABLE'),
    );
    expect(
      manifest,
      contains('android:name="flutter_deeplinking_enabled"'),
    );
    expect(manifest, contains('android:value="false"'));
  });

  test('LoginPage uses the shared OAuth redirect URI', () {
    final loginPage = File(
      'lib/features/auth/presentation/login_page.dart',
    ).readAsStringSync();

    expect(loginPage, contains('redirectTo: oauthRedirectUri'));
    expect(loginPage, contains('queryParams: googleOAuthQueryParams'));
    expect(loginPage, contains('emailRedirectTo: oauthRedirectUri'));
  });

  test('release bootstrap delegates OAuth callback handling explicitly', () {
    final app = File('lib/app.dart').readAsStringSync();

    expect(app, contains('authFlowType: AuthFlowType.pkce'));
    expect(app, contains('detectSessionInUri: false'));
    expect(app, contains('OAuthDeepLinkService'));
  });
}
