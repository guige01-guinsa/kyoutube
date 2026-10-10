import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:k_youtube/features/shopping/domain/business_registration.dart';
import 'package:k_youtube/features/shopping/domain/purchase_request_ledger.dart';
import 'package:k_youtube/features/shopping/domain/supplier_request.dart';
import 'package:k_youtube/features/shopping/data/business_document_store.dart';
import 'package:k_youtube/features/shopping/application/supplier_request_pdf.dart';
import 'package:k_youtube/features/shopping/application/request_ledger_documents.dart';
import 'supplier_request_test.dart' show sampleRequest, sampleSupplier;

Map<String, dynamic> ledgerFixture({int count = 2}) => {
      'total_count': count,
      'totals': [
        {
          'currency': 'KRW',
          'request_count': count,
          'cancelled_count': 0,
          'unpriced_count': count,
          'priced_total': 5000 * count
        }
      ],
      'rows': [
        for (var i = 0; i < count; i++)
          {
            'id': '61000000-0000-4000-8000-${i.toString().padLeft(12, '0')}',
            'supplier': '늘푸른 식자재 $i / Green Pantry',
            'buyer': '스카우트 키친 / Scout Kitchen',
            'buyer_number': '123-45-67890',
            'supplier_number': '234-56-78901',
            'created_at': '2026-09-16T01:00:00Z',
            'delivery_date': '2026-09-18',
            'status': i.isEven ? 'draft' : 'sent',
            'currency': 'KRW',
            'item_count': 2,
            'unpriced_count': 1,
            'priced_total': 5000
          }
      ]
    };
