import 'dart:async';
import 'package:flutter/foundation.dart';

import 'package:in_app_purchase/in_app_purchase.dart';
import 'package:in_app_purchase_android/in_app_purchase_android.dart';
import 'package:in_app_purchase_android/billing_client_wrappers.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../domain/membership.dart';
import '../domain/billing_plan.dart';

class MembershipException implements Exception {
  const MembershipException(this.message, {this.code});

  final String message;
  final String? code;

  @override
  String toString() => message;
}

class MembershipProducts {
  const MembershipProducts({
    required this.isStoreAvailable,
    required this.products,
    required this.notFoundIds,
    this.errorMessage,
    this.offers = const [],
  });

  final bool isStoreAvailable;
  final List<ProductDetails> products;
  final List<String> notFoundIds;
  final String? errorMessage;
  final List<BillingOffer> offers;

  ProductDetails? forPlan(String code) {
    final offer = offers.where((o) => o.planCode == code).firstOrNull;
    if (offer == null || !offer.checkoutEnabled) return null;
    for (final product in products.where((p) => p.id == offer.productId)) {
      if (product is! GooglePlayProductDetails) continue;
      final index = product.subscriptionIndex;
      final details = product.productDetails.subscriptionOfferDetails;
      if (index == null || details == null || index >= details.length) continue;
      final option = details[index];
      if (option.basePlanId == offer.basePlanId && option.offerId == null) {
        return product;
      }
    }
    return null;
  }

  ProductDetails? byId(String id, {String? googlePlayOfferId}) {
    final candidates = products.where((product) => product.id == id).toList();
    if (googlePlayOfferId != null && googlePlayOfferId.trim().isNotEmpty) {
      for (final product in candidates) {
        if (_googlePlayOfferId(product) == googlePlayOfferId) return product;
      }
      return null;
    }
    for (final product in candidates) {
      if (_googlePlayOfferId(product) == null) return product;
    }
    return candidates.firstOrNull;
  }

  bool hasOffer(String id, String googlePlayOfferId) =>
      byId(id, googlePlayOfferId: googlePlayOfferId) != null;

  String? _googlePlayOfferId(ProductDetails product) {
    if (product is! GooglePlayProductDetails ||
        product.subscriptionIndex == null ||
        product.productDetails.subscriptionOfferDetails == null) {
      return null;
    }
    return product.productDetails
        .subscriptionOfferDetails![product.subscriptionIndex!].offerId;
  }
}

class MembershipService {
  MembershipService({
    SupabaseClient? client,
    InAppPurchase? inAppPurchase,
  })  : _client = client ?? Supabase.instance.client,
        _store = inAppPurchase;

  static const productIds = <String>{
    'recipe_scout_plus',
    'recipe_scout_business'
  };

  final SupabaseClient _client;
  final InAppPurchase? _store;
  InAppPurchase get _inAppPurchase {
    if (kIsWeb) {
      throw const MembershipException(
          '웹에서는 기존 회원권을 사용할 수 있습니다. 신규 결제는 준비 중입니다.');
    }
    return _store ?? InAppPurchase.instance;
  }

  Stream<List<PurchaseDetails>> get purchaseUpdates =>
      kIsWeb ? const Stream.empty() : _inAppPurchase.purchaseStream;

  Future<MembershipInfo> fetchMembership() async {
    final response = await _client.functions.invoke(
      'membership',
      body: <String, dynamic>{'action': 'status'},
    );
    final payload = _payload(response.data);
    if (response.status < 200 ||
        response.status >= 300 ||
        payload['status'] != 'ok') {
      throw MembershipException(
        payload['message'] as String? ?? '회원 정보를 불러오지 못했습니다.',
        code: payload['code'] as String?,
      );
    }
    final data = payload['data'];
    if (data is! Map) {
      throw const MembershipException('회원 정보 형식이 올바르지 않습니다.');
    }
    return MembershipInfo.fromJson(Map<String, dynamic>.from(data));
  }

