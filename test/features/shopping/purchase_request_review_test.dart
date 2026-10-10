import 'package:flutter_test/flutter_test.dart';
import 'package:k_youtube/features/shopping/domain/purchase_request_review.dart';
import 'package:k_youtube/features/shopping/domain/request_document_amounts.dart';
import 'package:k_youtube/features/shopping/domain/supplier_request.dart';

const reviewLines = [
  SupplierRequestLine(
      id: 'a',
      name: 'Carrot',
      quantity: 2,
      unit: 'bag',
      spec: '1kg bag',
      price: 3000,
      productUrl: 'https://food.example.com/a',
      sourceIds: ['shopping-a']),
  SupplierRequestLine(
      id: 'b', name: 'Onion', quantity: 3, unit: 'bag', spec: '2kg bag'),
];
Map<String, dynamic> reviewData() => {
      'summary': 'Review specification wording.',
      'checks': ['Onions need a quote.'],
      'suggestions': [
        {
          'line_id': 'a',
          'name': 'Carrots',
          'spec': '1kg per bag',
          'reason': 'Clarify wording.'
        },
        {
          'line_id': 'b',
          'name': 'Onions',
          'spec': '2kg per bag',
          'reason': 'Clarify wording.'
        },
      ],
    };
void main() {
  test(
      'partial apply preserves original, unselected line, price, URL and source links',
      () {
    final before = purchaseReviewFingerprint(reviewLines);
    final review = PurchaseRequestReview.fromJson(reviewData(), reviewLines);
    final next = review.apply(reviewLines, {'a'});
    expect(purchaseReviewFingerprint(reviewLines), before);
    expect(next.first.name, 'Carrots');
    expect(next.last, same(reviewLines.last));
    expect(next.first.quantity, 2);
    expect(next.first.price, 3000);
    expect(next.first.unit, 'bag');
    expect(next.first.productUrl, reviewLines.first.productUrl);
    expect(next.first.sourceIds, ['shopping-a']);
    expect(RequestDocumentAmounts(next).subtotal, 6000);
    expect(RequestDocumentAmounts(next).unpricedCount, 1);
  });
  test('apply none or all keeps unknown prices unknown', () {
    final review = PurchaseRequestReview.fromJson(reviewData(), reviewLines);
    expect(purchaseReviewFingerprint(review.apply(reviewLines, {})),
        purchaseReviewFingerprint(reviewLines));
    final all = review.apply(reviewLines, {'a', 'b'});
    expect(all.map((l) => l.name), ['Carrots', 'Onions']);
    expect(all.last.price, isNull);
  });
  test('rejects foreign IDs, duplicate changes and attempted price injection',
      () {
    for (final changes in [
      [
        {'line_id': 'unknown', 'name': 'X', 'spec': '', 'reason': 'X'}
      ],
      [reviewData()['suggestions'][0], reviewData()['suggestions'][0]],
      [
        {...reviewData()['suggestions'][0], 'price': 0}
      ],
    ]) {
      expect(
          () => PurchaseRequestReview.fromJson(
              {...reviewData(), 'suggestions': changes}, reviewLines),
          throwsFormatException);
    }
  });
  test('minimal provider input excludes product links and shopping provenance',
      () {
    final input = purchaseReviewInput(reviewLines, 'KRW', 'ko');
    expect(input.keys.toSet(), {'language', 'currency', 'lines'});
    final first = (input['lines'] as List).first as Map;
    expect(first.keys.toSet(),
        {'id', 'name', 'spec', 'quantity', 'unit', 'price'});
    expect(input.toString(), isNot(contains('https://')));
  });
  test(
      'empty, oversized and invalid numeric inputs fail before calling provider',
      () {
    expect(() => purchaseReviewInput([], 'KRW', 'ko'), throwsFormatException);
    expect(
        () => purchaseReviewInput(
            List.filled(21, reviewLines.first), 'KRW', 'ko'),
        throwsFormatException);
    expect(
        () => purchaseReviewInput([
              const SupplierRequestLine(
                  id: 'a', name: 'X', quantity: double.infinity, unit: 'kg')
            ], 'KRW', 'ko'),
        throwsFormatException);
  });
}
