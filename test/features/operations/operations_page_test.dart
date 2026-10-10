import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:k_youtube/core/localization/app_localizations.dart';
import 'package:k_youtube/core/theme/app_theme.dart';
import 'package:k_youtube/features/operations/data/operations_repository.dart';
import 'package:k_youtube/features/operations/domain/operations_overview.dart';
import 'package:k_youtube/features/operations/presentation/operations_page.dart';

Future<void> showPage(WidgetTester tester, String language,
    {bool fail = false}) async {
  await tester.pumpWidget(ProviderScope(
      overrides: [
        operationsOverviewProvider.overrideWith((ref, days) async {
          if (fail) throw StateError('private backend message');
          return OperationsOverview.fromJson({
            'generated_at': '2026-09-12T12:00:00Z',
            'days': days,
            'requests': {
              'total': 20,
              'failed': 2,
              'ai_attempts': 10,
              'ai_successes': 8,
              'ai_p95_ms': 65000
            },
            'usage': {
              'month': '2026-09-01',
              'input_tokens': 10000,
              'output_tokens': 1234,
              'unknown_usage': 2
            },
            'costs': null,
            'failures': [
              {
                'source': 'ai_youtube_recipe_assistant',
                'code': 'incomplete_draft',
                'kind': 'request',
                'count': 2
              }
            ],
          });
        }),
      ],
      child: MaterialApp(
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
            data: MediaQuery.of(context)
                .copyWith(textScaler: const TextScaler.linear(2)),
            child: child!),
        home: const OperationsPage(),
      )));
  await tester.pumpAndSettle();
}

void main() {
  for (final language in ['ko', 'en']) {
    testWidgets(
        '$language dashboard remains usable at 320px and double text scale',
        (tester) async {
      tester.view.physicalSize = const Size(320, 740);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await showPage(tester, language);
      expect(tester.takeException(), isNull);
      final save = find.text(opsCopy['save']!.en);
      final target = language == 'en' ? save : find.text(opsCopy['save']!.ko);
      await tester.scrollUntilVisible(target, 250,
          scrollable: find.byType(Scrollable).first);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await tester.enterText(find.byType(TextField).last, '-1');
      await tester.ensureVisible(target);
      await tester.tap(target);
      await tester.pumpAndSettle();
      expect(
          find.text(language == 'en'
              ? opsCopy['invalid']!.en
              : opsCopy['invalid']!.ko),
          findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }
  testWidgets('failed load shows recovery instead of healthy zero metrics',
      (tester) async {
    await showPage(tester, 'en', fail: true);
    expect(find.text(opsCopy['unavailable']!.en), findsOneWidget);
    expect(find.text('0'), findsNothing);
    expect(find.textContaining('private backend'), findsNothing);
  });
}
