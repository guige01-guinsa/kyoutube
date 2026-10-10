import 'package:k_youtube/features/membership/domain/membership_features.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:k_youtube/core/localization/app_localizations.dart';
import 'package:k_youtube/core/theme/app_theme.dart';
import 'package:k_youtube/features/membership/application/membership_providers.dart';
import 'package:k_youtube/features/membership/domain/membership.dart';
import 'package:k_youtube/features/recipes/presentation/widgets/youtube_draft_methods.dart';

void main() {
  for (final lang in ['ko', 'en']) {
    for (final plan in [
      'free',
      'plus_monthly',
      'plus_annual',
      'business_monthly',
      'business_annual'
    ]) {
      testWidgets('$lang draft methods enforce $plan at narrow large text',
          (tester) async {
        tester.view.physicalSize = const Size(320, 900);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        var standard = 0, video = 0;
        await tester.pumpWidget(ProviderScope(
            overrides: [
              membershipInfoProvider.overrideWith((ref) async =>
                  MembershipInfo.fromJson({
                    'plan_code': plan,
                    'status': 'active',
                    'valid_until': '2099-01-01T00:00:00Z'
                  })),
              membershipFeaturesProvider.overrideWith((_) async =>
                  MembershipFeatures(
                      canManageCosts: false,
                      canManageSales: false,
                      canShareRequestPdf: false,
                      videoMonthlyLimit: plan == 'free' ? 0 : 5,
                      supplierLimit: 3)),
              videoAnalysisUsageProvider
                  .overrideWith((ref) async => (limit: 20, used: 3)),
            ],
            child: MaterialApp(
                theme: AppTheme.light,
                locale: Locale(lang),
                supportedLocales: AppLocalizations.supportedLocales,
                localizationsDelegates: const [
                  AppLocalizations.delegate,
                  GlobalMaterialLocalizations.delegate,
                  GlobalWidgetsLocalizations.delegate,
                  GlobalCupertinoLocalizations.delegate
                ],
                builder: (context, child) => MediaQuery(
                    data: MediaQuery.of(context)
                        .copyWith(textScaler: const TextScaler.linear(2)),
                    child: child!),
                home: Scaffold(
                    body: SingleChildScrollView(
                        padding: const EdgeInsets.all(16),
                        child: YoutubeDraftMethods(
                            onStandard: () => standard++,
                            onVideo: () => video++))))));
        await tester.pumpAndSettle();
        final normal = find.byKey(const ValueKey('standard-youtube-draft'));
        await tester.ensureVisible(normal);
        await tester.tap(normal);
        expect(standard, 1);
        final button = find.byKey(const ValueKey('video-youtube-draft'));
        expect(tester.widget<OutlinedButton>(button).onPressed != null,
            plan != 'free');
        if (plan != 'free') {
          await tester.ensureVisible(button);
          await tester.tap(button);
          expect(video, 1);
        }
        expect(tester.takeException(), isNull);
      });
    }
  }
  testWidgets(
      'monthly limit or expired membership disables video but keeps standard',
      (tester) async {
    for (final expired in [false, true]) {
      await tester.pumpWidget(const SizedBox());
      await tester.pumpWidget(ProviderScope(
          overrides: [
            membershipInfoProvider
                .overrideWith((ref) async => MembershipInfo.fromJson({
                      'plan_code': 'paid_monthly',
                      'status': 'active',
                      'valid_until': expired ? '2020-01-01' : '2099-01-01'
                    })),
            membershipFeaturesProvider.overrideWith((_) async =>
                MembershipFeatures(
                    canManageCosts: false,
                    canManageSales: false,
                    canShareRequestPdf: false,
                    videoMonthlyLimit: expired ? 0 : 20,
                    supplierLimit: 3)),
            videoAnalysisUsageProvider
                .overrideWith((ref) async => (limit: 20, used: 20)),
          ],
          child: MaterialApp(
              home: Scaffold(
                  body: SingleChildScrollView(
                      child: YoutubeDraftMethods(
                          onStandard: () {}, onVideo: () {}))))));
      await tester.pumpAndSettle();
      expect(
          tester
              .widget<OutlinedButton>(
                  find.byKey(const ValueKey('video-youtube-draft')))
              .onPressed,
          isNull);
      expect(
          tester
              .widget<FilledButton>(
                  find.byKey(const ValueKey('standard-youtube-draft')))
              .onPressed,
          isNotNull);
    }
  });
}
