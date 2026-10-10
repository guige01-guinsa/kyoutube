import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:k_youtube/core/theme/app_theme.dart';
import 'package:k_youtube/features/auth/application/auth_providers.dart';
import 'package:k_youtube/features/shopping/data/request_ledger_repository.dart';
import 'package:k_youtube/features/shopping/domain/purchase_request_ledger.dart';
import 'package:k_youtube/features/shopping/domain/supplier_request.dart';
import 'package:k_youtube/features/shopping/application/request_document_service.dart';
import 'package:k_youtube/features/shopping/presentation/request_document_preview.dart';
import 'package:k_youtube/features/shopping/presentation/request_ledger_page.dart';
import 'request_documents_test.dart' show ledgerFixture, certificateFixture;
import 'supplier_request_test.dart' show sampleRequest;

class LedgerRepo implements RequestLedgerRepository {
  final filters = <RequestLedgerFilter>[];
  int count = 2;
  @override
  Future<RequestLedgerPageData> search(RequestLedgerFilter f,
      {int offset = 0, int limit = 50}) async {
    filters.add(f);
    return RequestLedgerPageData.fromJson(ledgerFixture(count: count));
  }

  @override
  Future<SupplierRequest> request(String id) async => sampleRequest();
  @override
  Future<List<Map<String, dynamic>>> events(String id) async => [
        {
          'event': 'baseline',
          'to_status': 'draft',
          'revision': 1,
          'recorded_at': '2026-09-16T01:00:00Z'
        }
      ];
}

final testOwner = StateProvider<String?>((_) => 'test-owner');
Future<void> pump(WidgetTester tester, Widget home, List<Override> overrides,
    {String locale = 'ko', double scale = 1.2}) async {
  tester.view.physicalSize = const Size(360, 800);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(ProviderScope(
      overrides: [
        activeAccountIdProvider.overrideWith((ref) => ref.watch(testOwner)),
        ...overrides
      ],
      child: MaterialApp(
          theme: AppTheme.light,
          locale: Locale(locale),
          supportedLocales: const [Locale('ko'), Locale('en')],
          localizationsDelegates: const [
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate
          ],
          builder: (ctx, child) => MediaQuery(
              data: MediaQuery.of(ctx)
                  .copyWith(textScaler: TextScaler.linear(scale)),
              child: child!),
          home: home)));
  await tester.pumpAndSettle();
}

void main() {
  for (final locale in ['ko', 'en']) {
    testWidgets(
        'ledger $locale filters and exports matching rows on narrow display',
        (tester) async {
      final repo = LedgerRepo();
      final exports = <String>[];
      await pump(
          tester,
          const RequestLedgerPage(),
          [
            requestLedgerRepositoryProvider.overrideWithValue(repo),
            requestDocumentExportProvider
                .overrideWithValue((bytes, name, mime, origin) async {
              exports.add(name);
              expect(mime, 'text/csv');
            })
          ],
          locale: locale);
      expect(tester.takeException(), isNull);
      await tester.enterText(find.byType(TextField), 'Pantry');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();
      expect(repo.filters.last.query, 'Pantry');
      final export = find.text(locale == 'ko' ? 'CSV 대장 출력' : 'Export CSV');
      await tester.scrollUntilVisible(export.hitTestable(), 180,
          scrollable: find
              .descendant(
                  of: find.byType(ListView), matching: find.byType(Scrollable))
              .first);
      await tester.tap(export);
      await tester.pumpAndSettle();
      expect(exports.single, endsWith('.csv'));
      expect(tester.takeException(), isNull);
    });
  }
  testWidgets('ledger rejects partial exports beyond 1000 rows',
      (tester) async {
    final repo = LedgerRepo();
    var exported = false;
    await pump(tester, const RequestLedgerPage(), [
      requestLedgerRepositoryProvider.overrideWithValue(repo),
      requestDocumentExportProvider.overrideWithValue((b, n, m, o) async {
        exported = true;
      })
    ]);
    repo.count = 1001;
    final button = find.text('CSV 대장 출력');
    await tester.scrollUntilVisible(button.hitTestable(), 180,
        scrollable: find
            .descendant(
                of: find.byType(ListView), matching: find.byType(Scrollable))
            .first);
    await tester.tap(button);
    await tester.pumpAndSettle();
    expect(exported, isFalse);
    expect(find.textContaining('1,000건'), findsOneWidget);
  });
  testWidgets(
      'PDF preview exports and prints exactly displayed bytes after access recheck',
      (tester) async {
    final pdf = Uint8List.fromList([37, 80, 68, 70]);
    var accesses = 0;
    Uint8List? saved, printed;
    final png = await tester.runAsync(certificateFixture);
    await pump(
        tester,
        PurchasePdfPreview(
            title: 'Document',
            filename: 'test',
            buildDocument: () async => pdf),
        [
          requestDocumentAccessProvider.overrideWithValue(() async {
            accesses++;
          }),
          requestDocumentRasterProvider.overrideWithValue((b) async {
            expect(identical(b, pdf), isTrue);
            return [png!];
          }),
          requestDocumentExportProvider.overrideWithValue((b, n, m, o) async {
            saved = b;
          }),
          requestDocumentPrintProvider.overrideWithValue((b, n, active) async {
            expect(active(), isTrue);
            printed = b;
            return false;
          }),
        ]);
    await tester.tap(find.text('PDF 저장·공유'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('프린터 인쇄'));
    await tester.pumpAndSettle();
    expect(identical(saved, pdf), isTrue);
    expect(identical(printed, pdf), isTrue);
    expect(accesses, 2);
  });
  testWidgets('PDF permission failure offers basic preview explanation',
      (tester) async {
    await pump(
        tester,
        PurchasePdfPreview(
            title: 'Document',
            filename: 'test',
            buildDocument: () async => throw const PostgrestException(
                message: 'PDF_MEMBERSHIP_REQUIRED')),
        []);
    expect(find.textContaining('플러스·비즈니스'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
  testWidgets('account switch removes private ledger rows', (tester) async {
    final repo = LedgerRepo();
    await pump(tester, const RequestLedgerPage(),
        [requestLedgerRepositoryProvider.overrideWithValue(repo)]);
    final scope = ProviderScope.containerOf(
        tester.element(find.byType(RequestLedgerPage)));
    scope.read(testOwner.notifier).state = null;
    await tester.pumpAndSettle();
    expect(find.text('로그인'), findsOneWidget);
    expect(find.textContaining('늘푸른'), findsNothing);
  });
}