  Future<({int limit, int used})> fetchVideoAnalysisUsage() async {
    final rows =
        await _client.rpc<List<dynamic>>('get_my_video_analysis_usage');
    if (rows.isEmpty) {
      throw const MembershipException('영상 분석 사용 내역을 불러오지 못했습니다.');
    }
    final row = Map<String, dynamic>.from(rows.first as Map);
    return (
      limit: (row['monthly_limit'] as num).toInt(),
      used: (row['monthly_used'] as num).toInt()
    );
  }

  Future<MembershipProducts> loadProducts() async {
    if (kIsWeb) {
      return const MembershipProducts(
          isStoreAvailable: false,
          products: [],
          notFoundIds: [],
          errorMessage: '웹에서는 기존 회원권을 사용할 수 있습니다. 신규 결제는 준비 중입니다.');
    }
    final available = await _inAppPurchase.isAvailable();
    if (!available) {
      return const MembershipProducts(
        isStoreAvailable: false,
        products: <ProductDetails>[],
        notFoundIds: <String>[],
        errorMessage: 'Google Play 결제를 사용할 수 없습니다.',
      );
    }
    final rows = await _client.rpc('get_membership_billing_catalog');
    final offers = (rows as List)
        .map((r) => BillingOffer.fromJson(Map<String, dynamic>.from(r as Map)))
        .toList(growable: false);
    final response = await _inAppPurchase.queryProductDetails(
        offers.where((o) => o.checkoutEnabled).map((o) => o.productId).toSet());
    return MembershipProducts(
      isStoreAvailable: true,
      products: response.productDetails,
      notFoundIds: response.notFoundIDs,
      errorMessage: response.error?.message,
      offers: offers,
    );
  }

  Future<void> startPurchase({
    required ProductDetails product,
    required String applicationUserName,
    String? currentPlanCode,
  }) async {
    if (!productIds.contains(product.id)) {
      throw const MembershipException('지원하지 않는 구독 상품입니다.');
    }
    // Recheck both the server membership and catalog just before checkout.
    final membership = await fetchMembership();
    final current = membership.isPaid ? membership.planCode : null;
    if (current != currentPlanCode) {
      throw const MembershipException('회원 정보가 변경되었습니다. 새로고침 후 다시 선택해 주세요.');
    }
    final catalog = await loadProducts();
    final selected = catalog.offers
        .where((o) =>
            identical(catalog.forPlan(o.planCode), product) ||
            (catalog.forPlan(o.planCode) is GooglePlayProductDetails &&
                product is GooglePlayProductDetails &&
                (catalog.forPlan(o.planCode) as GooglePlayProductDetails)
                        .offerToken ==
                    product.offerToken &&
                catalog.forPlan(o.planCode)!.id == product.id))
        .firstOrNull;
    if (selected == null) throw const MembershipException('현재 구매할 수 없는 상품입니다.');
    final past = await _inAppPurchase
        .getPlatformAddition<InAppPurchaseAndroidPlatformAddition>()
        .queryPastPurchases(applicationUserName: applicationUserName);
    if (past.error != null) {
      throw const MembershipException('구독 복원 후 다시 시도해 주세요.');
    }
    final appPurchases =
        past.pastPurchases.where((p) => productIds.contains(p.productID));
    if (appPurchases.any((p) => p.status == PurchaseStatus.pending)) {
      throw const MembershipException(
          '결제 승인 대기 중입니다. Google Play에서 진행 상태를 확인해 주세요.');
    }
    if (current == null) {
      for (final purchase in appPurchases) {
        final verified = await verifyPurchase(purchase);
        if (verified.isPaid) {
          throw const MembershipException('회원 정보가 변경되었습니다. 새로고침 후 다시 선택해 주세요.');
        }
      }
    }
    ChangeSubscriptionParam? change;
    if (current != null) {
      final oldOffer =
          catalog.offers.where((o) => o.planCode == current).firstOrNull;
      if (oldOffer == null) {
        throw const MembershipException('구독 복원 후 다시 시도해 주세요.');
      }
      GooglePlayPurchaseDetails? old;
      for (final purchase in past.pastPurchases
          .where((p) => p.productID == oldOffer.productId)) {
        final verified = await verifyPurchase(purchase, requireCurrent: true);
        if (verified.planCode == current) {
          old = purchase;
          break;
        }
      }
      if (old == null) throw const MembershipException('구독 복원 후 다시 시도해 주세요.');
      change = ChangeSubscriptionParam(
          oldPurchaseDetails: old, replacementMode: ReplacementMode.deferred);
    }
    if (_client.auth.currentUser?.id != applicationUserName) {
      throw const MembershipException('로그인이 필요합니다.');
    }
    final started = await _inAppPurchase.buyNonConsumable(
      purchaseParam: GooglePlayPurchaseParam(
        productDetails: product,
        applicationUserName: applicationUserName,
        changeSubscriptionParam: change,
      ),
    );
    if (!started) {
      throw const MembershipException('Google Play 결제 화면을 열지 못했습니다.');
    }
  }

