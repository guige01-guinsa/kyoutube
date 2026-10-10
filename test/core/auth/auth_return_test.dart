import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:k_youtube/core/auth/auth_return.dart';

void main() {
  test('only internal business paths can resume authentication', () {
    for (final bad in [
      'https://evil.example',
      '//evil.example',
      '/login',
      '/account/mfa',
      '/reset-password',
      '/shopping/../login',
      '/shopping/%5cfoo',
      '/shopping#external',
      '/shopping\n',
      '/unknown'
    ]) {
      expect(safeAuthReturn(bad), isNull, reason: bad);
    }
    const path = '/business-workspaces/shop/receiving/request?line=2';
    expect(safeAuthReturn(path), path);
    final uri = Uri.parse(loginFor(path, resume: true, account: 'owner'));
    expect(uri.path, '/login');
    expect(uri.queryParameters['returnTo'], path);
    expect(uri.queryParameters['resume'], '1');
  });
  test('OAuth return is consumed once and expires', () async {
    SharedPreferences.setMockInitialValues({});
    await AuthReturnStore.remember('/shopping-review?source=public%3A1');
    expect(await AuthReturnStore.take(), '/shopping-review?source=public%3A1');
    expect(await AuthReturnStore.take(), isNull);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('auth_return_path_v1', '0|/shopping');
    expect(await AuthReturnStore.take(), isNull);
    await AuthReturnStore.remember('https://evil.example');
    expect(await AuthReturnStore.take(), isNull);
  });
}
