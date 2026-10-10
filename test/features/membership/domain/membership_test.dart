import 'package:flutter_test/flutter_test.dart';
import 'package:k_youtube/features/membership/domain/membership.dart';

void main() {
  test('parses a monthly paid membership and calculates remaining usage', () {
    final membership = MembershipInfo.fromJson(<String, dynamic>{
      'plan_code': 'paid_monthly',
      'display_name': '월간 유료 회원',
      'status': 'active',
      'price_krw': 9000,
      'billing_period': 'monthly',
      'recipe_model': 'gpt-5.4-mini',
      'daily_limit': 10,
      'weekly_limit': 50,
      'monthly_limit': 100,
      'daily_used': 3,
      'weekly_used': 9,
      'monthly_used': 21,
      'auto_renews': true,
      'is_admin': false,
    });

    expect(membership.isPaid, isTrue);
    expect(membership.priceKrw, 9000);
    expect(membership.dailyRemaining, 7);
    expect(membership.weeklyRemaining, 41);
    expect(membership.monthlyRemaining, 79);
  });

  test('parses the reduced free-member limits', () {
    final membership = MembershipInfo.fromJson(<String, dynamic>{
      'plan_code': 'free',
      'daily_limit': 1,
      'weekly_limit': 5,
      'monthly_limit': 10,
    });

    expect(membership.isPaid, isFalse);
    expect(membership.dailyLimit, 1);
    expect(membership.weeklyLimit, 5);
    expect(membership.monthlyLimit, 10);
  });

  test('remaining usage never becomes negative', () {
    final membership = MembershipInfo.fromJson(<String, dynamic>{
      'daily_limit': 1,
      'weekly_limit': 5,
      'monthly_limit': 10,
      'daily_used': 2,
      'weekly_used': 6,
      'monthly_used': 11,
    });

    expect(membership.dailyRemaining, 0);
    expect(membership.weeklyRemaining, 0);
    expect(membership.monthlyRemaining, 0);
  });

  test('parses a scheduled discount campaign and selects localized copy', () {
    final campaign = SubscriptionDiscountCampaign.fromJson(<String, dynamic>{
      'id': 'campaign-1',
      'name': '가을 행사',
      'headline_ko': '첫 달 50% 할인',
      'headline_en': '50% off your first month',
      'plan_code': 'paid_monthly',
      'google_play_offer_id': 'autumn-50',
      'starts_at': '2026-09-01T00:00:00Z',
      'ends_at': '2026-10-01T00:00:00Z',
      'is_active': true,
    });

    expect(campaign.googlePlayOfferId, 'autumn-50');
    expect(campaign.headlineFor('ko'), '첫 달 50% 할인');
    expect(campaign.headlineFor('en'), '50% off your first month');
    expect(
      campaign.isRunningAt(DateTime.parse('2026-09-15T00:00:00Z')),
      isTrue,
    );
    expect(
      campaign.isRunningAt(DateTime.parse('2026-10-01T00:00:00Z')),
      isFalse,
    );
  });

  test('parses an editable membership policy and formats both locales', () {
    final policy = MembershipPlanPolicy.fromJson(<String, dynamic>{
      'code': 'paid_monthly',
      'display_name': '월간 유료 회원',
      'product_id': 'recipe_scout_premium_monthly',
      'price_krw': 9000,
      'billing_period': 'monthly',
      'recipe_model': 'gpt-5.4-mini',
      'daily_ai_limit': 10,
      'weekly_ai_limit': 50,
      'monthly_ai_limit': 100,
      'is_active': true,
    });

    expect(policy.productId, 'recipe_scout_premium_monthly');
    expect(policy.allowanceLabelFor('ko'), '10회/일 · 50회/주 · 100회/월');
    expect(policy.allowanceLabelFor('en'), '10/day · 50/week · 100/month');
  });
}
