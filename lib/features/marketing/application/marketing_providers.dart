import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../auth/application/auth_providers.dart';

final marketingAdminProvider = FutureProvider<bool>((ref) async {
  final user = ref.watch(authUserProvider).valueOrNull;
  if (user == null) return false;
  final row = await Supabase.instance.client
      .from('marketing_admins')
      .select('user_id')
      .eq('user_id', user.id)
      .maybeSingle();
  return row != null;
});

final marketingCampaignsProvider = FutureProvider<List<Map<String, dynamic>>>((
  ref,
) async {
  final isAdmin = await ref.watch(marketingAdminProvider.future);
  if (!isAdmin) return <Map<String, dynamic>>[];
  return Supabase.instance.client
      .from('marketing_campaigns')
      .select()
      .order('created_at', ascending: false)
      .limit(50);
});

final marketingServiceProvider = Provider((ref) => MarketingService());

class MarketingService {
  Future<void> generate(String topic) async {
    await Supabase.instance.client.functions.invoke(
      'marketing_generate',
      body: <String, dynamic>{'topic': topic},
    );
  }

  Future<void> schedule(String id, DateTime time) async {
    await Supabase.instance.client.rpc(
      'schedule_marketing_campaign',
      params: <String, dynamic>{
        'campaign_id': id,
        'publish_at': time.toUtc().toIso8601String(),
      },
    );
  }

  Future<void> cancel(String id) async {
    await Supabase.instance.client.rpc(
      'cancel_marketing_campaign',
      params: <String, dynamic>{'campaign_id': id},
    );
  }
}
