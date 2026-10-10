import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:k_youtube/features/auth/application/auth_providers.dart';
import 'package:k_youtube/features/membership/application/membership_providers.dart';
import 'package:k_youtube/features/membership/domain/membership.dart';
import 'package:k_youtube/features/shopping/data/shopping_affiliate_repository.dart';
import 'package:k_youtube/features/shopping/domain/shopping_affiliate.dart';
import 'package:k_youtube/features/shopping/domain/affiliate_review.dart';
import 'package:k_youtube/features/shopping/presentation/affiliate_display_page.dart';

void main() {
  test('draft checklist does not imply verification or publication', () {
    final row = <String, dynamic>{'program': 'coupang'};
    final tasks = affiliateReviewTasks(row);
    expect(tasks.length, 5);
    expect(row.containsKey('product_verified'), isFalse);
    expect(row.containsKey('published'), isFalse);
  });
  test('expired published product requires review', () {
    final tasks = affiliateReviewTasks({
      'program': 'coupang',
      'link': 'https://link.coupang.com/a/Valid1',
      'ingredients': ['soy'],
      'product_verified': true,
      'specification': '1.8L',
      'mobile_allowed': true,
      'review_note': 'Reviewed product and placement',
      'published': true,
      'expires_at': '2026-01-01T00:00:00Z'
    }, now: DateTime.utc(2026, 2));
    expect(tasks.single, contains('기간이 지났습니다'));
  });
  Future<void> show(WidgetTester tester, {required bool admin}) async {
    await tester.pumpWidget(ProviderScope(
        overrides: [
          activeAccountIdProvider.overrideWithValue('reviewer'),
          membershipInfoProvider.overrideWith(
              (_) async => MembershipInfo.fromJson({'is_admin': admin})),
          shoppingAffiliatesProvider('onion').overrideWith((_) async => []),
          shoppingAffiliatesProvider('soy').overrideWith((_) async => [
                ShoppingAffiliate({
                  'id': 'soy-id',
                  'program': 'coupang',
                  'title': 'Verified soy sauce',
                  'specification': '1.8L',
                  'link': 'https://link.coupang.com/a/Valid1'
                })
              ]),
        ],
        child: const MaterialApp(
            home: AffiliateDisplayPage(
                ingredient: 'onion', expectedId: 'soy-id'))));
    await tester.pumpAndSettle();
  }

  testWidgets('lookup follows edited query and shows actual published offer',
      (tester) async {
    await show(tester, admin: true);
    expect(find.textContaining('The selected product is not visible'),
        findsOneWidget);
    await tester.enterText(find.byType(TextField), 'soy');
    await tester.tap(find.text('Search / refresh'));
    await tester.pumpAndSettle();
    expect(find.text('Verified soy sauce'), findsOneWidget);
    expect(find.textContaining('The selected product is not visible'),
        findsNothing);
  });
  testWidgets('non-admin cannot access product lookup', (tester) async {
    await show(tester, admin: false);
    expect(find.byType(TextField), findsNothing);
    expect(find.textContaining('Administrator access is required'), findsOneWidget);
  });
}
