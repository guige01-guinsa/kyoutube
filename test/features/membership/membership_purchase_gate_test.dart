import 'billing_catalog_test.dart' show fixtureProducts;
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:in_app_purchase/in_app_purchase.dart';
import 'package:k_youtube/features/auth/application/auth_providers.dart';
import 'package:k_youtube/features/membership/application/membership_providers.dart';
import 'package:k_youtube/features/membership/data/membership_service.dart';
import 'package:k_youtube/features/membership/domain/membership.dart';
import 'package:k_youtube/features/membership/domain/membership_features.dart';
import 'package:k_youtube/features/membership/presentation/membership_page.dart';
import 'membership_features_test.dart' show account;

class AvailableStore implements MembershipService {
  @override
  Stream<List<PurchaseDetails>> get purchaseUpdates => const Stream.empty();

  @override
  Future<MembershipProducts> loadProducts() async => fixtureProducts();

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  for (final state in [
    'loading',
    'error',
    'free',
    'plus_monthly',
    'business_annual'
  ]) {
    testWidgets(
        'checkout requires verified membership and a different selected plan: $state',
        (tester) async {
      tester.view.physicalSize = const Size(600, 4000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final pending = Completer<MembershipInfo>();
      await tester.pumpWidget(ProviderScope(overrides: [
        authUserProvider
            .overrideWith((_) => Stream.value(account('store-user'))),
        membershipServiceProvider.overrideWithValue(AvailableStore()),
        membershipInfoProvider.overrideWith((_) async {
          if (state == 'loading') return pending.future;
          if (state == 'error') throw StateError('unavailable');
          return MembershipInfo.fromJson(
              {'plan_code': state, 'status': 'active'});
        }),
        membershipFeaturesProvider.overrideWith((_) async =>
            const MembershipFeatures(
                canManageCosts: false,
                canManageSales: false,
                canShareRequestPdf: true,
                videoMonthlyLimit: 0,
                supplierLimit: 200)),
        activeDiscountCampaignsProvider.overrideWith((_) async => []),
        activeMembershipPlanPoliciesProvider.overrideWith((_) async => []),
      ], child: const MaterialApp(home: MembershipPage())));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      // ListView's explicit children keep both plan cards available for inspection.
      final buttons = tester.widgetList<FilledButton>(
          find.byType(FilledButton, skipOffstage: false));
      expect(buttons.length, 2);
      expect(
          buttons.where((button) => button.onPressed != null).length,
          state == 'free' || state == 'business_annual'
              ? 2
              : state == 'plus_monthly'
                  ? 1
                  : 0);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      if (!pending.isCompleted) {
        pending.complete(MembershipInfo.fromJson({'plan_code': 'free'}));
      }
    });
  }
}
