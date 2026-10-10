import '../../../core/localization/localized_text.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/auth/auth_return.dart';
import '../application/auth_providers.dart';
import '../../membership/application/membership_providers.dart';

class AccountRecoveryActions extends ConsumerWidget {
  const AccountRecoveryActions({super.key, this.onRecovered});
  final VoidCallback? onRecovered;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final account = ref.watch(activeAccountIdProvider);
    final en = Localizations.localeOf(context).languageCode != 'ko';
    final info = ref.watch(membershipInfoProvider);
    var mfa = false;
    try {
      mfa = account != null &&
          Supabase.instance.client.auth.mfa
                  .getAuthenticatorAssuranceLevel()
                  .currentLevel !=
              AuthenticatorAssuranceLevels.aal2;
    } catch (_) {
      // Access stays server-enforced when the authentication client is unavailable.
    }
    final message = account == null
        ? (en ? 'Sign in to continue.' : '로그인 후 계속할 수 있습니다.')
        : mfa
            ? (en ? 'Complete two-step verification.' : '2단계 인증을 완료해 주세요.')
            : info.isLoading
                ? (en ? 'Checking access…' : '권한 확인 중입니다.')
                : info.valueOrNull?.isAdmin == true
                    ? (en
                        ? 'Access confirmed. Check the input and connection, then retry.'
                        : '권한이 확인되었습니다. 입력 내용과 연결 상태를 확인한 뒤 다시 시도해 주세요.')
                    : (en
                        ? 'Administrator access is required. Refresh your access if it changed.'
                        : '관리자 권한이 필요합니다. 권한이 변경됐다면 다시 확인해 주세요.');
    return Column(mainAxisSize: MainAxisSize.min, children: [
      Text(message),
      if (account == null || mfa)
        TextButton(
            onPressed: () async {
              final here = GoRouterState.of(context).uri.toString();
              await context.push(account == null
                  ? loginFor(here, resume: true)
                  : Uri(
                      path: '/account/mfa',
                      queryParameters: {'returnTo': here}).toString());
              if (!context.mounted) return;
              ref.invalidate(membershipInfoProvider);
              onRecovered?.call();
            },
            child: Text(account == null
                ? (en ? 'Sign in & continue' : '로그인 후 계속')
                : (en ? 'Verify & continue' : '인증 후 계속'))),
      TextButton(
          onPressed: () {
            ref.invalidate(membershipInfoProvider);
            onRecovered?.call();
          },
          child: LocalizedText(en ? 'Check access again' : '권한 다시 확인')),
    ]);
  }
}
