import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../auth/application/auth_providers.dart';

final chefPaidAccessProvider = FutureProvider.autoDispose<bool>((ref) {
  ref.watch(activeAccountIdProvider);
  final timer = Timer(const Duration(minutes: 1), ref.invalidateSelf);
  ref.onDispose(timer.cancel);
  return Supabase.instance.client
      .rpc('has_chef_paid_access')
      .then((value) => value == true);
});

class ChefPaidNotice extends StatelessWidget {
  const ChefPaidNotice({super.key});
  @override
  Widget build(BuildContext context) {
    final en = Localizations.localeOf(context).languageCode != 'ko';
    return Card(
        child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(children: [
              const Icon(Icons.lock_outline),
              const SizedBox(height: 8),
              Text(en
                  ? 'Cost, pricing and sales tools require an active Business membership.'
                  : '원가·판매가·매출 관리는 비즈니스 회원 전용입니다.'),
              Text(en
                  ? 'Serving scaling and recipe versions remain available.'
                  : '인분 환산과 레시피 버전 관리는 계속 사용할 수 있습니다.'),
              TextButton(
                  onPressed: () => context.push('/membership'),
                  child: Text(en ? 'Membership' : '회원 및 구독 관리')),
            ])));
  }
}
