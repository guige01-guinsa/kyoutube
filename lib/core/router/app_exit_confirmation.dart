import 'package:flutter/material.dart';

import '../localization/app_localizations.dart';

/// Let GoRouter handle history and editor guards before confirming app exit.
class AppExitBackButtonDispatcher extends RootBackButtonDispatcher {
  AppExitBackButtonDispatcher({required this.confirmExit});

  final Future<void> Function() confirmExit;
  bool _confirming = false;

  @override
  Future<bool> didPopRoute() async {
    if (_confirming) return true;
    if (await super.didPopRoute()) return true;
    if (_confirming) return true;
    _confirming = true;
    try {
      await confirmExit();
    } finally {
      _confirming = false;
    }
    // Cancellation and sign-out failure both keep the Android activity open.
    return true;
  }
}

enum _ExitChoice { keepSession, signOut }

Future<void> showAppExitConfirmation(
  BuildContext context, {
  required bool signedIn,
  required Future<void> Function() signOut,
  required Future<void> Function() exitApp,
}) async {
  final en = AppLocalizations.of(context).isEnglish;
  final messenger = ScaffoldMessenger.maybeOf(context);
  final choice = await showDialog<_ExitChoice>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      scrollable: true,
      title: Text(en ? 'Leave Recipe Scout?' : '레시피 스카우트를 종료할까요?'),
      content: Text(signedIn
          ? (en
              ? 'You are signed in. Choose whether to keep your login on this phone or sign out before leaving.'
              : '현재 로그인되어 있습니다. 이 휴대폰의 로그인을 유지하거나 로그아웃한 뒤 종료할 수 있어요.')
          : (en ? 'You are not signed in.' : '현재 로그아웃 상태입니다.')),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(dialogContext).pop(),
          child: Text(en ? 'Keep using' : '계속 사용'),
        ),
        TextButton(
          onPressed: () =>
              Navigator.of(dialogContext).pop(_ExitChoice.keepSession),
          child: Text(signedIn
              ? (en ? 'Exit and stay signed in' : '로그인 유지하고 종료')
              : (en ? 'Exit' : '종료')),
        ),
        if (signedIn)
          FilledButton(
            onPressed: () =>
                Navigator.of(dialogContext).pop(_ExitChoice.signOut),
            child: Text(en ? 'Sign out and exit' : '로그아웃 후 종료'),
          ),
      ],
    ),
  );
  if (choice == null) return;
  try {
    if (choice == _ExitChoice.signOut) await signOut();
    await exitApp();
  } catch (_) {
    if (messenger?.mounted ?? false) {
      messenger!.showSnackBar(SnackBar(
          content: Text(en
              ? 'Unable to complete the request. The app is still open. Check your connection and try again.'
              : '요청을 완료하지 못해 앱을 종료하지 않았습니다. 연결 상태를 확인한 뒤 다시 시도해 주세요.')));
    }
  }
}
