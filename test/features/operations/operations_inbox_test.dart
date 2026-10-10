import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:k_youtube/core/localization/app_localizations.dart';
import 'package:k_youtube/features/operations/data/operations_alerts_repository.dart';
import 'package:k_youtube/features/operations/domain/operations_alert.dart';
import 'package:k_youtube/features/operations/presentation/operations_inbox_page.dart';

class MemoryInbox implements OpsAlertsRepository {
  bool read = false;
  bool fail = false;
  @override
  Future<Map<String, dynamic>> inbox(int? before) async {
    if (fail) throw StateError('private server exception');
    return {
      'last_checked_at': null,
      'pending_push': 1,
      'failed_push': 0,
      'database_budget_bytes': 8589934592,
      'events': [
        {
          'id': 7,
          'code': 'database_budget',
          'severity': 'warning',
          'is_read': read,
          'created_at': '2026-09-13T00:00:00Z',
          'detail': {'percent': 74.2}
        }
      ]
    };
  }

  @override
  Future<void> markRead(int id) async {
    read = true;
  }

  @override
  Future<void> setDatabaseBudget(int bytes) async {}
}

Future<void> showInbox(
    WidgetTester tester, String language, MemoryInbox repo) async {
  await tester.pumpWidget(ProviderScope(
      overrides: [opsAlertsRepositoryProvider.overrideWithValue(repo)],
      child: MaterialApp(
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
          home: const OperationsInboxPage())));
  await tester.pumpAndSettle();
}

void main() {
  for (final language in ['ko', 'en']) {
    testWidgets('$language inbox remains usable at narrow width and marks read',
        (tester) async {
      tester.view.physicalSize = const Size(320, 740);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final repo = MemoryInbox();
      await showInbox(tester, language, repo);
      expect(tester.takeException(), isNull);
      final monitoring = find.text(language == 'ko'
          ? '자동 감시 실행 상태를 확인하세요'
          : 'Check the monitoring schedule');
      await tester.scrollUntilVisible(monitoring, 250,
          scrollable: find.byType(Scrollable).first);
      await tester.pumpAndSettle();
      expect(monitoring, findsOneWidget);
      final target = find.text(language == 'ko' ? '확인 표시' : 'Mark read');
      await tester.scrollUntilVisible(target, 250,
          scrollable: find.byType(Scrollable).first);
      await tester.ensureVisible(target);
      await tester.pumpAndSettle();
      await tester.tap(target);
      await tester.pumpAndSettle();
      expect(repo.read, isTrue);
      expect(tester.takeException(), isNull);
    });
  }
  testWidgets('failed authorization does not show empty or healthy inbox',
      (tester) async {
    await showInbox(tester, 'en', MemoryInbox()..fail = true);
    expect(find.textContaining('Check admin access'), findsOneWidget);
    expect(find.textContaining('private server'), findsNothing);
    expect(find.text('Operations monitoring'), findsNothing);
  });
  test('measurement distinguishes DB alert budget from real free disk', () {
    final alert = OperationsAlert({
      'id': 1,
      'code': 'database_budget',
      'severity': 'warning',
      'created_at': '2026-09-13T00:00:00Z',
      'detail': {'percent': 71}
    });
    expect(alert.measurement(true), contains('configured DB budget'));
    expect(alert.action(true), contains('not actual free disk space'));
  });
}
