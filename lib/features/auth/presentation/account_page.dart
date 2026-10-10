import '../../marketing/application/marketing_providers.dart';
import 'package:flutter/material.dart';
import 'package:k_youtube/core/localization/localized_text.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/firebase/firebase_messaging_service.dart';
import '../../../core/router/app_router.dart';
import '../../../core/widgets/scout_page.dart';
import '../../membership/application/membership_providers.dart';

import '../application/account_service.dart';
import '../application/auth_providers.dart';

class AccountPage extends ConsumerStatefulWidget {
  const AccountPage({super.key});

  @override
  ConsumerState<AccountPage> createState() => _AccountPageState();
}

class _AccountPageState extends ConsumerState<AccountPage> {
  static final Uri _privacyPolicyUri = Uri.parse(
    'https://ka-part.com/privacy',
  );
  static final Uri _deleteAccountGuideUri = Uri.parse(
    'https://ka-part.com/delete-account',
  );

  bool _isProcessing = false;

  Future<void> _openExternalUrl(Uri uri) async {
    try {
      final opened = await launchUrl(
        uri,
        mode: LaunchMode.externalApplication,
      );

      if (!opened && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: LocalizedText('웹페이지를 열 수 없습니다.')),
        );
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: LocalizedText('웹페이지를 열 수 없습니다.')),
        );
      }
    }
  }

  Future<void> _signOut() async {
    setState(() {
      _isProcessing = true;
    });

    try {
      await ref.read(accountServiceProvider).signOutCurrentAccount();

      if (mounted) {
        context.go('/login');
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: LocalizedText('로그아웃에 실패했습니다. 잠시 후 다시 시도해 주세요.')),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isProcessing = false;
        });
      }
    }
  }

  Future<void> _requestNotificationPermission() async {
    await FirebaseMessagingService.requestPermission();

    if (!mounted) {
      return;
    }

    final state = FirebaseMessagingService.debugState.value;
    final isGranted = state.permissionStatus == 'authorized' ||
        state.permissionStatus == 'provisional';

    final message = state.errorMessage != null
        ? '알림 설정을 열지 못했습니다. 잠시 후 다시 시도해 주세요.'
        : isGranted
            ? '알림이 활성화되었습니다.'
            : '알림 권한이 허용되지 않았습니다. 필요하면 기기 설정에서 변경해 주세요.';

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: LocalizedText(message)),
    );
  }

  Future<void> _confirmAndDeleteAccount() async {
    final user = ref.read(authUserProvider).valueOrNull;

    if (user == null) {
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (BuildContext dialogContext) {
        return AlertDialog(
          title: const LocalizedText('회원탈퇴'),
          content: LocalizedText(
            '${user.email ?? '현재 계정'}을(를) 탈퇴하시겠습니까?\n\n'
            '탈퇴 후 계정 복구가 어려울 수 있습니다.',
          ),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const LocalizedText('취소'),
            ),
            FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: Theme.of(dialogContext).colorScheme.error,
                foregroundColor: Theme.of(dialogContext).colorScheme.onError,
              ),
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: const LocalizedText('탈퇴하기'),
            ),
          ],
        );
      },
    );

    if (confirmed != true || !mounted) {
      return;
    }

    setState(() {
      _isProcessing = true;
    });

    try {
      await ref.read(accountServiceProvider).deleteCurrentAccount();

      if (!mounted) {
        return;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: LocalizedText('회원탈퇴가 완료되었습니다.')),
      );

      context.go('/login');
    } on FunctionException {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: LocalizedText('회원탈퇴를 완료하지 못했습니다. 잠시 후 다시 시도해 주세요.')),
        );
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: LocalizedText('회원탈퇴를 완료하지 못했습니다. 잠시 후 다시 시도해 주세요.')),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isProcessing = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(authUserProvider).valueOrNull;
    final membership = ref.watch(membershipInfoProvider).valueOrNull;

    if (user == null) {
      return Scaffold(
        appBar: AppBar(title: const LocalizedText('계정 관리')),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                FilledButton(
                  onPressed: () => context.go('/login'),
                  child: const LocalizedText('로그인하기'),
                ),
                const SizedBox(height: 16),
                OutlinedButton.icon(
                  onPressed: () => _openExternalUrl(_privacyPolicyUri),
                  icon: const Icon(Icons.privacy_tip_outlined),
                  label: const LocalizedText('개인정보 처리방침'),
                ),
                const SizedBox(height: 8),
                OutlinedButton.icon(
                  onPressed: () => _openExternalUrl(_deleteAccountGuideUri),
                  icon: const Icon(Icons.person_remove_outlined),
                  label: const LocalizedText('계정 삭제 안내'),
                ),
              ],
            ),
          ),
        ),
      );
    }

    final isEnglish = Localizations.localeOf(context).languageCode != 'ko';
    return Scaffold(
      appBar: AppBar(title: const LocalizedText('계정 관리')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 32),
        child: ScoutPageBody(
          maxWidth: 880,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              ScoutPageHeading(
                title: isEnglish ? 'Your account, your way' : '나에게 맞는 계정 설정',
                subtitle: isEnglish
                    ? 'Manage your workspace, security and service preferences.'
                    : '작업공간과 보안, 서비스 이용 설정을 한곳에서 관리하세요.',
                icon: Icons.manage_accounts_outlined,
              ),
              const SizedBox(height: 16),
              ScoutPanel(
                child: Row(
                  children: <Widget>[
                    const CircleAvatar(
                        radius: 24, child: Icon(Icons.person_outline)),
                    const SizedBox(width: 16),
                    Expanded(
                        child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        const LocalizedText('로그인 계정'),
                        const SizedBox(height: 4),
                        SelectableText(user.email ?? context.tr('이메일 정보 없음'),
                            style: Theme.of(context).textTheme.titleMedium),
                      ],
                    )),
                  ],
                ),
              ),
              const SizedBox(height: 28),
              _settingsGroup(
                  isEnglish ? 'Workspace & security' : '이용 설정과 보안', <Widget>[
                ListTile(
                  leading: const Icon(Icons.tune),
                  title:
                      LocalizedText(isEnglish ? 'Manage purposes' : '이용 목적 관리'),
                  subtitle: LocalizedText(isEnglish
                      ? 'Choose your home and menus'
                      : '첫 화면과 메뉴를 나에게 맞게 선택해요'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: _isProcessing
                      ? null
                      : () => context.push('/workspace-settings'),
                ),
                ListTile(
                  leading: const Icon(Icons.security),
                  title: LocalizedText(
                      isEnglish ? 'Two-step verification' : '2단계 인증'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap:
                      _isProcessing ? null : () => context.push('/account/mfa'),
                ),
                ListTile(
                  leading: const Icon(Icons.workspace_premium_outlined),
                  title: const LocalizedText('회원 및 구독 관리'),
                  subtitle: const LocalizedText('무료·유료 등급과 AI 사용량을 확인합니다.'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: _isProcessing
                      ? null
                      : () => context.push(AppRoutes.membership),
                ),
                if (ref.watch(marketingAdminProvider).valueOrNull == true)
                  ListTile(
                    leading: const Icon(Icons.campaign_outlined),
                    title: const LocalizedText('마케팅 자동화'),
                    subtitle: const LocalizedText('홍보 초안 검토 및 예약 게시'),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: _isProcessing
                        ? null
                        : () => context.push(AppRoutes.marketing),
                  ),
                ListTile(
                  leading: const Icon(Icons.notifications_active_outlined),
                  title: const LocalizedText('알림 설정'),
                  subtitle: const LocalizedText('새 레시피와 서비스 알림을 받을 수 있습니다.'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: _isProcessing ? null : _requestNotificationPermission,
                ),
              ]),
              if (membership?.isAdmin ?? false) ...<Widget>[
                const SizedBox(height: 24),
                _settingsGroup(
                    isEnglish ? 'Service administration' : '서비스 운영', <Widget>[
                  ListTile(
                    leading: const Icon(Icons.admin_panel_settings_outlined),
                    title: const LocalizedText('관리자 홈'),
                    subtitle: const LocalizedText('회원·제휴 상품·서비스 운영을 관리합니다.'),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: _isProcessing
                        ? null
                        : () => context.push(AppRoutes.membershipAdmin),
                  ),
                ]),
              ],
              const SizedBox(height: 24),
              _settingsGroup(
                  isEnglish ? 'Help & information' : '도움말과 이용 안내', <Widget>[
                ListTile(
                  leading: const Icon(Icons.auto_stories_outlined),
                  title: const LocalizedText('레시피 스카우트 사용법'),
                  subtitle: const LocalizedText('영상에서 내 레시피와 장보기까지 둘러봅니다.'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: _isProcessing
                      ? null
                      : () => context.push(AppRoutes.guide),
                ),
                ListTile(
                  leading: const Icon(Icons.privacy_tip_outlined),
                  title: const LocalizedText('개인정보 처리방침'),
                  subtitle: const LocalizedText('레시피 스카우트 개인정보 처리방침을 확인합니다.'),
                  trailing: const Icon(Icons.open_in_new),
                  onTap: () => _openExternalUrl(_privacyPolicyUri),
                ),
                ListTile(
                  leading: const Icon(Icons.person_remove_outlined),
                  title: const LocalizedText('계정 삭제 안내'),
                  subtitle: const LocalizedText('계정 및 데이터 삭제 방법을 확인합니다.'),
                  trailing: const Icon(Icons.open_in_new),
                  onTap: () => _openExternalUrl(_deleteAccountGuideUri),
                ),
              ]),
              const SizedBox(height: 32),
              ScoutPanel(
                  child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  OutlinedButton.icon(
                    onPressed: _isProcessing ? null : _signOut,
                    icon: const Icon(Icons.logout),
                    label: const LocalizedText('로그아웃'),
                  ),
                  const SizedBox(height: 16),
                  const Divider(),
                  const SizedBox(height: 12),
                  LocalizedText('회원탈퇴 시 계정 복구가 어려울 수 있습니다.',
                      style: Theme.of(context).textTheme.bodySmall),
                  const SizedBox(height: 8),
                  Align(
                    alignment: AlignmentDirectional.centerStart,
                    child: TextButton.icon(
                      style: TextButton.styleFrom(
                          foregroundColor: Theme.of(context).colorScheme.error),
                      onPressed:
                          _isProcessing ? null : _confirmAndDeleteAccount,
                      icon: const Icon(Icons.person_remove_outlined),
                      label: LocalizedText(_isProcessing ? '처리 중...' : '회원탈퇴'),
                    ),
                  ),
                ],
              )),
            ],
          ),
        ),
      ),
    );
  }

  Widget _settingsGroup(String title, List<Widget> children) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Text(title, style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 12),
        Card(
            child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Column(children: <Widget>[
            for (var i = 0; i < children.length; i++) ...<Widget>[
              if (i > 0) const Divider(height: 1, indent: 16, endIndent: 16),
              children[i],
            ],
          ]),
        )),
      ],
    );
  }
}
