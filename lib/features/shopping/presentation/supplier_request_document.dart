import '../../../core/localization/localized_text.dart';
import 'package:flutter/material.dart';
import '../domain/request_document_amounts.dart';
import '../domain/shopping_assistant.dart';
import '../domain/supplier_request.dart';
import 'shopping_assistant_dialogs.dart';

/// An accessible, responsive reading view of the same fields as the shared PDF.
class SupplierRequestDocument extends StatelessWidget {
  const SupplierRequestDocument({super.key, required this.request});
  final SupplierRequest request;
  static const _ink = Color(0xff332a32);
  static const _green = Color(0xff69445f);
  static const _muted = Color(0xff596e65);
  static const _line = Color(0xffdce5df);

  @override
  Widget build(BuildContext context) {
    final r = request;
    final en = Localizations.localeOf(context).languageCode != 'ko';
    String t(String ko, String english) => shopText(context, ko, english);
    final amounts = RequestDocumentAmounts(r.lines);
    Widget label(String text) => Text(text,
        style: const TextStyle(fontSize: 12, color: _muted, height: 1.5));
    Widget value(String text) => LocalizedText(text.isEmpty ? '—' : text,
        style: const TextStyle(fontSize: 14, color: _ink, height: 1.55));
    Widget field(String title, String text) => Padding(
        padding: const EdgeInsets.only(top: 8),
        child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [label(title), value(text)]));
    Widget heading(String number, String title) => Padding(
        padding: const EdgeInsets.only(top: 24, bottom: 12),
        child: LocalizedText('$number  $title',
            style: const TextStyle(
                fontSize: 16,
                color: _green,
                fontWeight: FontWeight.w700,
                height: 1.4)));
    Widget party(String title, String name, List<Widget> fields) => Container(
        width: double.infinity,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
            color: const Color(0xfff5f8f5),
            border: Border.all(color: _line),
            borderRadius: BorderRadius.circular(8)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          label(title),
          const SizedBox(height: 6),
          LocalizedText(name.isEmpty ? '—' : name,
              style: const TextStyle(
                  fontSize: 17,
                  color: _ink,
                  fontWeight: FontWeight.w700,
                  height: 1.4)),
          ...fields
        ]));
    final supplier = party(t('받는 업체', 'To · Supplier'), r.supplier.name, [
      if (r.supplier.contact.isNotEmpty)
        field(t('담당자', 'Contact'), r.supplier.contact),
      if (r.supplier.phone.isNotEmpty)
        field(t('업체 연락처', 'Supplier phone'), r.supplier.phone),
      if (r.supplierBusiness.number.isNotEmpty)
        field(t('사업자등록번호', 'Registration no.'),
            r.supplierBusiness.formattedNumber),
    ]);
    final buyer = party(t('보내는 업소', 'From · Buyer'), r.buyer, [
      if (r.phone.isNotEmpty) field(t('회신 연락처', 'Reply to'), r.phone),
      if (r.buyerBusiness.number.isNotEmpty)
        field(
            t('사업자등록번호', 'Registration no.'), r.buyerBusiness.formattedNumber),
    ]);
    final quantityLabel = t('구매 수량', 'Quantity');
    final priceLabel = t('요청 단가', 'Requested unit price');
    final amountLabel = t('품목 금액', 'Line amount');
    String quantity(SupplierRequestLine line) =>
        '${shoppingNumber(line.quantity)} ${requestUnit(line.unit, en)}';
    String price(SupplierRequestLine line) => line.price == null
        ? t('견적 요청', 'Quote requested')
        : '${requestMoney(line.price)} / ${requestUnit(line.unit, en)}';
    return Center(
        child: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 860),
      child: SelectionArea(
          child: Container(
        key: const Key('supplier-request-document'),
        padding:
            EdgeInsets.all(MediaQuery.sizeOf(context).width < 420 ? 16 : 28),
        decoration: BoxDecoration(
            color: Colors.white,
            border: Border.all(color: _line),
            borderRadius: BorderRadius.circular(12)),
        child: LayoutBuilder(builder: (context, constraints) {
          final wide = constraints.maxWidth >= 620 &&
              MediaQuery.textScalerOf(context).scale(14) <= 21;
          return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const LocalizedText('RECIPE SCOUT',
                    style: TextStyle(
                        fontSize: 11,
                        letterSpacing: 2,
                        color: _green,
                        fontWeight: FontWeight.w600)),
                const SizedBox(height: 10),
                Text(t('식자재 구매 요청서', 'Ingredient purchase request'),
                    style: const TextStyle(
                        fontSize: 25,
                        color: _ink,
                        fontWeight: FontWeight.w700,
                        height: 1.3)),
                field(t('요청번호', 'Request reference'), r.reference),
                if (r.createdAt != null)
                  field(
                      t('작성일', 'Created on'),
                      r.createdAt!
                          .toLocal()
                          .toIso8601String()
                          .substring(0, 10)),
                const SizedBox(height: 18),
                const Divider(color: _green, thickness: 2, height: 2),
                heading('01', t('거래 정보', 'Parties')),
                if (wide)
                  Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Expanded(child: supplier),
                    const SizedBox(width: 12),
                    Expanded(child: buyer)
                  ])
                else ...[supplier, const SizedBox(height: 12), buyer],
                if (r.deliveryDate.isNotEmpty ||
                    r.deliveryWindow.isNotEmpty ||
                    r.address.isNotEmpty) ...[
                  heading('02', t('납품 요청', 'Delivery instructions')),
                  if (r.deliveryDate.isNotEmpty || r.deliveryWindow.isNotEmpty)
                    field(t('희망 납품', 'Requested delivery'),
                        '${r.deliveryDate} ${r.deliveryWindow}'.trim()),
                  if (r.address.isNotEmpty)
                    field(t('납품 장소', 'Delivery address'), r.address),
                ],
                heading('03', t('요청 품목', 'Requested items')),
                label(
                    '${t('통화', 'Currency')}: ${r.currency} · ${r.lines.length} ${t('개 품목', 'items')}'),
                const SizedBox(height: 10),
                if (wide)
                  Table(
                      columnWidths: const {
                        0: FlexColumnWidth(4),
                        1: FlexColumnWidth(1.7),
                        2: FlexColumnWidth(2.2),
                        3: FlexColumnWidth(2)
                      },
                      border: TableBorder.all(color: _line),
                      defaultVerticalAlignment:
                          TableCellVerticalAlignment.middle,
                      children: [
                        TableRow(
                            decoration:
                                const BoxDecoration(color: Color(0xfff0e6ec)),
                            children: [
                              t('품목 / 규격', 'Item / specification'),
                              quantityLabel,
                              priceLabel,
                              amountLabel
                            ]
                                .map((text) => Padding(
                                    padding: const EdgeInsets.all(10),
                                    child: label(text)))
                                .toList()),
                        for (var i = 0; i < r.lines.length; i++)
                          TableRow(
                              children: [
                            '${i + 1}. ${r.lines[i].name}${r.lines[i].details.isEmpty ? '' : '\n${r.lines[i].details}'}',
                            quantity(r.lines[i]),
                            price(r.lines[i]),
                            requestMoney(amounts.amounts[i])
                          ]
                                  .map((text) => Padding(
                                      padding: const EdgeInsets.all(10),
                                      child: value(text)))
                                  .toList()),
                      ])
                else
                  for (var i = 0; i < r.lines.length; i++)
                    Container(
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        decoration: const BoxDecoration(
                            border: Border(bottom: BorderSide(color: _line))),
                        child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              LocalizedText('${i + 1}. ${r.lines[i].name}',
                                  style: const TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.w700,
                                      color: _ink,
                                      height: 1.4)),
                              if (r.lines[i].details.isNotEmpty) ...[
                                const SizedBox(height: 4),
                                value(r.lines[i].details)
                              ],
                              Wrap(spacing: 24, runSpacing: 4, children: [
                                field(quantityLabel, quantity(r.lines[i])),
                                field(priceLabel, price(r.lines[i])),
                                field(amountLabel,
                                    requestMoney(amounts.amounts[i])),
                              ])
                            ])),
                const SizedBox(height: 16),
                Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                        color: const Color(0xfff0e6ec),
                        borderRadius: BorderRadius.circular(8)),
                    child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          label(t('입력 금액 소계', 'Subtotal of priced items')),
                          const SizedBox(height: 6),
                          LocalizedText(
                              '${requestMoney(amounts.subtotal)} ${r.currency}',
                              key: const Key('request-document-subtotal'),
                              style: const TextStyle(
                                  fontSize: 24,
                                  color: _green,
                                  fontWeight: FontWeight.w700)),
                          if (amounts.unpricedCount > 0)
                            value(
                                '${amounts.unpricedCount} ${t('개 품목은 견적 확인이 필요합니다.', 'items need a quote.')}'),
                          const SizedBox(height: 6),
                          label(t(
                              '입력된 수량 × 단가 기준입니다. 미입력 품목·배송비·세금은 별도 확인해 주세요.',
                              'Based on entered quantity × price. Confirm unpriced items, delivery and taxes separately.')),
                        ])),
                heading('04', t('요청사항', 'Notes')),
                if (r.notes.isNotEmpty) ...[
                  value(r.notes),
                  const SizedBox(height: 12)
                ],
                value(t(
                    '납품 가능 여부와 배송비·세금을 포함한 총금액을 회신해 주세요. 대체 상품은 먼저 확인 부탁드립니다.',
                    'Please confirm availability and the total including delivery and taxes. Confirm substitutions first.')),
                const SizedBox(height: 20),
                const Divider(color: _line),
                label(t('이 문서는 구매 요청이며 결제 확인서가 아닙니다.',
                    'This is a purchase request, not proof of payment.')),
              ]);
        }),
      )),
    ));
  }
}