  Future<void> restorePurchases(String applicationUserName) {
    return _inAppPurchase.restorePurchases(
      applicationUserName: applicationUserName,
    );
  }

  Future<MembershipInfo> verifyPurchase(PurchaseDetails purchase,
      {bool requireCurrent = false}) async {
    if (!productIds.contains(purchase.productID)) {
      throw const MembershipException('지원하지 않는 구독 상품입니다.');
    }
    if (purchase.status != PurchaseStatus.purchased &&
        purchase.status != PurchaseStatus.restored) {
      throw const MembershipException('아직 결제가 완료되지 않았습니다.');
    }
    final token = purchase.verificationData.serverVerificationData.trim();
    if (token.isEmpty) {
      throw const MembershipException('Google Play 구매 토큰이 없습니다.');
    }
    final response = await _client.functions.invoke(
      'membership',
      body: <String, dynamic>{
        'action': 'verify_google_play',
        'productId': purchase.productID,
        'purchaseToken': token,
      },
    );
    final payload = _payload(response.data);
    if (response.status < 200 ||
        response.status >= 300 ||
        payload['status'] != 'ok') {
      throw MembershipException(
        payload['message'] as String? ?? '구독을 확인하지 못했습니다.',
        code: payload['code'] as String?,
      );
    }
    final data = payload['data'];
    if (data is! Map) {
      throw const MembershipException('구독 확인 결과가 올바르지 않습니다.');
    }
    if (requireCurrent &&
        (payload['verification'] as Map?)?['currentPurchase'] != true) {
      throw const MembershipException('구독 복원 후 다시 시도해 주세요.');
    }
    if (purchase.pendingCompletePurchase) {
      await _inAppPurchase.completePurchase(purchase);
    }
    return MembershipInfo.fromJson(Map<String, dynamic>.from(data));
  }

  Future<List<ManagedMembership>> listManagedMemberships() async {
    final rows = await _client.rpc<List<dynamic>>('admin_list_memberships');
    return rows
        .whereType<Map>()
        .map((row) => ManagedMembership.fromJson(
              Map<String, dynamic>.from(row),
            ))
        .toList(growable: false);
  }

  Future<List<SubscriptionDiscountCampaign>>
      listActiveDiscountCampaigns() async {
    final rows = await _client
        .rpc<List<dynamic>>('get_active_subscription_discount_campaigns');
    return rows
        .whereType<Map>()
        .map((row) => SubscriptionDiscountCampaign.fromJson(
              Map<String, dynamic>.from(row),
            ))
        .toList(growable: false);
  }

  Future<List<SubscriptionDiscountCampaign>>
      listManagedDiscountCampaigns() async {
    final rows = await _client
        .rpc<List<dynamic>>('admin_list_subscription_discount_campaigns');
    return rows
        .whereType<Map>()
        .map((row) => SubscriptionDiscountCampaign.fromJson(
              Map<String, dynamic>.from(row),
            ))
        .toList(growable: false);
  }

