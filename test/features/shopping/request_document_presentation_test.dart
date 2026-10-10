import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:k_youtube/core/theme/app_theme.dart';
import 'package:k_youtube/features/shopping/presentation/supplier_request_document.dart';
import 'package:k_youtube/features/shopping/presentation/supplier_requests_page.dart';
import 'supplier_request_test.dart' show sampleRequest;
import 'supplier_request_widget_test.dart' show pumpRequest, RequestRepo;

void main() {
  setUpAll(() async {
    if (!const bool.fromEnvironment('REQUEST_DOCUMENT_CAPTURE')) return;
    final bytes = ByteData.sublistView(
        await File('assets/fonts/NanumGothic-Regular.ttf').readAsBytes());
    for (final family in ['Ahem', 'Roboto', 'RecipeScoutKR']) {
      await (FontLoader(family)..addFont(Future.value(bytes))).load();
    }
    await (FontLoader('MaterialIcons')
          ..addFont(Future.value(ByteData.sublistView(await File(
                  '.fvm/flutter_sdk/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf')
              .readAsBytes()))))
        .load();
  });
  for (final language in ['ko', 'en']) {
    testWidgets(
        '$language document keeps totals readable at 320px and 200% text',
        (tester) async {
      tester.view.physicalSize = const Size(320, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(MaterialApp(
        theme: AppTheme.light,
        locale: Locale(language),
        supportedLocales: const [Locale('ko'), Locale('en')],
        localizationsDelegates: const [
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
                child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: SupplierRequestDocument(request: sampleRequest())))),
      ));
      await tester.pumpAndSettle();
      expect(find.text(sampleRequest().reference), findsOneWidget);
      await tester
          .ensureVisible(find.byKey(const Key('request-document-subtotal')));
      await tester.pumpAndSettle();
      expect(find.text('10,000 KRW'), findsOneWidget);
      expect(
          find.text(language == 'ko'
              ? '2 개 품목은 견적 확인이 필요합니다.'
              : '2 items need a quote.'),
          findsOneWidget);
      expect(tester.takeException(), isNull);
    });
    testWidgets(
        '$language primary PDF action shares a file without changing the request',
        (tester) async {
      final repo = RequestRepo(), shares = <bool>[];
      await pumpRequest(tester, repo, shares,
          language: language,
          home: SupplierRequestDetails(request: sampleRequest()));
      expect(
          find.byKey(const Key('supplier-request-document')), findsOneWidget);
      final pdf = find.byKey(const Key('request-share-pdf'));
      expect(tester.widget<FilledButton>(pdf).onPressed, isNotNull);
      await tester.tap(pdf);
      await tester.pumpAndSettle();
      expect(shares, [true]);
      expect(repo.saves, isEmpty);
      expect(repo.rows.single.status, 'draft');
      await tester.tap(find.byKey(const Key('request-share-text')));
      await tester.pumpAndSettle();
      expect(shares, [true, false]);
      expect(tester.takeException(), isNull);
    });
  }
  testWidgets('capture document preview mobile and desktop', (tester) async {
    if (!const bool.fromEnvironment('REQUEST_DOCUMENT_CAPTURE')) return;
    final out = Directory('.artifacts/request-document-polish');
    await tester.runAsync(() => out.create(recursive: true));
    for (final language in ['ko', 'en']) {
      for (final width in [390.0, 1100.0]) {
        await pumpRequest(tester, RequestRepo(), [],
            language: language,
            home: RepaintBoundary(
                key: const Key('document-capture'),
                child: SupplierRequestDetails(request: sampleRequest())));
        tester.view.physicalSize = Size(width, width < 500 ? 1000 : 1900);
        await tester.pumpAndSettle();
        final boundary = tester.renderObject<RenderRepaintBoundary>(
            find.byKey(const Key('document-capture')));
        await tester.runAsync(() async {
          final image = await boundary.toImage();
          final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
          await File('${out.path}/preview-$language-${width.toInt()}.png')
              .writeAsBytes(bytes!.buffer.asUint8List());
          image.dispose();
        });
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
      }
    }
  });
}
