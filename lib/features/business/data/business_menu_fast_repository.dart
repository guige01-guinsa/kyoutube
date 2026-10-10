import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../auth/application/auth_providers.dart';

class BusinessMenuFastRepository {
  BusinessMenuFastRepository(this.client);
  final SupabaseClient client;
  Future<Map<String, dynamic>> preview(String workspace,
          List<Map<String, dynamic>> sources, bool stock) async =>
      Map<String, dynamic>.from(await client.rpc('business_menu_fast_preview',
          params: {
            'p_workspace': workspace,
            'p_sources': sources,
            'p_use_stock': stock
          }) as Map);
  Future<void> saveDefault(
      String workspace, int revision, Map<String, dynamic> data) async {
    await client.rpc('business_ingredient_default_save', params: {
      'p_workspace': workspace,
      'p_revision': revision,
      'p_data': data
    });
  }

  Future<Map<String, dynamic>> create(Map<String, dynamic> payload) async =>
      Map<String, dynamic>.from(await client.rpc(
          payload.containsKey('p_choices')
              ? 'business_menu_batch_coupang'
              : 'business_menu_batch_create',
          params: {
            ...payload,
            if (payload.containsKey('p_choices'))
              'p_surface': kIsWeb ? 'web' : 'mobile'
          }) as Map);
  Future<Map<String, dynamic>> batch(String workspace, String id) async {
    final row = await client
        .from('business_menu_batches')
        .select('result')
        .eq('workspace_id', workspace)
        .eq('id', id)
        .single();
    return Map<String, dynamic>.from(row['result'] as Map);
  }

  Future<List<Map<String, dynamic>>> templates(String workspace) async =>
      List<Map<String, dynamic>>.from(await client
          .from('business_menu_templates')
          .select()
          .eq('workspace_id', workspace)
          .order('name')
          .limit(100));
  Future<List<Map<String, dynamic>>> recent(String workspace) async =>
      List<Map<String, dynamic>>.from(await client
          .from('business_menu_batches')
          .select('id,sources,result,delivery_date,created_at')
          .eq('workspace_id', workspace)
          .order('created_at', ascending: false)
          .limit(30));
  Future<void> saveTemplate(String workspace, String id, String name,
      List<Map<String, dynamic>> sources) async {
    await updateTemplate(workspace, id, 0, name, sources);
  }

  Future<void> updateTemplate(String workspace, String id, int revision,
      String name, List<Map<String, dynamic>> sources) async {
    await client.rpc('business_menu_template_save', params: {
      'p_workspace': workspace,
      'p_id': id,
      'p_revision': revision,
      'p_name': name,
      'p_sources': sources
    });
  }

  Future<void> manageTemplate(
      String workspace, String id, int revision, String action,
      {String? name}) async {
    await client.rpc('business_menu_template_manage', params: {
      'p_workspace': workspace,
      'p_id': id,
      'p_revision': revision,
      'p_action': action,
      'p_name': name,
    });
  }
}

final businessMenuFastRepositoryProvider = Provider((ref) {
  ref.watch(activeAccountIdProvider);
  return BusinessMenuFastRepository(Supabase.instance.client);
});
