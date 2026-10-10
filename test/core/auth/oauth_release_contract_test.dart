import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:k_youtube/core/auth/oauth_redirect.dart';

void main() {
  test('OAuth redirect URI has the expected Android callback shape', () {
    final uri = Uri.parse(oauthRedirectUri);

    expect(uri.scheme, 'io.supabase.kyoutube');
    expect(uri.host, 'login-callback');
    expect(uri.path, '/');
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

  test('LoginPage uses a secure browser tab for Google OAuth callbacks', () {
    final loginPage = File(
      'lib/features/auth/presentation/login_page.dart',
    ).readAsStringSync().replaceAll('\r\n', '\n');

    expect(loginPage, contains('redirectTo: oauthRedirectUri'));
    expect(loginPage,
        isNot(contains("package:google_sign_in/google_sign_in.dart")));
    final pubspec = File('pubspec.yaml').readAsStringSync();
    expect(pubspec, isNot(contains('google_sign_in:')));
    expect(loginPage, isNot(contains('GoogleSignIn(')));
    expect(loginPage, isNot(contains('auth.signInWithIdToken(')));
    expect(loginPage,
        contains('auth.signInWithOAuth(\n        OAuthProvider.google,'));
    final googleSignInStart =
        loginPage.indexOf('Future<void> _signInWithGoogle');
    final kakaoSignInStart = loginPage.indexOf('Future<void> _signInWithKakao');
    final googleSignIn =
        loginPage.substring(googleSignInStart, kakaoSignInStart);
    expect(
      googleSignIn,
      contains(': LaunchMode.inAppBrowserView'),
    );
    expect(googleSignIn, isNot(contains('LaunchMode.externalApplication')));
    expect(
      googleSignIn,
      contains('안전한 로그인 탭으로 열었습니다'),
    );
    expect(loginPage, contains('emailRedirectTo: oauthRedirectUri'));
    expect(loginPage, contains('OAuthProvider.kakao'));
    expect(loginPage, contains("const LocalizedText('Google로 로그인')"));
    expect(loginPage, isNot(contains('_isGoogleLoginVisible')));
    expect(loginPage, contains("const LocalizedText('카카오로 로그인')"));
  });

  test('release features cannot be removed by optional build flags', () {
    final home = File(
      'lib/features/home/presentation/home_page.dart',
    ).readAsStringSync();
    final releaseScript = File(
      'tools/release/run-internal-track-validation.ps1',
    ).readAsStringSync();

    expect(home, contains("Key('video-recipe-entry')"));
    expect(home, contains("context.push(AppRoutes.youtube)"));
    expect(home, isNot(contains('youtubeSearchEnabled')));
    expect(releaseScript, isNot(contains('DisableYoutubeSearch')));
    expect(releaseScript, isNot(contains('EnableYoutubeSearch')));
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
