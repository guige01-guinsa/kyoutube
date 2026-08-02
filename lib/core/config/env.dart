import 'package:flutter/foundation.dart';

class Env {
  static const String _rawAppEnv =
      String.fromEnvironment('APP_ENV', defaultValue: '');

  static String get appEnv {
    final normalized = _rawAppEnv.trim().toLowerCase();
    switch (normalized) {
      case 'local':
      case 'staging':
      case 'production':
        return normalized;
      default:
        return kReleaseMode ? 'production' : 'local';
    }
  }

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

  static String get supabaseUrl {
    switch (appEnv) {
      case 'production':
        return _productionSupabaseUrl.isNotEmpty
            ? _productionSupabaseUrl
            : _supabaseUrl;
      case 'staging':
        return _stagingSupabaseUrl.isNotEmpty ? _stagingSupabaseUrl : _supabaseUrl;
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
    if (supabaseUrl.isEmpty || supabaseAnonKey.isEmpty) {
      throw StateError(
        'Supabase runtime values are required for the selected APP_ENV. '
        'Provide either SUPABASE_URL/SUPABASE_ANON_KEY or the environment-specific keys.',
      );
    }
  }
}
