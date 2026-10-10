import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../auth/application/auth_providers.dart';
import '../../chef/data/chef_access.dart';
import '../../chef/data/chef_sales_repository.dart';
import '../../chef/domain/chef_sales.dart';

typedef ProfessionalSalesQuery = ({
  ChefSalesPeriod period,
  String currency,
  String date
});

/// Account-scoped; financial access is checked before querying sales.
final professionalSalesSummaryProvider = FutureProvider.autoDispose
    .family<ChefSalesTotals?, ProfessionalSalesQuery>((ref, query) async {
  if (ref.watch(activeAccountIdProvider) == null) return null;
  if (!await ref.watch(chefPaidAccessProvider.future)) return null;
  return ref.watch(chefSalesRepositoryProvider).totals(
      ChefSalesRange.forDate(DateTime.parse(query.date), query.period),
      query.currency);
});