Future<Uint8List> certificateFixture() async {
  final loader = FontLoader('CertificateFixture')
    ..addFont(Future.value(ByteData.sublistView(
        await File('assets/fonts/NanumGothic-Regular.ttf').readAsBytes())));
  await loader.load();
  final recorder = ui.PictureRecorder();
  final canvas = ui.Canvas(recorder);
  canvas.drawRect(const ui.Rect.fromLTWH(0, 0, 600, 800),
      ui.Paint()..color = const ui.Color(0xFFF5F5ED));
  final p = (ui.ParagraphBuilder(
          ui.ParagraphStyle(fontSize: 32, fontFamily: 'CertificateFixture'))
        ..pushStyle(ui.TextStyle(color: const ui.Color(0xFF176B58)))
        ..addText(
            'TEST CERTIFICATE\n\nSAMPLE ONLY\n\n123-45-67890\n\nNot a real registration'))
      .build()
    ..layout(const ui.ParagraphConstraints(width: 500));
  canvas.drawParagraph(p, const ui.Offset(50, 100));
  final picture = recorder.endRecording();
  final image = await picture.toImage(600, 800);
  final data = await image.toByteData(format: ui.ImageByteFormat.png);
  image.dispose();
  picture.dispose();
  p.dispose();
  return data!.buffer.asUint8List();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('optional registration preserves old snapshot and validates format', () {
    final r = sampleRequest();
    expect(r.data.containsKey('business_registrations'), isFalse);
    expect(const BusinessRegistration(number: '1234567890').formattedNumber,
        '123-45-67890');
    expect(const BusinessRegistration(number: '123-45-67890').valid, isTrue);
    expect(const BusinessRegistration(number: '123').valid, isFalse);
    expect(const BusinessRegistration(imagePath: 'private.png').valid, isFalse);
    final withDocs = SupplierRequest(
        id: r.id,
        supplier: r.supplier,
        lines: r.lines,
        buyerBusiness: const BusinessRegistration(
            number: '1234567890', imagePath: 'private/buyer.png'),
        supplierBusiness: const BusinessRegistration(
            number: '2345678901', imagePath: 'private/supplier.png'));
    final roundtrip = SupplierRequest.fromJson(
        {'id': r.id, 'data': withDocs.data, 'status': 'draft', 'revision': 1});
    expect(roundtrip.repeat().buyerBusiness.imagePath, 'private/buyer.png');
    expect(roundtrip.repeat().supplierBusiness.formattedNumber, '234-56-78901');
    final text = supplierRequestText(roundtrip, english: false);
    expect(text, contains('123-45-67890'));
    expect(text, contains('234-56-78901'));
    expect(text, isNot(contains('private/')));
  });
  test('ledger CSV preserves Korean and prevents formula injection', () {
    final fixture = ledgerFixture();
    ((fixture['rows'] as List).first as Map)['supplier'] =
        ' =HYPERLINK("https://example.test")';
    final csv = utf8.decode(requestLedgerCsv(
        RequestLedgerPageData.fromJson(fixture).rows,
        english: false));
    expect(
        requestLedgerCsv(RequestLedgerPageData.fromJson(fixture).rows,
                english: false)
            .take(3),
        [239, 187, 191]);
    expect(csv, contains("\"' =HYPERLINK"));
    expect(csv, contains('스카우트 키친'));
    for (final input in [
      '=1+1',
      '+SUM(A1)',
      '-2+3',
      '@SUM(A1)',
      '\t=1',
      '\r=1',
      '\n=1'
    ]) {
      expect(ledgerCsvCell(input).startsWith('"\''), isTrue);
    }
    expect(ledgerCsvCell('A,"B"\nC'), '"A,""B""\nC"');
  });
  test('ledger query uses UTC instants and explicit pagination', () {
    expect(ledgerAmount('9007199254740993.01', 'USD'), '9007199254740993.01');
    expect(ledgerAmount('5000', 'USD'), '5000.00');
    final params = RequestLedgerFilter(
            from: DateTime(2026, 9, 1),
            before: DateTime(2026, 10, 1),
            query: ' pantry ')
        .params(offset: 50, limit: 100);
    expect(params['p_query'], 'pantry');
    expect(params['p_offset'], 50);
    expect(params['p_limit'], 100);
    expect(DateTime.parse(params['p_from']).toLocal(), DateTime(2026, 9, 1));
  });
  test('certificate processing bounds size and re-encodes a readable image',
      () async {
    await expectLater(prepareBusinessDocument(Uint8List(5 * 1024 * 1024 + 1)),
        throwsFormatException);
    final png = await prepareBusinessDocument(await certificateFixture());
    expect(png.take(4), [137, 80, 78, 71]);
    expect(png.length, lessThan(5 * 1024 * 1024));
  });
  test(
      'renders Korean/English request attachments and multi-page ledger locally',
      () async {
    final font = ByteData.sublistView(
        await File('assets/fonts/NanumGothic-Regular.ttf').readAsBytes());
    final certificate = await certificateFixture();
    final base = sampleRequest();
    final request = SupplierRequest(
        id: base.id,
        supplier: sampleSupplier,
        lines: base.lines,
        buyer: base.buyer,
        address: base.address,
        notes: base.notes,
        buyerBusiness: const BusinessRegistration(
            number: '1234567890', imagePath: 'private/buyer.png'),
        supplierBusiness: const BusinessRegistration(
            number: '2345678901', imagePath: 'private/supplier.png'));
    final out = Directory('.artifacts/request-documents')
      ..createSync(recursive: true);
    for (final english in [false, true]) {
      final bytes = await supplierRequestPdf(request, font,
          english: english,
          buyerCertificate: certificate,
          supplierCertificate: certificate);
      expect(ascii.decode(bytes.take(4).toList()), '%PDF');
      await File('${out.path}/request-${english ? 'en' : 'ko'}.pdf')
          .writeAsBytes(bytes);
    }
    final ledger = await requestLedgerPdf(
        RequestLedgerPageData.fromJson(ledgerFixture(count: 200)), font,
        english: false, filterLabel: '2026-09-01 ~ 2026-09-30 · 전체 상태');
    await File('${out.path}/ledger-long.pdf').writeAsBytes(ledger);
  }, timeout: const Timeout(Duration(minutes: 2)));
}
