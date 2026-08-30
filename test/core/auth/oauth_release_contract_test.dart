import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:k_youtube/core/auth/oauth_redirect.dart';

void main() {
  test('OAuth redirect URI has the expected Android callback shape', () {
    final uri = Uri.parse(oauthRedirectUri);

    expect(uri.scheme, 'io.supabase.kyoutube');
    expect(uri.host, 'login-callback');
    expect(uri.path, '/');
    expect(googleOAuthQueryParams, const <String, String>{
      'prompt': 'select_account',
    });
  });

  test(
    'AndroidManifest delegates OAuth links to app_links via MainActivity',
    () {
      final manifest = File(
        'android/app/src/main/AndroidManifest.xml',
      ).readAsStringSync();

      final activityIndex = manifest.indexOf('android:name=".MainActivity"');
      final metadataIndex = manifest.indexOf(
        'android:name="flutter_deeplinking_enabled"',
      );

      expect(activityIndex, greaterThanOrEqualTo(0));
      expect(metadataIndex, greaterThan(activityIndex));

      expect(manifest, contains('android:scheme="io.supabase.kyoutube"'));
      expect(manifest, contains('android:host="login-callback"'));
      expect(manifest, contains('android.intent.category.BROWSABLE'));
      expect(manifest, contains('android:value="false"'));
    },
  );

  test('LoginPage uses the shared OAuth redirect URI', () {
    final loginPage = File(
      'lib/features/auth/presentation/login_page.dart',
    ).readAsStringSync();

    expect(loginPage, contains('redirectTo: oauthRedirectUri'));
    expect(loginPage, contains('queryParams: googleOAuthQueryParams'));
    expect(
      loginPage,
      contains('authScreenLaunchMode: LaunchMode.externalApplication'),
    );
    expect(loginPage, contains('emailRedirectTo: oauthRedirectUri'));
    expect(loginPage, contains('OAuthProvider.kakao'));
    expect(loginPage, contains("const Text('카카오로 로그인')"));
  });

  test('local Supabase config keeps Kakao credentials out of source', () {
    final config = File('supabase/config.toml').readAsStringSync();

    expect(config, contains('[auth.external.kakao]'));
    expect(config, contains('client_id = "env(AUTH_KAKAO_CLIENT_ID)"'));
    expect(config, contains('secret = "env(AUTH_KAKAO_SECRET)"'));
  });

  test('release bootstrap delegates OAuth callback handling explicitly', () {
    final app = File('lib/app.dart').readAsStringSync();
    final deepLinkService = File(
      'lib/core/auth/oauth_deep_link_service.dart',
    ).readAsStringSync();

    expect(app, contains('authFlowType: AuthFlowType.pkce'));
    expect(app, contains('detectSessionInUri: false'));
    expect(app, contains('OAuthDeepLinkService'));

    expect(deepLinkService, contains('getSessionFromUrl(uri)'));
    expect(deepLinkService, contains('addPostFrameCallback'));
  });
}
