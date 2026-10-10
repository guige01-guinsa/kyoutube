import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../domain/purchase_request_review.dart';
import '../domain/supplier_request.dart';

abstract class PurchaseReviewRepository {
  Future<PurchaseRequestReview> review(List<SupplierRequestLine> lines,
      {required String currency, required String language});
}

class PurchaseReviewException implements Exception {
  const PurchaseReviewException(this.code);
  final String code;
}

final purchaseReviewRepositoryProvider = Provider<PurchaseReviewRepository>(
    (_) => SupabasePurchaseReviewRepository(Supabase.instance.client));

class SupabasePurchaseReviewRepository implements PurchaseReviewRepository {
  SupabasePurchaseReviewRepository(this.client);
  final SupabaseClient client;
  @override
  Future<PurchaseRequestReview> review(List<SupplierRequestLine> lines,
      {required String currency, required String language}) async {
    final user = client.auth.currentUser;
    if (user == null || user.isAnonymous) {
      throw const PurchaseReviewException('unauthorized');
    }
    final input = purchaseReviewInput(lines, currency, language);
    try {
      final response = await client.functions
          .invoke('ai_purchase_request_review', body: input);
      if (client.auth.currentUser?.id != user.id) {
        throw const PurchaseReviewException('unauthorized');
      }
      if (response.status != 200 || response.data is! Map) {
        throw const PurchaseReviewException('review_unavailable');
      }
      return PurchaseRequestReview.fromJson(
          Map<String, dynamic>.from(response.data as Map), lines);
    } on FunctionException catch (e) {
      final data = e.details;
      throw PurchaseReviewException(data is Map && data['error'] is String
          ? data['error'] as String
          : 'review_unavailable');
    }
  }
}