  Future<void> saveDiscountCampaign({
    String? id,
    required String name,
    required String headlineKo,
    required String headlineEn,
    required String planCode,
    required String googlePlayOfferId,
    required DateTime startsAt,
    required DateTime endsAt,
    required bool isActive,
  }) async {
    await _client.rpc<void>(
      'admin_upsert_subscription_discount_campaign',
      params: <String, dynamic>{
        'p_id': id,
        'p_name': name,
        'p_headline_ko': headlineKo,
        'p_headline_en': headlineEn,
        'p_plan_code': planCode,
        'p_google_play_offer_id': googlePlayOfferId,
        'p_starts_at': startsAt.toUtc().toIso8601String(),
        'p_ends_at': endsAt.toUtc().toIso8601String(),
        'p_is_active': isActive,
      },
    );
  }

  Future<void> deleteDiscountCampaign(String id) async {
    await _client.rpc<void>(
      'admin_delete_subscription_discount_campaign',
      params: <String, dynamic>{'p_id': id},
    );
  }

  Future<List<MembershipPlanPolicy>> listActivePlanPolicies() async {
    final rows = await _client
        .from('membership_plans')
        .select()
        .eq('is_active', true)
        .order('price_krw');
    return (rows as List<dynamic>)
        .whereType<Map>()
        .map((row) => MembershipPlanPolicy.fromJson(
              Map<String, dynamic>.from(row),
            ))
        .toList(growable: false);
  }

  Future<List<MembershipPlanPolicy>> listManagedPlanPolicies() async {
    final rows =
        await _client.rpc<List<dynamic>>('admin_list_membership_plan_policies');
    return rows
        .whereType<Map>()
        .map((row) => MembershipPlanPolicy.fromJson(
              Map<String, dynamic>.from(row),
            ))
        .toList(growable: false);
  }

  Future<YoutubeDraftSuccessStats> fetchYoutubeDraftSuccessStats({
    int days = 30,
  }) async {
    final rows = await _client.rpc<List<dynamic>>(
      'admin_get_youtube_draft_success_stats',
      params: <String, dynamic>{'p_days': days},
    );
    final row = rows.whereType<Map>().firstOrNull;
    return YoutubeDraftSuccessStats.fromJson(
      row == null ? const <String, dynamic>{} : Map<String, dynamic>.from(row),
    );
  }

  Future<void> updatePlanPolicy(MembershipPlanPolicy policy) async {
    await _client.rpc<void>(
      'admin_update_membership_plan_policy',
      params: <String, dynamic>{
        'p_plan_code': policy.code,
        'p_price_krw': policy.priceKrw,
        'p_recipe_model': policy.recipeModel,
        'p_daily_ai_limit': policy.dailyLimit,
        'p_weekly_ai_limit': policy.weeklyLimit,
        'p_monthly_ai_limit': policy.monthlyLimit,
        'p_is_active': policy.isActive,
      },
    );
  }

  Future<void> setManagedMembership({
    required String userId,
    required String planCode,
  }) async {
    DateTime? validUntil;
    if (BillingPlan.byCode(planCode)?.annual == false) {
      validUntil = DateTime.now().toUtc().add(const Duration(days: 31));
    } else if (BillingPlan.byCode(planCode)?.annual == true) {
      validUntil = DateTime.now().toUtc().add(const Duration(days: 366));
    }
    await _client.rpc<void>('admin_set_membership', params: <String, dynamic>{
      'p_user_id': userId,
      'p_plan_code': planCode,
      'p_valid_until': validUntil?.toIso8601String(),
    });
  }

  Map<String, dynamic> _payload(Object? data) {
    if (data is Map<String, dynamic>) return data;
    if (data is Map) return Map<String, dynamic>.from(data);
    return <String, dynamic>{};
  }
}
