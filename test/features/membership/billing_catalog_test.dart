import 'package:flutter_test/flutter_test.dart';
import 'package:in_app_purchase_android/in_app_purchase_android.dart';
import 'package:in_app_purchase_android/billing_client_wrappers.dart';
import 'package:k_youtube/features/membership/data/membership_service.dart';
import 'package:k_youtube/features/membership/domain/billing_plan.dart';

MembershipProducts fixtureProducts(
        {bool enabled = true, bool annualOnly = false}) =>
    MembershipProducts(isStoreAvailable: true, notFoundIds: [], offers: [
      for (final plan in BillingPlan.plans)
        BillingOffer(
            planCode: plan.code,
            productId:
                plan.business ? 'recipe_scout_business' : 'recipe_scout_plus',
            basePlanId: plan.annual ? 'annual' : 'monthly',
            checkoutEnabled: enabled)
    ], products: [
      for (final product in ['recipe_scout_plus', 'recipe_scout_business'])
        ...GooglePlayProductDetails.fromProductDetails(ProductDetailsWrapper(
            productId: product,
            productType: ProductType.subs,
            title: product,
            name: product,
            description: 'Fixture',
            subscriptionOfferDetails: [
              for (final period
                  in annualOnly ? ['annual'] : ['annual', 'monthly'])
                SubscriptionOfferDetailsWrapper(
                    basePlanId: period,
                    offerTags: const [],
                    offerIdToken: '$product-$period',
                    pricingPhases: [
                      PricingPhaseWrapper(
                          billingCycleCount: 0,
                          billingPeriod: period == 'annual' ? 'P1Y' : 'P1M',
                          formattedPrice: product == 'recipe_scout_plus'
                              ? (period == 'annual' ? '₩99,000' : '₩9,900')
                              : (period == 'annual' ? '₩189,000' : '₩19,000'),
                          priceAmountMicros: (product == 'recipe_scout_plus'
                                  ? (period == 'annual' ? 99000 : 9900)
                                  : (period == 'annual' ? 189000 : 19000)) *
                              1000000,
                          priceCurrencyCode: 'KRW',
                          recurrenceMode: RecurrenceMode.infiniteRecurring)
                    ])
            ]))
    ]);

void main() {
  test('base-plan matching never buys first arbitrary annual offer', () {
    final products = fixtureProducts();
    expect(products.forPlan('plus_monthly')?.price, '₩9,900');
    expect(products.forPlan('plus_annual')?.price, '₩99,000');
    expect(products.forPlan('business_monthly')?.price, '₩19,000');
    expect(products.forPlan('business_annual')?.price, '₩189,000');
  });
  test('missing monthly plan never falls back to annual', () {
    expect(fixtureProducts(annualOnly: true).forPlan('plus_monthly'), isNull);
  });
  test('server disabled checkout wins over available Play products', () {
    expect(fixtureProducts(enabled: false).forPlan('plus_monthly'), isNull);
  });
  test('unknown catalog plan and non-boolean enablement fail closed', () {
    for (final row in [
      {
        'plan_code': 'unknown',
        'product_id': 'p',
        'base_plan_id': 'm',
        'checkout_enabled': true
      },
      {
        'plan_code': 'plus_monthly',
        'product_id': 'p',
        'base_plan_id': 'm',
        'checkout_enabled': 'true'
      }
    ]) {
      expect(() => BillingOffer.fromJson(row), throwsFormatException);
    }
  });
  test('annual and monthly tiers expose equal monthly limits', () {
    for (final tier in ['plus', 'business']) {
      final month = BillingPlan.byCode('${tier}_monthly')!;
      final year = BillingPlan.byCode('${tier}_annual')!;
      expect([month.ai, month.video, month.suppliers, month.requests],
          [year.ai, year.video, year.suppliers, year.requests]);
    }
  });
}
