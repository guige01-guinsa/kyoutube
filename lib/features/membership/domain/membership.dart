class MembershipInfo {
  const MembershipInfo({
    required this.planCode,
    required this.displayName,
    required this.status,
    required this.priceKrw,
    required this.billingPeriod,
    required this.recipeModel,
    required this.dailyLimit,
    required this.weeklyLimit,
    required this.monthlyLimit,
    required this.dailyUsed,
    required this.weeklyUsed,
    required this.monthlyUsed,
    required this.autoRenews,
    required this.isAdmin,
    this.validUntil,
  });

  factory MembershipInfo.fromJson(Map<String, dynamic> json) {
    int number(String key) => (json[key] as num?)?.toInt() ?? 0;

    return MembershipInfo(
      planCode: json['plan_code'] as String? ?? 'free',
      displayName: json['display_name'] as String? ?? '무료 회원',
      status: json['status'] as String? ?? 'free',
      priceKrw: number('price_krw'),
      billingPeriod: json['billing_period'] as String? ?? 'none',
      recipeModel: json['recipe_model'] as String? ?? 'gpt-4o-mini',
      dailyLimit: number('daily_limit'),
      weeklyLimit: number('weekly_limit'),
      monthlyLimit: number('monthly_limit'),
      dailyUsed: number('daily_used'),
      weeklyUsed: number('weekly_used'),
      monthlyUsed: number('monthly_used'),
      validUntil: DateTime.tryParse(json['valid_until'] as String? ?? ''),
      autoRenews: json['auto_renews'] as bool? ?? false,
      isAdmin: json['is_admin'] as bool? ?? false,
    );
  }

  final String planCode;
  final String displayName;
  final String status;
  final int priceKrw;
  final String billingPeriod;
  final String recipeModel;
  final int dailyLimit;
  final int weeklyLimit;
  final int monthlyLimit;
  final int dailyUsed;
  final int weeklyUsed;
  final int monthlyUsed;
  final DateTime? validUntil;
  final bool autoRenews;
  final bool isAdmin;

  bool get isPaid => planCode != 'free';
  int get dailyRemaining => (dailyLimit - dailyUsed).clamp(0, dailyLimit);
  int get weeklyRemaining => (weeklyLimit - weeklyUsed).clamp(0, weeklyLimit);
  int get monthlyRemaining =>
      (monthlyLimit - monthlyUsed).clamp(0, monthlyLimit);
}

class ManagedMembership {
  const ManagedMembership({
    required this.userId,
    required this.email,
    required this.displayName,
    required this.profileRole,
    required this.planCode,
    required this.status,
    required this.monthlyUsed,
    this.validUntil,
  });

  factory ManagedMembership.fromJson(Map<String, dynamic> json) {
    return ManagedMembership(
      userId: json['user_id'] as String? ?? '',
      email: json['email'] as String? ?? '이메일 없음',
      displayName: json['display_name'] as String? ?? '',
      profileRole: json['profile_role'] as String? ?? 'user',
      planCode: json['plan_code'] as String? ?? 'free',
      status: json['membership_status'] as String? ?? 'free',
      monthlyUsed: (json['monthly_used'] as num?)?.toInt() ?? 0,
      validUntil: DateTime.tryParse(json['valid_until'] as String? ?? ''),
    );
  }

  final String userId;
  final String email;
  final String displayName;
  final String profileRole;
  final String planCode;
  final String status;
  final int monthlyUsed;
  final DateTime? validUntil;
}

class SubscriptionDiscountCampaign {
  const SubscriptionDiscountCampaign({
    required this.id,
    required this.name,
    required this.headlineKo,
    required this.headlineEn,
    required this.planCode,
    required this.googlePlayOfferId,
    required this.startsAt,
    required this.endsAt,
    required this.isActive,
  });

  factory SubscriptionDiscountCampaign.fromJson(Map<String, dynamic> json) {
    return SubscriptionDiscountCampaign(
      id: json['id'] as String? ?? '',
      name: json['name'] as String? ?? '',
      headlineKo: json['headline_ko'] as String? ?? '',
      headlineEn: json['headline_en'] as String? ?? '',
      planCode: json['plan_code'] as String? ?? '',
      googlePlayOfferId: json['google_play_offer_id'] as String? ?? '',
      startsAt: DateTime.tryParse(json['starts_at'] as String? ?? '') ??
          DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
      endsAt: DateTime.tryParse(json['ends_at'] as String? ?? '') ??
          DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
      isActive: json['is_active'] as bool? ?? true,
    );
  }

  final String id;
  final String name;
  final String headlineKo;
  final String headlineEn;
  final String planCode;
  final String googlePlayOfferId;
  final DateTime startsAt;
  final DateTime endsAt;
  final bool isActive;

  bool isRunningAt(DateTime now) =>
      isActive && !now.isBefore(startsAt) && now.isBefore(endsAt);

  String headlineFor(String languageCode) =>
      languageCode == 'ko' ? headlineKo : headlineEn;
}

class MembershipPlanPolicy {
  const MembershipPlanPolicy({
    required this.code,
    required this.displayName,
    required this.priceKrw,
    required this.billingPeriod,
    required this.recipeModel,
    required this.dailyLimit,
    required this.weeklyLimit,
    required this.monthlyLimit,
    required this.isActive,
    this.productId,
  });

  factory MembershipPlanPolicy.fromJson(Map<String, dynamic> json) {
    int number(String key) => (json[key] as num?)?.toInt() ?? 0;
    return MembershipPlanPolicy(
      code: json['code'] as String? ?? '',
      displayName: json['display_name'] as String? ?? '',
      productId: json['product_id'] as String?,
      priceKrw: number('price_krw'),
      billingPeriod: json['billing_period'] as String? ?? 'none',
      recipeModel: json['recipe_model'] as String? ?? 'gpt-4o-mini',
      dailyLimit: number('daily_ai_limit'),
      weeklyLimit: number('weekly_ai_limit'),
      monthlyLimit: number('monthly_ai_limit'),
      isActive: json['is_active'] as bool? ?? false,
    );
  }

  final String code;
  final String displayName;
  final String? productId;
  final int priceKrw;
  final String billingPeriod;
  final String recipeModel;
  final int dailyLimit;
  final int weeklyLimit;
  final int monthlyLimit;
  final bool isActive;

  String allowanceLabelFor(String languageCode) => languageCode == 'ko'
      ? '$dailyLimit회/일 · $weeklyLimit회/주 · $monthlyLimit회/월'
      : '$dailyLimit/day · $weeklyLimit/week · $monthlyLimit/month';
}

class YoutubeDraftSuccessStats {
  const YoutubeDraftSuccessStats({
    required this.attempts,
    required this.successes,
    required this.successRate,
    required this.transcriptAttempts,
    required this.repairedAttempts,
  });

  factory YoutubeDraftSuccessStats.fromJson(Map<String, dynamic> json) {
    int integer(String key) => (json[key] as num?)?.toInt() ?? 0;
    return YoutubeDraftSuccessStats(
      attempts: integer('attempts'),
      successes: integer('successes'),
      successRate: (json['success_rate'] as num?)?.toDouble() ?? 0,
      transcriptAttempts: integer('transcript_attempts'),
      repairedAttempts: integer('repaired_attempts'),
    );
  }

  final int attempts;
  final int successes;
  final double successRate;
  final int transcriptAttempts;
  final int repairedAttempts;
}
