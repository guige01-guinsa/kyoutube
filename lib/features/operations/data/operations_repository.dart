import '../../auth/application/auth_providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../domain/operations_overview.dart';

final operationsRepositoryProvider =
    Provider((ref) => OperationsRepository(Supabase.instance.client));
final operationsOverviewProvider =
    FutureProvider.autoDispose.family<OperationsOverview, int>((ref, days) {
  ref.watch(activeAccountIdProvider);
  return ref.watch(operationsRepositoryProvider).load(days);
});

class OperationsRepository {
  OperationsRepository(this.client);
  final SupabaseClient client;
  Future<OperationsOverview> load(int days) async {
    final result = await client.rpc('admin_get_ops_overview',
        params: {'p_days': days}).timeout(const Duration(seconds: 15));
    return OperationsOverview.fromJson(
        Map<String, dynamic>.from(result as Map));
  }

  Future<void> saveCosts(
      {required String month,
      double? openai,
      double? other,
      required double budget}) async {
    await client.rpc('admin_set_ops_monthly_costs', params: {
      'p_month': month,
      'p_openai_usd': openai,
      'p_other_usd': other,
      'p_budget_usd': budget,
    }).timeout(const Duration(seconds: 15));
  }
}
