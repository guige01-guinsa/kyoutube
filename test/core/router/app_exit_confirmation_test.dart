import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:k_youtube/core/localization/app_localizations.dart';
import 'package:k_youtube/core/router/app_exit_confirmation.dart';
import 'package:k_youtube/core/theme/app_theme.dart';

void main() {
  Future<(GoRouter, AppExitBackButtonDispatcher)> pumpExitApp(
    WidgetTester tester, {
    bool signedIn = true,
    Future<void> Function()? signOut,
    Future<void> Function()? exitApp,
    bool guardAllowsExit = true,
    String language = 'ko',
    double textScale = 1,
  }) async {
    tester.view.physicalSize = const Size(320, 740);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final router = GoRouter(routes: [
      ShellRoute(
        builder: (_, __, child) => child,
        routes: [
          GoRoute(
            path: '/',
            onExit: (_, __) => guardAllowsExit,
            builder: (_, __) => const Scaffold(body: Text('HOME')),
          ),
          GoRoute(
            path: '/detail',
            builder: (_, __) => const Scaffold(body: Text('DETAIL')),
          ),
        ],
      ),
    ]);
    addTearDown(router.dispose);
    final dispatcher = AppExitBackButtonDispatcher(
      confirmExit: () => showAppExitConfirmation(
        router.routerDelegate.navigatorKey.currentContext!,
        signedIn: signedIn,
        signOut: signOut ?? () async {},
        exitApp: exitApp ?? () async {},
      ),
    );
    await tester.pumpWidget(MaterialApp.router(
      theme: AppTheme.light,
      locale: Locale(language),
      supportedLocales: AppLocalizations.supportedLocales,
      localizationsDelegates: const [
        AppLocalizations.delegate,
        ...GlobalMaterialLocalizations.delegates,
      ],
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context)
            .copyWith(textScaler: TextScaler.linear(textScale)),
        child: child!,
      ),
      routerDelegate: router.routerDelegate,
      routeInformationParser: router.routeInformationParser,
      routeInformationProvider: router.routeInformationProvider,
      backButtonDispatcher: dispatcher,
    ));
    await tester.pumpAndSettle();
    return (router, dispatcher);
  }

  testWidgets(
      'root back offers choices; repeated back never duplicates or exits',
      (tester) async {
    final events = <String>[];
    final (_, dispatcher) = await pumpExitApp(tester,
        signOut: () async => events.add('signOut'),
        exitApp: () async => events.add('exit'));
    final back = dispatcher.didPopRoute();
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsOneWidget);
    expect(find.text('로그인 유지하고 종료'), findsOneWidget);
    expect(await dispatcher.didPopRoute(), isTrue);
    expect(find.byType(AlertDialog), findsOneWidget);
    await tester.tap(find.text('계속 사용'));
    await tester.pumpAndSettle();
    expect(await back, isTrue);
    expect(events, isEmpty);
  });

  testWidgets('keep session exits without calling sign out', (tester) async {
    final events = <String>[];
    final (_, dispatcher) = await pumpExitApp(tester,
        signOut: () async => events.add('signOut'),
        exitApp: () async => events.add('exit'));
    final back = dispatcher.didPopRoute();
    await tester.pumpAndSettle();
    await tester.tap(find.text('로그인 유지하고 종료'));
    await tester.pumpAndSettle();
    await back;
    expect(events, ['exit']);
  });

  testWidgets('sign out must finish before exit and blocks duplicate requests',
      (tester) async {
    final events = <String>[];
    final completed = Completer<void>();
    final (_, dispatcher) = await pumpExitApp(tester,
        signOut: () async {
          events.add('signOut');
          await completed.future;
        },
        exitApp: () async => events.add('exit'));
    final back = dispatcher.didPopRoute();
    await tester.pumpAndSettle();
    await tester.tap(find.text('로그아웃 후 종료'));
    await tester.pumpAndSettle();
    expect(events, ['signOut']);
    expect(await dispatcher.didPopRoute(), isTrue);
    completed.complete();
    await tester.pumpAndSettle();
    await back;
    expect(events, ['signOut', 'exit']);
  });

  testWidgets('sign out failure keeps app open and explains retry',
      (tester) async {
    var exited = false;
    final (_, dispatcher) = await pumpExitApp(tester,
        signOut: () async => throw StateError('offline'),
        exitApp: () async {
          exited = true;
        });
    final back = dispatcher.didPopRoute();
    await tester.pumpAndSettle();
    await tester.tap(find.text('로그아웃 후 종료'));
    await tester.pumpAndSettle();
    await back;
    expect(exited, isFalse);
    expect(find.textContaining('앱을 종료하지 않았습니다'), findsOneWidget);
    expect(find.text('HOME'), findsOneWidget);
  });

  testWidgets('detail back and open dialogs are handled before exit',
      (tester) async {
    final (router, dispatcher) = await pumpExitApp(tester);
    unawaited(router.push('/detail'));
    await tester.pumpAndSettle();
    expect(await dispatcher.didPopRoute(), isTrue);
    await tester.pumpAndSettle();
    expect(find.text('HOME'), findsOneWidget);
    expect(find.byType(AlertDialog), findsNothing);
    unawaited(showDialog<void>(
        context: router.routerDelegate.navigatorKey.currentContext!,
        builder: (_) => const AlertDialog(content: Text('OTHER DIALOG'))));
    await tester.pumpAndSettle();
    expect(await dispatcher.didPopRoute(), isTrue);
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsNothing);
  });

  testWidgets('existing editor exit guard takes priority', (tester) async {
    final (_, dispatcher) = await pumpExitApp(tester, guardAllowsExit: false);
    expect(await dispatcher.didPopRoute(), isTrue);
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsNothing);
    expect(find.text('HOME'), findsOneWidget);
  });

  for (final language in ['ko', 'en']) {
    testWidgets('signed in $language choices fit narrow large text',
        (tester) async {
      final (_, dispatcher) =
          await pumpExitApp(tester, language: language, textScale: 2);
      final back = dispatcher.didPopRoute();
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      final signOut =
          find.text(language == 'ko' ? '로그아웃 후 종료' : 'Sign out and exit');
      await tester.ensureVisible(signOut);
      expect(signOut.hitTestable(), findsOneWidget);
      final cancel = find.text(language == 'ko' ? '계속 사용' : 'Keep using');
      await tester.ensureVisible(cancel);
      await tester.tap(cancel);
      await tester.pumpAndSettle();
      await back;
    });
  }

  for (final language in ['ko', 'en']) {
    testWidgets(
        'guest $language dialog fits narrow large text and has no logout',
        (tester) async {
      final (_, dispatcher) = await pumpExitApp(tester,
          signedIn: false, language: language, textScale: 2);
      final back = dispatcher.didPopRoute();
      await tester.pumpAndSettle();
      expect(
          find.text(
              language == 'ko' ? '현재 로그아웃 상태입니다.' : 'You are not signed in.'),
          findsOneWidget);
      expect(find.text('로그아웃 후 종료'), findsNothing);
      expect(find.text('Sign out and exit'), findsNothing);
      expect(tester.takeException(), isNull);
      final cancel = find.text(language == 'ko' ? '계속 사용' : 'Keep using');
      await tester.ensureVisible(cancel);
      await tester.tap(cancel);
      await tester.pumpAndSettle();
      await back;
    });
  }
}
