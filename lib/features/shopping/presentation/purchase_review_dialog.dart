import '../../../core/localization/localized_text.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../auth/application/auth_providers.dart';
import '../data/purchase_review_repository.dart';
import '../domain/purchase_request_review.dart';
import '../domain/request_document_amounts.dart';
import '../domain/shopping_assistant.dart';
import '../domain/supplier_request.dart';
import 'shopping_assistant_dialogs.dart';

class PurchaseReviewDialog extends ConsumerStatefulWidget {
  const PurchaseReviewDialog(
      {super.key,
      required this.lines,
      required this.currency,
      required this.onReviewed,
      this.cached});
  final List<SupplierRequestLine> lines;
  final String currency;
  final PurchaseRequestReview? cached;
  final ValueChanged<PurchaseRequestReview> onReviewed;
  @override
  ConsumerState<PurchaseReviewDialog> createState() =>
      _PurchaseReviewDialogState();
}

class _PurchaseReviewDialogState extends ConsumerState<PurchaseReviewDialog> {
  late PurchaseRequestReview? _review = widget.cached;
  final _selected = <String>{};
  bool _busy = false;
  String? _error;
  String t(String ko, String en) => shopText(context, ko, en);

  Future<void> _start() async {
    final owner = ref.read(activeAccountIdProvider);
    if (owner == null || _busy) return;
    final language = Localizations.localeOf(context).languageCode == 'es'
        ? 'es'
        : Localizations.localeOf(context).languageCode == 'en'
            ? 'en'
            : 'ko';
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final result = await ref
          .read(purchaseReviewRepositoryProvider)
          .review(widget.lines, currency: widget.currency, language: language);
      if (!mounted || ref.read(activeAccountIdProvider) != owner) return;
      widget.onReviewed(result);
      setState(() => _review = result);
    } catch (e) {
      if (!mounted || ref.read(activeAccountIdProvider) != owner) return;
      final code = e is PurchaseReviewException ? e.code : '';
      setState(() => _error = code.startsWith('ai_quota') ||
              code == 'ai_rate_limited'
          ? t('AI 이용 한도에 도달했습니다. 원본으로 계속 작성할 수 있습니다.',
              'AI usage limit reached. You can continue with the original.')
          : code == 'ai_request_in_flight'
              ? t('진행 중인 AI 작업이 있습니다. 완료 후 다시 시도해 주세요.',
                  'An AI task is already running. Try again when it finishes.')
              : t('AI 검토를 완료하지 못했습니다. 원본은 유지됩니다. 나중에 다시 시도해 주세요.',
                  'AI review could not be completed. The original is preserved. Try again later.'));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Widget _item(String label, SupplierRequestLine line) => Expanded(
      child: Padding(
          padding: const EdgeInsets.all(8),
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(label, style: Theme.of(context).textTheme.labelLarge),
            Text(line.name),
            if (line.spec.isNotEmpty) Text(line.spec),
            LocalizedText(
                '${shoppingNumber(line.quantity)} ${shopUnit(context, line.unit)}'),
          ])));

  @override
  Widget build(BuildContext context) {
    final review = _review;
    final alternative = review?.apply(widget.lines, _selected) ?? widget.lines;
    final originalAmounts = RequestDocumentAmounts(widget.lines);
    final alternativeAmounts = RequestDocumentAmounts(alternative);
    return AlertDialog(
      scrollable: true,
      title: Text(t('AI 검토·대안 비교', 'AI review and comparison')),
      content: SizedBox(
          width: 650,
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(t(
                '입력한 품목명·규격·수량·단위·단가를 AI에 보내 검토합니다. 품목 문구의 수정안과 확인사항을 제안하며, 선택한 수정만 반영합니다.',
                'Send item names, specifications, quantities, units and prices to AI for review. It suggests wording edits and checks; only selected edits are applied.')),
            const SizedBox(height: 8),
            Text(t(
                '회원 AI 한도를 함께 사용합니다. 검토 요청은 최대 20품목, 하루 5회·월 30회이며 실패한 요청도 이 요청 제한에 포함됩니다.',
                'Uses your shared member AI allowance. Reviews allow up to 20 items, 5 attempts per day and 30 per month, including failed attempts.')),
            const SizedBox(height: 8),
            Text(t('수량·단가·공급업체 변경은 직접 확인해 수정해 주세요. AI 검토로 주문이나 발송이 이루어지지 않습니다.',
                'Confirm and edit quantities, prices and suppliers yourself. AI review does not place or send orders.')),
            const Divider(height: 24),
            Text(t('입력 단가 기준 소계 (배송비·추가 세금 제외)',
                'Subtotal from entered prices (excluding delivery and additional taxes)')),
            LocalizedText(
                '${t('원본', 'Original')}: ${requestMoney(originalAmounts.subtotal)} ${widget.currency}  →  ${t('선택한 대안', 'Selected alternative')}: ${requestMoney(alternativeAmounts.subtotal)} ${widget.currency}'),
            if (originalAmounts.unpricedCount > 0)
              LocalizedText(
                  '${t('견적 필요 품목', 'Items requiring a quote')}: ${originalAmounts.unpricedCount}'),
            if (widget.lines
                .any((l) => l.quantity == null || l.unit.trim().isEmpty))
              Text(t('수량 또는 구매 단위가 비어 있는 품목을 확인해 주세요.',
                  'Check items with a missing quantity or purchase unit.')),
            if (_busy) ...[
              const SizedBox(height: 16),
              const LinearProgressIndicator(),
              Text(t('AI가 검토하고 있습니다. 자동 재시도는 하지 않습니다.',
                  'AI is reviewing. Requests are not automatically retried.')),
            ],
            if (_error != null)
              Padding(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  child: Text(_error!,
                      style: TextStyle(
                          color: Theme.of(context).colorScheme.error))),
            if (review != null) ...[
              const SizedBox(height: 16),
              Text(review.summary),
              if (review.checks.isNotEmpty) ...[
                const SizedBox(height: 12),
                Text(t('확인할 사항', 'Checks to review'),
                    style: Theme.of(context).textTheme.titleSmall),
                for (final check in review.checks)
                  Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: LocalizedText('• $check')),
              ],
              if (review.suggestions.isEmpty)
                Padding(
                    padding: const EdgeInsets.only(top: 12),
                    child: Text(t('적용할 문구 수정안이 없습니다. 확인사항을 살펴보고 원본으로 계속 작성하세요.',
                        'There are no wording edits to apply. Review the checks and continue with the original.'))),
              if (review.suggestions.isNotEmpty) ...[
                TextButton(
                    onPressed: () => setState(() {
                          if (_selected.length == review.suggestions.length) {
                            _selected.clear();
                          } else {
                            _selected.addAll(
                                review.suggestions.map((s) => s.lineId));
                          }
                        }),
                    child: Text(
                        t('모든 제안 선택·해제', 'Select or clear all suggestions'))),
                for (final suggestion in review.suggestions)
                  Builder(builder: (_) {
                    final original = widget.lines
                        .firstWhere((l) => l.id == suggestion.lineId);
                    final proposed =
                        review.apply([original], {suggestion.lineId}).single;
                    return Card(
                        child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                          CheckboxListTile(
                              value: _selected.contains(suggestion.lineId),
                              onChanged: (value) => setState(() {
                                    if (value == true) {
                                      _selected.add(suggestion.lineId);
                                    } else {
                                      _selected.remove(suggestion.lineId);
                                    }
                                  }),
                              title: Text(suggestion.reason),
                              controlAffinity: ListTileControlAffinity.leading),
                          Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                _item(t('원본', 'Original'), original),
                                _item(t('AI 제안', 'AI suggestion'), proposed),
                              ]),
                        ]));
                  }),
              ],
            ],
          ])),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(t('원본 유지', 'Keep original'))),
        if (review == null)
          FilledButton(
              onPressed: _busy ? null : _start,
              child: Text(t('AI 검토 시작', 'Start AI review'))),
        if (review != null && review.suggestions.isNotEmpty)
          FilledButton(
              onPressed: _selected.isEmpty
                  ? null
                  : () => Navigator.pop(context, alternative),
              child: Text(t('선택한 수정 반영', 'Apply selected edits'))),
      ],
    );
  }
}
