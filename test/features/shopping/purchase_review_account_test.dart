import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:k_youtube/features/auth/application/auth_providers.dart';
import 'package:k_youtube/features/shopping/data/purchase_review_repository.dart';
import 'package:k_youtube/features/shopping/domain/purchase_request_review.dart';
import 'package:k_youtube/features/shopping/presentation/purchase_review_dialog.dart';
import 'package:k_youtube/features/shopping/presentation/shopping_assistant_dialogs.dart';
import 'purchase_review_widget_test.dart' show ReviewRepo, open, showReview;
import 'purchase_request_review_test.dart' show reviewLines, reviewData;
import 'supplier_request_widget_test.dart' show RequestRepo;

void main() {
  testWidgets('only selected item is saved and applying does not itself save',
      (tester) async {
    final repo = ReviewRepo(), requests = RequestRepo();
    await open(tester, repo, requests);
    await showReview(tester);
    await tester.tap(find.text('Start AI review'));
    await tester.pumpAndSettle();
    final item = find.byType(CheckboxListTile).first;
    await tester.ensureVisible(item);
    await tester.tap(item);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Apply selected edits'));
    await tester.pumpAndSettle();
    expect(requests.saves, isEmpty);
    await tester.tap(find.text('Save and preview'));
    await tester.pumpAndSettle();
    expect(
        requests.saves.single.lines.map((l) => l.name), ['Carrots', 'Onion']);
    expect(requests.saves.single.lines.first.price, 3000);
    expect(requests.saves.single.lines.last.price, isNull);
    expect(requests.saves.single.lines.first.productUrl,
        reviewLines.first.productUrl);
  });
  testWidgets(
      'changing accounts removes pending review and discards its result',
      (tester) async {
    final account = StateProvider<String?>((ref) => 'owner');
    final repo = ReviewRepo()..pending = Completer<PurchaseRequestReview>();
    var reviewed = false;
    await tester.pumpWidget(ProviderScope(
        overrides: [
          activeAccountIdProvider.overrideWith((ref) => ref.watch(account)),
          purchaseReviewRepositoryProvider.overrideWithValue(repo),
        ],
        child: MaterialApp(
            home: Builder(
                builder: (context) => Scaffold(
                    body: TextButton(
                        onPressed: () => showDialog<void>(
                            context: context,
                            builder: (_) => ShoppingAccountGuard(
                                child: PurchaseReviewDialog(
                                    lines: reviewLines,
                                    currency: 'KRW',
                                    onReviewed: (_) {
                                      reviewed = true;
                                    }))),
                        child: const Text('Open review')))))));
    await tester.tap(find.text('Open review'));
    await tester.pumpAndSettle();
    final container = ProviderScope.containerOf(
        tester.element(find.byType(PurchaseReviewDialog)));
    await tester.tap(find.text('Start AI review'));
    await tester.pump();
    container.read(account.notifier).state = 'other';
    await tester.pumpAndSettle();
    expect(find.byType(PurchaseReviewDialog), findsNothing);
    repo.pending!
        .complete(PurchaseRequestReview.fromJson(reviewData(), reviewLines));
    await tester.pumpAndSettle();
    expect(reviewed, isFalse);
    expect(tester.takeException(), isNull);
  });
}
