import 'package:shared_preferences/shared_preferences.dart';

/// Internal navigation only. No credentials or form contents are persisted.
String? safeAuthReturn(String? value) {
  if (value == null ||
      value.length > 2048 ||
      !value.startsWith('/') ||
      value.startsWith('//') ||
      RegExp(r'[\\\x00-\x20]').hasMatch(value)) {
    return null;
  }
  final uri = Uri.tryParse(value);
  if (uri == null ||
      uri.hasScheme ||
      uri.hasAuthority ||
      uri.hasFragment ||
      uri.path.contains('..') ||
      uri.path.contains('%') ||
      RegExp(r'[\\\x00-\x20]').hasMatch(uri.path) ||
      ['/login', '/account/mfa', '/reset-password'].contains(uri.path)) {
    return null;
  }
  const roots = [
    'workspace',
    'search',
    'chef',
    'chef-sales',
    'classics',
    'guide',
    'business-workspaces',
    'business-samples',
    'membership',
    'shopping',
    'shopping-review',
    'shopping-assistant',
    'shopping-preparation',
    'shopping-stores',
    'kitchen',
    'account',
    'my-recipes',
    'recipes',
    'creator',
    'subscriber',
    'ingredient-search',
    'ingredient-search-results',
    'recommended-search',
    'youtube',
    'suppliers',
    'supplier-directory',
    'supplier-business',
    'procurement-plan',
    'supplier-plan',
    'supplier-requests',
    'supplier-request-ledger'
  ];
  return roots.contains(uri.pathSegments.firstOrNull) ? uri.toString() : null;
}

String loginFor(String location, {bool resume = false, String? account}) =>
    Uri(path: '/login', queryParameters: {
      if (safeAuthReturn(location) case final String path) 'returnTo': path,
      if (resume) 'resume': '1',
      if (account != null) 'account': account,
    }).toString();

class AuthReturnStore {
  static const _key = 'auth_return_path_v1';
  static String? _memory;
  static Future<void> remember(String? path) async {
    _memory = safeAuthReturn(path);
    try {
      final prefs = await SharedPreferences.getInstance();
      if (_memory == null) {
        await prefs.remove(_key);
        return;
      }
      await prefs.setString(
          _key, '${DateTime.now().millisecondsSinceEpoch}|$_memory');
    } catch (_) {
      /* In-memory navigation still works if browser storage is blocked. */
    }
  }

  static Future<String?> take() async {
    final fallback = _memory;
    _memory = null;
    try {
      final prefs = await SharedPreferences.getInstance();
      final saved = prefs.getString(_key);
      await prefs.remove(_key);
      if (saved == null) return fallback;
      final separator = saved.indexOf('|');
      if (separator < 0) return null;
      final time = int.tryParse(saved.substring(0, separator));
      final age = DateTime.now().millisecondsSinceEpoch - (time ?? 0);
      if (age < 0 || age > const Duration(minutes: 30).inMilliseconds) {
        return null;
      }
      return safeAuthReturn(saved.substring(separator + 1));
    } catch (_) {
      return fallback;
    }
  }
}
