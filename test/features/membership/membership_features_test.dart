import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:k_youtube/features/auth/application/auth_providers.dart';
import 'package:k_youtube/features/membership/application/membership_providers.dart';
import 'package:k_youtube/features/membership/data/membership_features_repository.dart';
import 'package:k_youtube/features/membership/domain/membership_features.dart';

Map<String, dynamic> features({bool paid = false, int video = 0}) => {
      'schema_version': 1,
      'can_manage_costs': paid,
      'can_manage_sales': paid,
      'can_share_request_pdf': true,
      'video_monthly_limit': video,
      'supplier_limit': 200,
      'request_monthly_limit': null,
    };

User account(String id) => User(
    id: id,
    appMetadata: {},
    userMetadata: {},
    aud: 'authenticated',
    createdAt: '2026-09-13');

void main() {
  test('capabilities are read independently of billing names', () async {
    final repository = MembershipFeaturesRepository(
        rpc: (_) async => features(paid: true, video: 5));
    final result = await repository.load();
    expect(result.canManageCosts, isTrue);
    expect(result.videoMonthlyLimit, 5);
    expect(result.requestMonthlyLimit, isNull);
  });

  test('malformed or future capability schemas never grant paid access', () {
    for (final data in [
      {...features(), 'schema_version': 2},
      {...features(), 'can_manage_costs': 'true'},
      {...features(), 'video_monthly_limit': -1},
      {...features(), 'supplier_limit': 3.5},
      {...features(), 'request_monthly_limit': -1},
    ]) {
      expect(() => MembershipFeatures.fromJson(data), throwsFormatException);
    }
  });

  for (final code in ['42501', 'PGRST301', 'PGRST204', 'PGRST202']) {
    test('server failure $code is not a compatibility grant', () async {
      var calls = 0;
      final repository = MembershipFeaturesRepository(rpc: (_) async {
        calls++;
        throw PostgrestException(message: 'fixture failure', code: code);
      });
      await expectLater(repository.load(), throwsA(isA<PostgrestException>()));
      expect(calls, 1);
    });
  }

  test('late paid response cannot replace free account after switch or logout',
      () async {
    final users = StreamController<User?>();
    final pending = Completer<dynamic>();
    var calls = 0;
    final container = ProviderContainer(overrides: [
      authUserProvider.overrideWith((_) => users.stream),
      membershipFeaturesRepositoryProvider.overrideWithValue(
        MembershipFeaturesRepository(
            rpc: (_) =>
                ++calls == 1 ? pending.future : Future.value(features())),
      ),
    ]);
    addTearDown(container.dispose);
    addTearDown(users.close);
    users.add(account('A'));
    await container.read(authUserProvider.future);
    final sub = container.listen(membershipFeaturesProvider, (_, __) {});
    addTearDown(sub.close);
    await Future<void>.delayed(Duration.zero);
    users.add(account('B'));
    await Future<void>.delayed(Duration.zero);
    expect(
        (await container.read(membershipFeaturesProvider.future))
            .canManageCosts,
        isFalse);
    pending.complete(features(paid: true));
    await Future<void>.delayed(Duration.zero);
    expect(
        container.read(membershipFeaturesProvider).requireValue.canManageCosts,
        isFalse);
    users.add(null);
    await Future<void>.delayed(Duration.zero);
    expect(container.read(membershipFeaturesProvider).hasError, isTrue);
    expect(calls, 2);
  });
}
