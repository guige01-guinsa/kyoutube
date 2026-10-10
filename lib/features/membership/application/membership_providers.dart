import '../../auth/application/auth_providers.dart';
import 'dart:async';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../data/membership_features_repository.dart';
import '../domain/membership_features.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/membership_service.dart';
import '../domain/membership.dart';

final membershipFeaturesRepositoryProvider =
    Provider<MembershipFeaturesRepository>(
  (ref) => MembershipFeaturesRepository(
      rpc: (name) async => Supabase.instance.client.rpc(name)),
);

final membershipFeaturesProvider =
    FutureProvider.autoDispose<MembershipFeatures>((ref) {
  final account = ref.watch(activeAccountIdProvider);
  if (account == null) throw StateError('AUTH_REQUIRED');
  final timer = Timer(const Duration(minutes: 1), ref.invalidateSelf);
  ref.onDispose(timer.cancel);
  return ref.watch(membershipFeaturesRepositoryProvider).load();
});

final membershipServiceProvider = Provider<MembershipService>(
  (ref) => MembershipService(),
);

final videoAnalysisUsageProvider =
    FutureProvider.autoDispose<({int limit, int used})>((ref) {
  ref.watch(activeAccountIdProvider);
  final timer = Timer(const Duration(minutes: 1), ref.invalidateSelf);
  ref.onDispose(timer.cancel);
  return ref.watch(membershipServiceProvider).fetchVideoAnalysisUsage();
});

final membershipInfoProvider = FutureProvider.autoDispose<MembershipInfo>(
  (ref) {
    ref.watch(activeAccountIdProvider);
    return ref.watch(membershipServiceProvider).fetchMembership();
  },
);

final managedMembershipsProvider =
    FutureProvider.autoDispose<List<ManagedMembership>>(
  (ref) {
    ref.watch(activeAccountIdProvider);
    return ref.watch(membershipServiceProvider).listManagedMemberships();
  },
);

final activeDiscountCampaignsProvider =
    FutureProvider.autoDispose<List<SubscriptionDiscountCampaign>>(
  (ref) {
    ref.watch(activeAccountIdProvider);
    return ref.watch(membershipServiceProvider).listActiveDiscountCampaigns();
  },
);

final managedDiscountCampaignsProvider =
    FutureProvider.autoDispose<List<SubscriptionDiscountCampaign>>(
  (ref) {
    ref.watch(activeAccountIdProvider);
    return ref.watch(membershipServiceProvider).listManagedDiscountCampaigns();
  },
);

final activeMembershipPlanPoliciesProvider =
    FutureProvider.autoDispose<List<MembershipPlanPolicy>>(
  (ref) {
    ref.watch(activeAccountIdProvider);
    return ref.watch(membershipServiceProvider).listActivePlanPolicies();
  },
);

final managedMembershipPlanPoliciesProvider =
    FutureProvider.autoDispose<List<MembershipPlanPolicy>>(
  (ref) {
    ref.watch(activeAccountIdProvider);
    return ref.watch(membershipServiceProvider).listManagedPlanPolicies();
  },
);

final youtubeDraftSuccessStatsProvider =
    FutureProvider.autoDispose<YoutubeDraftSuccessStats>(
  (ref) {
    ref.watch(activeAccountIdProvider);
    return ref.watch(membershipServiceProvider).fetchYoutubeDraftSuccessStats();
  },
);
