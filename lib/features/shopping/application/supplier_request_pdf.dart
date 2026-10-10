import 'dart:typed_data';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import '../domain/shopping_assistant.dart';
import '../domain/supplier_request.dart';
import '../domain/request_document_amounts.dart';

/// All layout and fonts are local. Supplier/customer data never goes to a PDF service.
Future<Uint8List> supplierRequestPdf(SupplierRequest r, ByteData fontData,
    {required bool english,
    bool practice = false,
    Uint8List? buyerCertificate,
    Uint8List? supplierCertificate}) async {
  String t(String ko, String en) => english ? en : ko;
  final font = pw.Font.ttf(fontData);
  final ink = PdfColor.fromHex('#203E36');
  final green = PdfColor.fromHex('#176B58');
  final mint = PdfColor.fromHex('#E5F1E9');
  final doc = pw.Document(title: r.reference, author: 'Recipe Scout');
  final border = PdfColor.fromHex('#DCE5DF');
  final muted = PdfColor.fromHex('#596E65');
  final amounts = RequestDocumentAmounts(r.lines);
  pw.Widget detail(String label, String value) => pw.Padding(
      padding: const pw.EdgeInsets.only(top: 7),
      child:
          pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
        pw.Text(label, style: pw.TextStyle(fontSize: 8, color: muted)),
        pw.SizedBox(height: 3),
        pw.Text(value.isEmpty ? '—' : value,
            style: pw.TextStyle(fontSize: 10, color: ink, lineSpacing: 2)),
      ]));
  pw.Widget section(String number, String title) => pw.Padding(
      padding: const pw.EdgeInsets.only(top: 16, bottom: 9),
      child: pw.Text('$number  $title',
          style: pw.TextStyle(fontSize: 12, color: green)));
  pw.Widget registration(String number, String destination, bool attached) {
    final text = detail(t('사업자등록번호', 'Registration no.'), number);
    return attached ? pw.Link(destination: destination, child: text) : text;
  }

  pw.Widget party(String title, String name, List<pw.Widget> fields) =>
      pw.Container(
          padding: const pw.EdgeInsets.all(12),
          decoration: pw.BoxDecoration(
              color: PdfColor.fromHex('#F5F8F5'),
              border: pw.Border.all(color: border, width: .6),
              borderRadius: pw.BorderRadius.circular(5)),
          child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Text(title, style: pw.TextStyle(fontSize: 8, color: muted)),
                pw.SizedBox(height: 6),
                pw.Text(name.isEmpty ? '—' : name,
                    style:
                        pw.TextStyle(fontSize: 13, color: ink, lineSpacing: 2)),
                ...fields,
              ]));

  doc.addPage(pw.MultiPage(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.all(36),
      maxPages: 50,
      theme: pw.ThemeData.withFont(
          base: font, bold: font, italic: font, boldItalic: font),
      header: (ctx) => pw.Container(
          margin: const pw.EdgeInsets.only(bottom: 6),
          padding: const pw.EdgeInsets.only(bottom: 12),
          decoration: pw.BoxDecoration(
              border: pw.Border(bottom: pw.BorderSide(color: green, width: 2))),
          child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Text('RECIPE SCOUT',
                    style: pw.TextStyle(
                        color: green, fontSize: 10, letterSpacing: 2)),
                pw.SizedBox(height: 7),
                if (practice)
                  pw.Text(t('연습용 · 실제 주문 아님', 'PRACTICE ONLY · NOT AN ORDER'),
                      style: pw.TextStyle(color: green, fontSize: 13)),
                pw.Text(t('식자재 구매 요청서', 'Ingredient purchase request'),
                    style: pw.TextStyle(
                        color: ink, fontSize: ctx.pageNumber == 1 ? 25 : 18)),
                pw.SizedBox(height: 7),
                pw.Text('${t('요청번호', 'Request reference')}: ${r.reference}',
                    style: pw.TextStyle(fontSize: 8, color: muted)),
                if (r.createdAt != null) ...[
                  pw.SizedBox(height: 4),
                  pw.Text(
                      '${t('작성일', 'Created on')}: ${r.createdAt!.toLocal().toIso8601String().substring(0, 10)}',
                      style: pw.TextStyle(fontSize: 8, color: muted)),
                ],
              ])),
      footer: (ctx) => pw.Container(
          padding: const pw.EdgeInsets.only(top: 10),
          child: pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              children: [
                pw.Text(
                    practice
                        ? t('연습용 문서 · 발송/거래 효력 없음',
                            'Practice document · no order or delivery')
                        : t('구매 요청 / 납품 조건 확인 필요',
                            'Purchase request / subject to supplier confirmation'),
                    style: const pw.TextStyle(fontSize: 8)),
                pw.Text('${ctx.pageNumber} / ${ctx.pagesCount}',
                    style: const pw.TextStyle(fontSize: 9)),
              ])),
      build: (_) => [
            section('01', t('거래 정보', 'Parties')),
            pw.Row(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
              pw.Expanded(
                  child: party(t('받는 업체', 'To · Supplier'), r.supplier.name, [
                if (r.supplier.contact.isNotEmpty)
                  detail(t('담당자', 'Contact'), r.supplier.contact),
                if (r.supplier.phone.isNotEmpty)
                  detail(t('업체 연락처', 'Supplier phone'), r.supplier.phone),
                if (r.supplierBusiness.number.isNotEmpty)
                  registration(r.supplierBusiness.formattedNumber,
                      'supplier-certificate', supplierCertificate != null),
              ])),
              pw.SizedBox(width: 12),
              pw.Expanded(
                  child: party(t('보내는 업소', 'From · Buyer'), r.buyer, [
                if (r.phone.isNotEmpty)
                  detail(t('회신 연락처', 'Reply to'), r.phone),
                if (r.buyerBusiness.number.isNotEmpty)
                  registration(r.buyerBusiness.formattedNumber,
                      'buyer-certificate', buyerCertificate != null),
              ])),
            ]),
            if (r.deliveryDate.isNotEmpty ||
                r.deliveryWindow.isNotEmpty ||
                r.address.isNotEmpty) ...[
              section('02', t('납품 요청', 'Delivery instructions')),
              if (r.deliveryDate.isNotEmpty || r.deliveryWindow.isNotEmpty)
                detail(t('희망 납품', 'Requested delivery'),
                    '${r.deliveryDate} ${r.deliveryWindow}'.trim()),
              if (r.address.isNotEmpty)
                detail(t('납품 장소', 'Delivery address'), r.address),
            ],
            section('03', t('요청 품목', 'Requested items')),
            pw.Text(
                '${t('통화', 'Currency')}: ${r.currency} · ${r.lines.length} ${t('개 품목', 'items')}',
                style: pw.TextStyle(fontSize: 8, color: muted)),
            pw.SizedBox(height: 7),
            pw.TableHelper.fromTextArray(
                headers: [
                  t('품목 / 규격', 'Item / specification'),
                  t('구매 수량', 'Quantity'),
                  t('요청 단가', 'Requested unit price'),
                  t('품목 금액', 'Line amount'),
                ],
                data: [
                  for (var i = 0; i < r.lines.length; i++)
                    [
                      '${i + 1}. ${r.lines[i].name}${r.lines[i].details.isEmpty ? '' : '\n${r.lines[i].details}'}',
                      '${shoppingNumber(r.lines[i].quantity)} ${requestUnit(r.lines[i].unit, english)}',
                      r.lines[i].price == null
                          ? t('견적 요청', 'Quote requested')
                          : '${requestMoney(r.lines[i].price)} / ${requestUnit(r.lines[i].unit, english)}',
                      requestMoney(amounts.amounts[i]),
                    ]
                ],
                columnWidths: {
                  0: const pw.FlexColumnWidth(4.5),
                  1: const pw.FlexColumnWidth(1.6),
                  2: const pw.FlexColumnWidth(2.3),
                  3: const pw.FlexColumnWidth(1.9),
                },
                cellAlignments: {
                  1: pw.Alignment.centerRight,
                  2: pw.Alignment.centerRight,
                  3: pw.Alignment.centerRight
                },
                headerDecoration: pw.BoxDecoration(color: mint),
                headerStyle: pw.TextStyle(fontSize: 9, color: ink),
                cellStyle: const pw.TextStyle(fontSize: 9, lineSpacing: 3),
                cellPadding: const pw.EdgeInsets.all(8),
                cellAlignment: pw.Alignment.centerLeft,
                border: pw.TableBorder.all(color: border, width: 0.5)),
            pw.SizedBox(height: 16),
            pw.Container(
                width: double.infinity,
                padding: const pw.EdgeInsets.all(12),
                decoration: pw.BoxDecoration(
                    color: mint, borderRadius: pw.BorderRadius.circular(5)),
                child: pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      pw.Text(t('입력 금액 소계', 'Subtotal of priced items'),
                          style: pw.TextStyle(fontSize: 9, color: muted)),
                      pw.SizedBox(height: 5),
                      pw.Text('${requestMoney(amounts.subtotal)} ${r.currency}',
                          style: pw.TextStyle(fontSize: 19, color: green)),
                      if (amounts.unpricedCount > 0) ...[
                        pw.SizedBox(height: 5),
                        pw.Text(
                            '${amounts.unpricedCount} ${t('개 품목은 견적 확인이 필요합니다.', 'items need a quote.')}',
                            style: pw.TextStyle(fontSize: 9, color: ink)),
                      ],
                      pw.SizedBox(height: 6),
                      pw.Text(
                          t('입력된 수량 × 단가 기준입니다. 미입력 품목·배송비·세금은 별도 확인해 주세요.',
                              'Based on entered quantity × price. Confirm unpriced items, delivery and taxes separately.'),
                          style: pw.TextStyle(
                              fontSize: 8, color: muted, lineSpacing: 2)),
                    ])),
            section('04', t('요청사항', 'Notes')),
            if (r.notes.isNotEmpty) ...[
              pw.Text(r.notes,
                  style: const pw.TextStyle(fontSize: 10, lineSpacing: 3)),
              pw.SizedBox(height: 10),
            ],
            pw.Text(
                t('납품 가능 여부와 배송비·세금을 포함한 총금액을 회신해 주세요. 대체 상품은 먼저 확인 부탁드립니다.',
                    'Please confirm availability and the total including delivery and taxes. Confirm substitutions first.'),
                style: const pw.TextStyle(fontSize: 10, lineSpacing: 4)),
            pw.SizedBox(height: 8),
            pw.Text(
                t('이 문서는 구매 요청이며 결제 확인서가 아닙니다.',
                    'This is a purchase request, not proof of payment.'),
                style: pw.TextStyle(fontSize: 9, color: green)),
          ]));
  void appendix(
      Uint8List? bytes, String destination, String label, String number) {
    if (bytes == null) return;
    doc.addPage(pw.Page(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(36),
        theme: pw.ThemeData.withFont(base: font, bold: font),
        build: (_) => pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Anchor(
                      name: destination,
                      child: pw.Text(label,
                          style: pw.TextStyle(fontSize: 18, color: ink))),
                  pw.SizedBox(height: 8),
                  pw.Text(number),
                  pw.SizedBox(height: 6),
                  pw.Text(r.reference, style: const pw.TextStyle(fontSize: 8)),
                  pw.SizedBox(height: 14),
                  pw.Expanded(
                      child: pw.Center(
                          child: pw.Image(pw.MemoryImage(bytes),
                              fit: pw.BoxFit.contain))),
                  pw.SizedBox(height: 10),
                  pw.Text(
                      t('사용자가 첨부한 사업자등록증 사본',
                          'Business registration copy attached by the user'),
                      style: const pw.TextStyle(fontSize: 9)),
                ])));
  }

  appendix(
      buyerCertificate,
      'buyer-certificate',
      t('요청 업소 사업자등록증', 'Buyer business registration certificate'),
      r.buyerBusiness.formattedNumber);
  appendix(
      supplierCertificate,
      'supplier-certificate',
      t('공급업체 사업자등록증', 'Supplier business registration certificate'),
      r.supplierBusiness.formattedNumber);
  return doc.save();
}
