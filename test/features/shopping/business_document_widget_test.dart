import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:k_youtube/features/shopping/data/business_document_store.dart';
import 'package:k_youtube/features/shopping/data/request_ledger_repository.dart';
import 'package:k_youtube/features/shopping/data/supplier_request_repository.dart';
import 'package:k_youtube/features/shopping/domain/business_registration.dart';
import 'package:k_youtube/features/shopping/domain/supplier_request.dart';
import 'package:k_youtube/features/shopping/presentation/business_registration_widgets.dart';
import 'package:k_youtube/features/shopping/presentation/supplier_request_editor.dart';
import 'package:k_youtube/features/shopping/presentation/request_ledger_page.dart';
import 'request_ledger_widget_test.dart' show pump, LedgerRepo;
import 'request_documents_test.dart' show certificateFixture;
import 'supplier_request_widget_test.dart' show RequestRepo;
import 'supplier_request_test.dart' show sampleRequest, sampleSupplier;

class DocumentStore extends BusinessDocumentStore {
  DocumentStore(this.bytes);
  final Uint8List bytes;
  String? downloaded;
  @override
  Future<Uint8List> download(String path) async {
    downloaded = path;
    return bytes;
  }

  @override
  Future<String> upload(Uint8List png) async => 'test-owner/certificate.png';
  @override
  Future<void> discard(String path) async {}
}

void main() {
  testWidgets('clicking registration number opens the private certificate',
      (tester) async {
    final png = await tester.runAsync(certificateFixture);
    final store = DocumentStore(png!);
    await pump(
        tester,
        const Scaffold(
            body: BusinessRegistrationLink(
                title: 'Buyer',
                registration: BusinessRegistration(
                    number: '1234567890',
                    imagePath: 'test-owner/certificate.png'))),
        [businessDocumentStoreProvider.overrideWithValue(store)]);
    await tester.tap(find.text('123-45-67890'));
    await tester.pumpAndSettle();
    expect(store.downloaded, 'test-owner/certificate.png');
    expect(find.byType(InteractiveViewer), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
  testWidgets('buyer and supplier registrations survive scrolling and saving',
      (tester) async {
    final repo = RequestRepo();
    SupplierRequest? result;
    await pump(
        tester,
        Builder(
            builder: (context) => Scaffold(
                body: TextButton(
                    onPressed: () async {
                      result = await showDialog<SupplierRequest>(
                          context: context,
                          builder: (_) => SupplierRequestEditor(
                              suppliers: const [sampleSupplier],
                              groups: const [],
                              request: sampleRequest()));
                    },
                    child: const Text('Open')))),
        [supplierRequestRepositoryProvider.overrideWithValue(repo)]);
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    for (final pair in [
      ('buyer-business', '1234567890'),
      ('supplier-business-${sampleSupplier.id}', '2345678901')
    ]) {
      final card = find.byKey(ValueKey(pair.$1));
      await tester.scrollUntilVisible(card, 180,
          scrollable: find
              .descendant(
                  of: find.byType(ListView), matching: find.byType(Scrollable))
              .first);
      await tester.enterText(
          find.descendant(of: card, matching: find.byType(TextFormField)),
          pair.$2);
      await tester.pumpAndSettle();
    }
    await tester.tap(find.text('저장하고 미리보기'));
    await tester.pumpAndSettle();
    expect(result?.buyerBusiness.formattedNumber, '123-45-67890');
    expect(result?.supplierBusiness.formattedNumber, '234-56-78901');
    expect(tester.takeException(), isNull);
  });
  testWidgets('ledger lays out at large text and desktop width',
      (tester) async {
    const key = ValueKey('ledger-review');
    await pump(
        tester,
        const RepaintBoundary(key: key, child: RequestLedgerPage()),
        [requestLedgerRepositoryProvider.overrideWithValue(LedgerRepo())],
        scale: 1.5);
    expect(tester.takeException(), isNull);
    for (final width in [360.0, 1200.0]) {
      tester.view.physicalSize = Size(width, 950);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      final boundary =
          tester.renderObject<RenderRepaintBoundary>(find.byKey(key));
      await tester.runAsync(() async {
        final image = await boundary.toImage(pixelRatio: 1);
        final data = await image.toByteData(format: ui.ImageByteFormat.png);
        final directory = Directory('.artifacts/request-documents')
          ..createSync(recursive: true);
        await File('${directory.path}/ledger-${width.toInt()}.png')
            .writeAsBytes(data!.buffer.asUint8List());
        image.dispose();
      });
    }
  });
}
