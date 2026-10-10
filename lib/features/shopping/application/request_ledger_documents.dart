import 'dart:typed_data';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import '../domain/purchase_request_ledger.dart';
import '../domain/supplier_request.dart';

Future<Uint8List> requestLedgerPdf(
    RequestLedgerPageData data, ByteData fontData,
    {required bool english, required String filterLabel}) async {
  String t(String ko, String en) => english ? en : ko;
  final font = pw.Font.ttf(fontData);
  final green = PdfColor.fromHex('#176B58');
  final doc = pw.Document(
      title: t('구매요청 대장', 'Purchase request ledger'), author: 'Recipe Scout');
  doc.addPage(pw.MultiPage(
      pageFormat: PdfPageFormat.a4.landscape,
      margin: const pw.EdgeInsets.all(28),
      maxPages: 100,
      theme: pw.ThemeData.withFont(base: font, bold: font),
      header: (c) =>
          pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
            pw.Text('RECIPE SCOUT',
                style:
                    pw.TextStyle(fontSize: 9, color: green, letterSpacing: 2)),
            pw.SizedBox(height: 5),
            pw.Text(t('구매요청 대장', 'Purchase request ledger'),
                style: pw.TextStyle(fontSize: 22, color: green)),
            pw.SizedBox(height: 5),
            pw.Text(filterLabel, style: const pw.TextStyle(fontSize: 9)),
            pw.SizedBox(height: 12),
          ]),
      footer: (c) => pw.Padding(
          padding: const pw.EdgeInsets.only(top: 8),
          child: pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              children: [
                pw.Text(
                    t('요청 기록 · 결제/세금계산서 아님',
                        'Request records · not proof of payment or tax invoice'),
                    style: const pw.TextStyle(fontSize: 8)),
                pw.Text('${c.pageNumber} / ${c.pagesCount}',
                    style: const pw.TextStyle(fontSize: 8)),
              ])),
      build: (c) => [
            pw.Text(
                t('총 ${data.totalCount}건 · 합계는 취소 건 제외, 입력 단가가 있는 품목만 포함합니다. 배송비·세금은 별도 확인해 주세요.',
                    '${data.totalCount} requests · Totals exclude cancelled requests and unpriced items. Confirm delivery charges and taxes separately.'),
                style: const pw.TextStyle(fontSize: 9)),
            for (final total in data.totals)
              pw.Padding(
                  padding: const pw.EdgeInsets.only(top: 5),
                  child: pw.Text(
                      '${total.currency} ${total.amount} · ${t('견적 대기', 'Unpriced items')} ${total.unpricedCount} · ${t('취소', 'Cancelled')} ${total.cancelledCount}',
                      style: const pw.TextStyle(fontSize: 10))),
            pw.SizedBox(height: 12),
            pw.TableHelper.fromTextArray(
              headers: [
                t('요청번호 / 작성일', 'Reference / created'),
                t('공급업체 / 사업자번호', 'Supplier / registration'),
                t('요청 업소 / 사업자번호', 'Buyer / registration'),
                t('납품일 / 상태', 'Delivery / status'),
                t('품목 / 미정', 'Items / unpriced'),
                t('단가 입력분 소계', 'Entered-price subtotal')
              ],
              data: [
                for (final r in data.rows)
                  [
                    '${r.reference}\n${ledgerDate(r.createdAt)}',
                    '${r.supplier}\n${r.supplierNumber}',
                    '${r.buyer}\n${r.buyerNumber}',
                    '${r.deliveryDate}\n${requestStatus(r.status, english)}',
                    '${r.itemCount} / ${r.unpricedCount}',
                    '${r.currency} ${r.amount}'
                  ]
              ],
              columnWidths: {
                0: const pw.FlexColumnWidth(1.7),
                1: const pw.FlexColumnWidth(1.4),
                2: const pw.FlexColumnWidth(1.4),
                3: const pw.FlexColumnWidth(1.4),
                4: const pw.FlexColumnWidth(.7),
                5: const pw.FlexColumnWidth(1.2)
              },
              cellStyle: const pw.TextStyle(fontSize: 8),
              headerStyle:
                  const pw.TextStyle(fontSize: 8, color: PdfColors.white),
              headerDecoration: pw.BoxDecoration(color: green),
              oddRowDecoration:
                  pw.BoxDecoration(color: PdfColor.fromHex('#F1F6F2')),
              cellPadding: const pw.EdgeInsets.all(6),
              border: pw.TableBorder.all(color: PdfColors.grey300, width: .4),
            ),
          ]));
  return doc.save();
}
