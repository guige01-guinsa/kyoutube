import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:k_youtube/core/localization/app_localizations.dart';
import 'package:k_youtube/core/theme/app_theme.dart';
import 'package:k_youtube/features/auth/application/auth_providers.dart';
import 'package:k_youtube/features/membership/application/membership_providers.dart';
import 'package:k_youtube/features/membership/domain/membership.dart';
import 'package:k_youtube/features/membership/domain/membership_features.dart';
import 'package:k_youtube/features/membership/presentation/membership_page.dart';
import 'membership_purchase_gate_test.dart' show AvailableStore;
import 'membership_features_test.dart' show account;

void main() {
  setUpAll(() async {
    await (FontLoader('Roboto')
          ..addFont(rootBundle.load('assets/fonts/NanumGothic-Regular.ttf')))
        .load();
    await (FontLoader('MaterialIcons')
          ..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf')))
        .load();
  });
  for (final en in [false, true]) {
    testWidgets(
        'launch billing ${en ? 'English' : 'Korean'} selects annual and supports large text',
        (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final boundary = GlobalKey();
      await tester.pumpWidget(ProviderScope(
          overrides: [
            authUserProvider
                .overrideWith((_) => Stream.value(account('launch-fixture'))),
            membershipServiceProvider.overrideWithValue(AvailableStore()),
            membershipInfoProvider
                .overrideWith((_) async => MembershipInfo.fromJson({
                      'plan_code': 'free',
                      'display_name': 'Scout',
                      'monthly_limit': 10,
                      'weekly_limit': 5,
                      'daily_limit': 1
                    })),
            membershipFeaturesProvider.overrideWith((_) async =>
                const MembershipFeatures(
                    canManageCosts: false,
                    canManageSales: false,
                    canShareRequestPdf: false,
                    videoMonthlyLimit: 0,
                    supplierLimit: 3,
                    requestMonthlyLimit: 3)),
            activeMembershipPlanPoliciesProvider.overrideWith((_) async => []),
          ],
          child: MaterialApp(
              theme: AppTheme.light,
              locale: Locale(en ? 'en' : 'ko'),
              supportedLocales: AppLocalizations.supportedLocales,
              localizationsDelegates: const [
                AppLocalizations.delegate,
                GlobalMaterialLocalizations.delegate,
                GlobalWidgetsLocalizations.delegate,
                GlobalCupertinoLocalizations.delegate
              ],
              builder: (_, child) =>
                  RepaintBoundary(key: boundary, child: child!),
              home: const MembershipPage())));
      await tester.pumpAndSettle();
      final annual = find.text(en ? 'Annual' : '연간');
      await tester.scrollUntilVisible(annual, 250,
          scrollable: find.byType(Scrollable).first);
      await tester.pumpAndSettle();
      await tester.tap(annual);
      await tester.pumpAndSettle();
      expect(
          tester
              .widget<SegmentedButton<bool>>(find.byType(SegmentedButton<bool>))
              .selected,
          {true});
      expect(find.text('₩99,000'), findsOneWidget);
      expect(find.text('₩189,000'), findsOneWidget);
      final out = Platform.environment['BILLING_PREVIEW_DIR'];
      if (out != null) {
        await tester.runAsync(() async {
          final render = boundary.currentContext!.findRenderObject()!
              as RenderRepaintBoundary;
          final picture = await render.toImage(pixelRatio: 2);
          final bytes =
              await picture.toByteData(format: ui.ImageByteFormat.png);
          await Directory(out).create(recursive: true);
          await File('$out/billing-${en ? 'en' : 'ko'}.png')
              .writeAsBytes(bytes!.buffer.asUint8List());
          picture.dispose();
        });
      }
      tester.view.physicalSize = const Size(320, 720);
      tester.platformDispatcher.textScaleFactorTestValue = 2;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(annual, 150,
          scrollable: find.byType(Scrollable).first);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });
  }
}
