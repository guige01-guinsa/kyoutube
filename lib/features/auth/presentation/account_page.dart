import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import '../application/account_service.dart';
import '../application/auth_providers.dart';

class AccountPage extends ConsumerStatefulWidget {
  const AccountPage({super.key});

  @override
  ConsumerState<AccountPage> createState() => _AccountPageState();
}

class _AccountPageState extends ConsumerState<AccountPage> {
  static final Uri _privacyPolicyUri = Uri.parse(
    'https://www.ka-part.com/privacy',
  );
  static final Uri _deleteAccountGuideUri = Uri.parse(
    'https://www.ka-part.com/delete-account',
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
          const SnackBar(content: Text('웹페이지를 열 수 없습니다.')),
        );
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('웹페이지를 열 수 없습니다.')),
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
          const SnackBar(content: Text('로그아웃에 실패했습니다. 잠시 후 다시 시도해 주세요.')),
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

  Future<void> _confirmAndDeleteAccount() async {
    final user = ref.read(authUserProvider).valueOrNull;

    if (user == null) {
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (BuildContext dialogContext) {
        return AlertDialog(
          title: const Text('회원탈퇴'),
          content: Text(
            '${user.email ?? '현재 계정'}을(를) 탈퇴하시겠습니까?\n\n'
            '탈퇴 후 계정 복구가 어려울 수 있습니다.',
          ),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('취소'),
            ),
            FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: Theme.of(dialogContext).colorScheme.error,
                foregroundColor: Theme.of(dialogContext).colorScheme.onError,
              ),
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: const Text('탈퇴하기'),
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
        const SnackBar(content: Text('회원탈퇴가 완료되었습니다.')),
      );

      context.go('/login');
    } on FunctionException {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('회원탈퇴를 완료하지 못했습니다. 잠시 후 다시 시도해 주세요.')),
        );
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('회원탈퇴를 완료하지 못했습니다. 잠시 후 다시 시도해 주세요.')),
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

    if (user == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('계정 관리')),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                FilledButton(
                  onPressed: () => context.go('/login'),
                  child: const Text('로그인하기'),
                ),
                const SizedBox(height: 16),
                OutlinedButton.icon(
                  onPressed: () => _openExternalUrl(_privacyPolicyUri),
                  icon: const Icon(Icons.privacy_tip_outlined),
                  label: const Text('개인정보 처리방침'),
                ),
                const SizedBox(height: 8),
                OutlinedButton.icon(
                  onPressed: () => _openExternalUrl(_deleteAccountGuideUri),
                  icon: const Icon(Icons.person_remove_outlined),
                  label: const Text('계정 삭제 안내'),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('계정 관리'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: <Widget>[
          Card(
            child: ListTile(
              leading: const CircleAvatar(
                child: Icon(Icons.person_outline),
              ),
              title: const Text('로그인 계정'),
              subtitle: Text(user.email ?? '이메일 정보 없음'),
            ),
          ),
          const SizedBox(height: 20),
          FilledButton.icon(
            onPressed: _isProcessing ? null : _signOut,
            icon: const Icon(Icons.logout),
            label: const Text('로그아웃'),
          ),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: _isProcessing ? null : _confirmAndDeleteAccount,
            icon: Icon(
              Icons.person_remove_outlined,
              color: Theme.of(context).colorScheme.error,
            ),
            label: Text(
              _isProcessing ? '처리 중...' : '회원탈퇴',
              style: TextStyle(
                color: Theme.of(context).colorScheme.error,
              ),
            ),
          ),
          const SizedBox(height: 16),
          Text(
            '회원탈퇴 시 계정 복구가 어려울 수 있습니다.',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 24),
          const Divider(),
          ListTile(
            leading: const Icon(Icons.privacy_tip_outlined),
            title: const Text('개인정보 처리방침'),
            subtitle: const Text('playscout 개인정보 처리방침을 확인합니다.'),
            trailing: const Icon(Icons.open_in_new),
            onTap: () => _openExternalUrl(_privacyPolicyUri),
          ),
          ListTile(
            leading: const Icon(Icons.person_remove_outlined),
            title: const Text('계정 삭제 안내'),
            subtitle: const Text('계정 및 데이터 삭제 방법을 확인합니다.'),
            trailing: const Icon(Icons.open_in_new),
            onTap: () => _openExternalUrl(_deleteAccountGuideUri),
          ),
        ],
      ),
    );
  }
}
