import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:k_youtube/core/localization/app_localizations.dart';
import 'package:k_youtube/core/router/app_router.dart';
import 'package:k_youtube/core/theme/app_theme.dart';
import 'package:k_youtube/features/auth/application/auth_providers.dart';
import 'package:k_youtube/features/membership/application/membership_providers.dart';
import 'package:k_youtube/features/membership/domain/membership.dart';
import 'package:k_youtube/features/membership/presentation/membership_admin_page.dart';

void main() {
  const capture = bool.fromEnvironment('DESIGN_COMPLETE_CAPTURE');
  if (capture) {
    setUpAll(() async {
      for (final family in [
        'Ahem',
        'Roboto',
        'RecipeScoutKR',
        'MaterialIcons'
      ]) {
        final path = family == 'MaterialIcons'
            ? '.fvm/flutter_sdk/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf'
            : 'assets/fonts/NanumGothic-Regular.ttf';
        await (FontLoader(family)
              ..addFont(File(path).readAsBytes().then(ByteData.sublistView)))
            .load();
      }
      await Directory('.artifacts/design-complete').create(recursive: true);
    });
  }
  for (final language in ['ko', 'en']) {
    for (final size in [const Size(320, 900), const Size(1366, 900)]) {
      testWidgets('$language admin tasks and member search at $size',
          (tester) async {
        tester.view.physicalSize =
            capture && size.width < 400 ? const Size(390, 900) : size;
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final router = GoRouter(routes: [
          GoRoute(path: '/', builder: (_, __) => const MembershipAdminPage()),
          GoRoute(
              path: AppRoutes.shoppingAffiliateAdmin,
              builder: (_, __) =>
                  const Scaffold(body: Text('Affiliate destination'))),
        ]);
        addTearDown(router.dispose);
        await tester.pumpWidget(ProviderScope(
            overrides: [
              activeAccountIdProvider.overrideWith((_) => 'admin'),
              membershipInfoProvider.overrideWith(
                  (_) async => MembershipInfo.fromJson({'is_admin': true})),
              managedMembershipsProvider.overrideWith((_) async => [
                    ManagedMembership.fromJson({
                      'user_id': '1',
                      'email': 'chef@example.com',
                      'display_name': 'Chef'
                    }),
                    ManagedMembership.fromJson({
                      'user_id': '2',
                      'email': 'buyer@example.com',
                      'display_name': 'Buyer'
                    }),
                  ]),
            ],
            child: MaterialApp.router(
              debugShowCheckedModeBanner: false,
              routerConfig: router,
              theme: AppTheme.light,
              locale: Locale(language),
              supportedLocales: AppLocalizations.supportedLocales,
              localizationsDelegates: const [
                AppLocalizations.delegate,
                GlobalMaterialLocalizations.delegate,
                GlobalWidgetsLocalizations.delegate,
                GlobalCupertinoLocalizations.delegate
              ],
              builder: (context, child) => MediaQuery(
                  data: MediaQuery.of(context).copyWith(
                      textScaler: TextScaler.linear(
                          !capture && size.width < 400 ? 2 : 1)),
                  child: RepaintBoundary(
                      key: const ValueKey('admin-design-preview'),
                      child: child!)),
            )));
        await tester.pumpAndSettle();
        if (capture && language == 'ko') {
          final boundary = tester.renderObject<RenderRepaintBoundary>(
              find.byKey(const ValueKey('admin-design-preview')));
          await tester.runAsync(() async {
            final image = await boundary.toImage(pixelRatio: 1);
            final bytes =
                await image.toByteData(format: ui.ImageByteFormat.png);
            await File(
                    '.artifacts/design-complete/admin-${size.width < 400 ? 'mobile' : 'desktop'}.png')
                .writeAsBytes(bytes!.buffer.asUint8List());
            image.dispose();
          });
        }
        expect(tester.takeException(), isNull);
        await tester.scrollUntilVisible(find.byType(TextField), 400,
            scrollable: find.byType(Scrollable).first, maxScrolls: 30);
        await tester.enterText(find.byType(TextField), 'Chef');
        await tester.pumpAndSettle();
        await tester.scrollUntilVisible(find.text('chef@example.com'), 150,
            scrollable: find.byType(Scrollable).first);
        expect(find.text('chef@example.com'), findsOneWidget);
        expect(find.text('buyer@example.com'), findsNothing);
        expect(tester.takeException(), isNull);
        final affiliate =
            find.text(language == 'ko' ? '제휴 상품 관리' : 'Affiliate offers');
        // The card remains reachable by scrolling even on enlarged mobile layouts.
        for (var i = 0;
            i < 30 && affiliate.hitTestable().evaluate().isEmpty;
            i++) {
          await tester.drag(
              find.byType(CustomScrollView), const Offset(0, 350));
          await tester.pumpAndSettle();
        }
        expect(affiliate.hitTestable(), findsOneWidget);
        await tester.tap(affiliate.hitTestable());
        await tester.pumpAndSettle();
        expect(find.text('Affiliate destination'), findsOneWidget);
        expect(tester.takeException(), isNull);
      });
    }
  }
  for (final state in ['signed-out', 'member', 'loading', 'error']) {
    testWidgets('admin tools are hidden while access is $state',
        (tester) async {
      var requestedMembers = false;
      final pending = Completer<MembershipInfo>();
      await tester.pumpWidget(ProviderScope(overrides: [
        activeAccountIdProvider
            .overrideWith((_) => state == 'signed-out' ? null : 'member'),
        membershipInfoProvider.overrideWith((_) {
          if (state == 'loading') return pending.future;
          if (state == 'error') {
            return Future<MembershipInfo>.error(StateError('offline'));
          }
          return Future.value(MembershipInfo.fromJson({'is_admin': false}));
        }),
        managedMembershipsProvider.overrideWith((_) async {
          requestedMembers = true;
          return [];
        }),
      ], child: const MaterialApp(home: MembershipAdminPage())));
      await tester.pump();
      if (state != 'loading') await tester.pumpAndSettle();
      expect(find.text('Affiliate offers'), findsNothing);
      expect(find.text('제휴 상품 관리'), findsNothing);
      expect(find.byType(TextField), findsNothing);
      expect(requestedMembers, isFalse);
      expect(tester.takeException(), isNull);
      if (state == 'loading') {
        expect(find.byType(CircularProgressIndicator), findsOneWidget);
        pending.complete(MembershipInfo.fromJson({'is_admin': false}));
        await tester.pumpAndSettle();
        expect(find.text('Affiliate offers'), findsNothing);
        expect(requestedMembers, isFalse);
      }
    });
  }
}
