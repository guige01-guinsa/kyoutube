/// Display policy for the launch tiers. Checkout identity and availability come
/// from the server catalog; price at purchase always comes from Google Play.
class BillingPlan {
  const BillingPlan(this.code, this.title, this.ai, this.video, this.suppliers,
      this.requests, this.priceKrw);
  final String code, title;
  final int ai, video, suppliers, priceKrw;
  final int? requests;
  bool get annual => code.endsWith('_annual');
  bool get business => code.startsWith('business_');
  static const plans = [
    BillingPlan('plus_monthly', '플러스 월간', 50, 5, 30, 30, 9900),
    BillingPlan('plus_annual', '플러스 연간', 50, 5, 30, 30, 99000),
    BillingPlan('business_monthly', '비즈니스 월간', 100, 20, 200, null, 19000),
    BillingPlan('business_annual', '비즈니스 연간', 100, 20, 200, null, 189000),
  ];
  static BillingPlan? byCode(String code) {
    for (final plan in plans) {
      if (plan.code == code) return plan;
    }
    return null;
  }
}

class BillingOffer {
  const BillingOffer(
      {required this.planCode,
      required this.productId,
      required this.basePlanId,
      required this.checkoutEnabled});
  factory BillingOffer.fromJson(Map<String, dynamic> json) {
    if (BillingPlan.byCode(json['plan_code'] as String? ?? '') == null ||
        json['product_id'] is! String ||
        json['base_plan_id'] is! String ||
        json['checkout_enabled'] is! bool ||
        (json['product_id'] as String).isEmpty ||
        (json['base_plan_id'] as String).isEmpty) {
      throw const FormatException('Invalid billing offer');
    }
    return BillingOffer(
        planCode: json['plan_code'] as String,
        productId: json['product_id'] as String,
        basePlanId: json['base_plan_id'] as String,
        checkoutEnabled: json['checkout_enabled'] as bool);
  }
  final String planCode, productId, basePlanId;
  final bool checkoutEnabled;
}
