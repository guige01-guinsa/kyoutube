import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:k_youtube/features/auth/application/auth_providers.dart';
import 'package:k_youtube/features/shopping/data/purchase_review_repository.dart';
import 'package:k_youtube/features/shopping/data/supplier_request_repository.dart';
import 'package:k_youtube/features/shopping/domain/purchase_request_review.dart';
import 'package:k_youtube/features/shopping/domain/supplier_request.dart';
import 'package:k_youtube/features/shopping/presentation/purchase_review_dialog.dart';
import 'package:k_youtube/features/shopping/presentation/supplier_request_editor.dart';
import 'purchase_request_review_test.dart' show reviewLines, reviewData;
import 'supplier_request_widget_test.dart' show RequestRepo;

class ReviewRepo extends PurchaseReviewRepository {
  int calls = 0;
  bool fail = false;
  Completer<PurchaseRequestReview>? pending;
  @override
  Future<PurchaseRequestReview> review(List<SupplierRequestLine> lines,
      {required String currency, required String language}) async {
    calls++;
    if (fail) throw const PurchaseReviewException('ai_quota_daily');
    return pending == null
        ? PurchaseRequestReview.fromJson(reviewData(), lines)
        : pending!.future;
  }
}

Future<void> open(
    WidgetTester tester, ReviewRepo repo, RequestRepo requests) async {
  tester.view.physicalSize = const Size(390, 1000);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  const supplier = ShoppingSupplier(id: 's', name: 'Foods');
  await tester.pumpWidget(ProviderScope(
      overrides: [
        activeAccountIdProvider.overrideWithValue('owner'),
        purchaseReviewRepositoryProvider.overrideWithValue(repo),
        supplierRequestRepositoryProvider.overrideWithValue(requests),
      ],
      child: const MaterialApp(
          locale: Locale('en'),
          supportedLocales: [Locale('en'), Locale('ko')],
          localizationsDelegates: GlobalMaterialLocalizations.delegates,
          home: SupplierRequestEditor(
              suppliers: [supplier],
              groups: [],
              request: SupplierRequest(
                  id: 'request',
                  supplier: supplier,
                  lines: reviewLines,
                  buyer: 'Kitchen')))));
  await tester.pumpAndSettle();
}

Future<void> showReview(WidgetTester tester) async {
  final button = find.text('Create AI review and alternative');
  await tester.scrollUntilVisible(button, 300,
      scrollable: find.byType(Scrollable).first);
  await tester.tap(button);
  await tester.pumpAndSettle();
}

void main() {
  testWidgets(
      'explicit start, partial apply, undo and cached comparison never auto-save',
      (tester) async {
    final repo = ReviewRepo(), requests = RequestRepo();
    await open(tester, repo, requests);
    await showReview(tester);
    expect(repo.calls, 0);
    await tester.tap(find.text('Start AI review'));
    await tester.pumpAndSettle();
    expect(repo.calls, 1);
    expect(requests.saves, isEmpty);
    final boxes = find.byType(CheckboxListTile);
    await tester.ensureVisible(boxes.first);
    await tester.tap(boxes.first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Apply selected edits'));
    await tester.pumpAndSettle();
    final undo = find.text('Restore items before AI edits');
    await tester.ensureVisible(undo);
    await tester.tap(undo);
    await tester.pumpAndSettle();
    await showReview(tester);
    expect(find.text('Start AI review'), findsNothing);
    expect(repo.calls, 1);
    await tester.tap(find.text('Keep original'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Save and preview'));
    await tester.pumpAndSettle();
    expect(requests.saves, hasLength(1));
    expect(purchaseReviewFingerprint(requests.saves.single.lines),
        purchaseReviewFingerprint(reviewLines));
    expect(tester.takeException(), isNull);
  });
  testWidgets('quota failure preserves manual save', (tester) async {
    final repo = ReviewRepo()..fail = true;
    final requests = RequestRepo();
    await open(tester, repo, requests);
    await showReview(tester);
    await tester.tap(find.text('Start AI review'));
    await tester.pumpAndSettle();
    expect(
        find.text(
            'AI usage limit reached. You can continue with the original.'),
        findsOneWidget);
    await tester.tap(find.text('Keep original'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Save and preview'));
    await tester.pumpAndSettle();
    expect(requests.saves.single.lines.first.name, 'Carrot');
    expect(repo.calls, 1);
  });
  testWidgets('closing pending review ignores late result', (tester) async {
    final repo = ReviewRepo()..pending = Completer<PurchaseRequestReview>();
    final requests = RequestRepo();
    await open(tester, repo, requests);
    await showReview(tester);
    await tester.tap(find.text('Start AI review'));
    await tester.pump();
    await tester.tap(find.text('Keep original'));
    await tester.pumpAndSettle();
    repo.pending!
        .complete(PurchaseRequestReview.fromJson(reviewData(), reviewLines));
    await tester.pumpAndSettle();
    expect(find.byType(PurchaseReviewDialog), findsNothing);
    expect(requests.saves, isEmpty);
    expect(find.text('Restore items before AI edits'), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
