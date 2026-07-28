import 'package:flutter/foundation.dart';

class Env {
  static const String appEnv =
      String.fromEnvironment(
        'APP_ENV',
        defaultValue: kReleaseMode ? 'production' : 'unset',
      );

  static const String _supabaseUrl =
      String.fromEnvironment('SUPABASE_URL', defaultValue: '');
  static const String _supabaseAnonKey =
      String.fromEnvironment('SUPABASE_ANON_KEY', defaultValue: '');

  static const String _localSupabaseUrl =
      String.fromEnvironment('SUPABASE_URL_LOCAL', defaultValue: '');
  static const String _localSupabaseAnonKey =
      String.fromEnvironment('SUPABASE_ANON_KEY_LOCAL', defaultValue: '');

  static const String _stagingSupabaseUrl =
      String.fromEnvironment('SUPABASE_URL_STAGING', defaultValue: '');
  static const String _stagingSupabaseAnonKey =
      String.fromEnvironment('SUPABASE_ANON_KEY_STAGING', defaultValue: '');

  static const String _productionSupabaseUrl =
      String.fromEnvironment('SUPABASE_URL_PRODUCTION', defaultValue: '');
  static const String _productionSupabaseAnonKey =
      String.fromEnvironment('SUPABASE_ANON_KEY_PRODUCTION', defaultValue: '');

  static const bool googleOAuthEnabled =
      bool.fromEnvironment('GOOGLE_OAUTH_ENABLED', defaultValue: false);
    static const bool googleOAuthConfigured =
      bool.fromEnvironment('GOOGLE_OAUTH_CONFIGURED', defaultValue: true);
  static const bool kakaoOAuthEnabled =
      bool.fromEnvironment('KAKAO_OAUTH_ENABLED', defaultValue: false);
  static const bool localSyncBetaEnabled =
      bool.fromEnvironment('LOCAL_SYNC_BETA_ENABLED', defaultValue: false);

  static String get oauthRedirectTo {
    if (kIsWeb) {
      return Uri.base.origin;
    }

    return 'io.supabase.kyoutube://login-callback';
  }

  static String get supabaseUrl {
    switch (appEnv) {
      case 'production':
        return _productionSupabaseUrl.isNotEmpty
            ? _productionSupabaseUrl
            : _supabaseUrl;
      case 'staging':
        return _stagingSupabaseUrl.isNotEmpty
            ? _stagingSupabaseUrl
            : _supabaseUrl;
      case 'local':
        return _localSupabaseUrl.isNotEmpty ? _localSupabaseUrl : _supabaseUrl;
      default:
        return _supabaseUrl;
    }
  }

  static String get supabaseAnonKey {
    switch (appEnv) {
      case 'production':
        return _productionSupabaseAnonKey.isNotEmpty
            ? _productionSupabaseAnonKey
            : _supabaseAnonKey;
      case 'staging':
        return _stagingSupabaseAnonKey.isNotEmpty
            ? _stagingSupabaseAnonKey
            : _supabaseAnonKey;
      case 'local':
        return _localSupabaseAnonKey.isNotEmpty
            ? _localSupabaseAnonKey
            : _supabaseAnonKey;
      default:
        return _supabaseAnonKey;
    }
  }

  static void validate() {
    if (appEnv == 'unset') {
      throw StateError(
        'APP_ENV is required. Pass one of local, staging, production via --dart-define=APP_ENV=... .',
      );
    }

    if (appEnv != 'local' && appEnv != 'staging' && appEnv != 'production') {
      throw StateError(
        'APP_ENV must be one of: local, staging, production.',
      );
    }

    if (supabaseUrl.isEmpty || supabaseAnonKey.isEmpty) {
      throw StateError(
        'Supabase runtime values are required for the selected APP_ENV. '
        'Provide either SUPABASE_URL/SUPABASE_ANON_KEY or the environment-specific keys.',
      );
    }
  }
}
