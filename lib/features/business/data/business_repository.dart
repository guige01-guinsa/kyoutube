import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../auth/application/auth_providers.dart';
import '../domain/business_workspace.dart';

class BusinessRepository {
  BusinessRepository(this.client);
  final SupabaseClient client;
  Future<List<Map<String, dynamic>>> testOptions({bool admin = false}) async =>
      List<Map<String, dynamic>>.from(await client
          .rpc(admin ? 'admin_business_test_list' : 'business_test_options'));
  Future<String> startTest(
          String campaign, String language, String display) async =>
      await client.rpc('business_test_start', params: {
        'p_campaign': campaign,
        'p_language': language,
        'p_display_name': display
      }) as String;
  Future<void> resetTest(String workspace, int generation) async {
    await client.rpc('business_test_reset',
        params: {'p_workspace': workspace, 'p_generation': generation});
  }

  Future<void> createTest(String name, int days, String audience) async {
    await client.rpc('admin_business_test_create',
        params: {'p_name': name, 'p_days': days, 'p_audience': audience});
  }

  Future<void> testParticipant(
      String campaign, String email, bool active) async {
    await client.rpc('admin_business_test_participant',
        params: {'p_campaign': campaign, 'p_email': email, 'p_active': active});
  }

  Future<void> endTest(String campaign) async {
    await client
        .rpc('admin_business_test_end', params: {'p_campaign': campaign});
  }

  Future<int> cleanupTest(String campaign) async {
    final result = await client.rpc('admin_business_test_cleanup',
        params: {'p_campaign': campaign}) as Map;
    return (result['remaining'] as num).toInt();
  }

  Future<List<Map<String, dynamic>>> workspaces() async =>
      List<Map<String, dynamic>>.from(await client
          .from('business_workspaces')
          .select('id,name,owner_id')
          .order('created_at'));
  Future<BusinessContext> context(String id) async =>
      BusinessContext.fromJson(Map<String, dynamic>.from(await client
          .rpc('business_context', params: {'p_workspace': id}) as Map));
  Future<List<BusinessRecord>> records(String workspace, String kind,
          {int offset = 0}) async =>
      (await client
              .from('business_records')
              .select()
              .eq('workspace_id', workspace)
              .eq('kind', kind)
              .order('updated_at', ascending: false)
              .order('id')
              .range(offset, offset + 49))
          .map(BusinessRecord.fromJson)
          .toList();
  Future<BusinessRecord> record(String workspace, String id) async =>
      BusinessRecord.fromJson(await client
          .from('business_records')
          .select()
          .eq('workspace_id', workspace)
          .eq('id', id)
          .single());
  Future<BusinessRecord> save(BusinessRecord r) async =>
      BusinessRecord.fromJson(Map<String, dynamic>.from(
          await client.rpc('business_save_record', params: {
        'p_workspace': r.workspace,
        'p_id': r.id,
        'p_kind': r.kind,
        'p_title': r.title,
        'p_data': r.data,
        'p_revision': r.revision
      }) as Map));
  Future<BusinessRecord> transition(BusinessRecord r, String status) async =>
      BusinessRecord.fromJson(Map<String, dynamic>.from(
          await client.rpc('business_purchase_transition', params: {
        'p_workspace': r.workspace,
        'p_id': r.id,
        'p_revision': r.revision,
        'p_status': status
      }) as Map));
  Future<String> create(String name, String display) async =>
      await client.rpc('business_create',
          params: {'p_name': name, 'p_display_name': display}) as String;
  Future<String> accept(String token, String display) async => await client.rpc(
      'business_accept',
      params: {'p_token': token.trim(), 'p_display_name': display}) as String;
  Future<Map<String, dynamic>> invite(
          String workspace, String email, Set<String> permissions) async =>
      Map<String, dynamic>.from(await client.rpc('business_invite', params: {
        'p_workspace': workspace,
        'p_email': email,
        'p_permissions': permissions.toList()
      }) as Map);
  Future<void> member(String workspace, String user, Set<String> permissions,
      bool active) async {
    await client.rpc('business_member_update', params: {
      'p_workspace': workspace,
      'p_user': user,
      'p_permissions': permissions.toList(),
      'p_active': active
    });
  }

  Future<void> memberProfile(String workspace, String user,
      {required String displayName,
      required String jobTitle,
      required String workContact,
      required int revision}) async {
    await client.rpc('business_member_profile_update', params: {
      'p_workspace': workspace,
      'p_user': user,
      'p_display_name': displayName.trim(),
      'p_job_title': jobTitle.trim(),
      'p_work_contact': workContact.trim(),
      'p_revision': revision
    });
  }

  Future<List<Map<String, dynamic>>> members(String workspace) async =>
      List<Map<String, dynamic>>.from(await client
          .from('business_members')
          .select()
          .eq('workspace_id', workspace)
          .order('display_name'));
  Future<List<Map<String, dynamic>>> invites(String workspace) async =>
      List<Map<String, dynamic>>.from(await client
          .from('business_invites')
          .select('id,email,permissions,expires_at,used_at,revoked')
          .eq('workspace_id', workspace)
          .order('created_at', ascending: false)
          .limit(50));
  Future<List<Map<String, dynamic>>> accessEvents(String workspace) async =>
      List<Map<String, dynamic>>.from(await client
          .from('business_access_events')
          .select('actor_id,subject_id,action,permissions,created_at')
          .eq('workspace_id', workspace)
          .order('created_at', ascending: false)
          .order('id', ascending: false)
          .limit(50));
  Future<void> revokeInvite(String id) async {
    await client.rpc('business_invite_revoke', params: {'p_id': id});
  }

  Future<void> settings(String workspace, String name, bool approval) async {
    await client.rpc('business_settings', params: {
      'p_workspace': workspace,
      'p_name': name,
      'p_require_approval': approval
    });
  }

  Future<BusinessRecord> importRecipe(String workspace, String source) async =>
      BusinessRecord.fromJson(Map<String, dynamic>.from(await client.rpc(
          'business_import_recipe',
          params: {'p_workspace': workspace, 'p_recipe': source}) as Map));
  Future<BusinessRecord> handover(BusinessRecord r, String requestId) async =>
      BusinessRecord.fromJson(Map<String, dynamic>.from(
          await client.rpc('business_request_ingredients', params: {
        'p_request': requestId,
        'p_workspace': r.workspace,
        'p_recipe': r.id,
        'p_revision': r.revision
      }) as Map));
  Future<List<Map<String, dynamic>>> versions(
          String workspace, String id) async =>
      List<Map<String, dynamic>>.from(await client.rpc('business_versions',
          params: {'p_workspace': workspace, 'p_id': id}) as List);
  Future<void> archive(BusinessRecord record) async {
    await client.rpc('business_archive_record', params: {
      'p_workspace': record.workspace,
      'p_id': record.id,
      'p_revision': record.revision
    });
  }

  Future<Map<String, dynamic>> salesTotals(BusinessSalesQuery q) async =>
      Map<String, dynamic>.from(
          await client.rpc('business_sales_totals', params: {
        'p_workspace': q.workspace,
        'p_from': q.from,
        'p_until': q.until,
        'p_currency': q.currency
      }) as Map);
  Future<BusinessRecord> document(BusinessRecord r) async =>
      BusinessRecord.fromJson(Map<String, dynamic>.from(await client
          .rpc('business_document', params: {
        'p_workspace': r.workspace,
        'p_id': r.id,
        'p_revision': r.revision
      }) as Map));
}

final businessRepositoryProvider =
    Provider((ref) => BusinessRepository(Supabase.instance.client));
final businessWorkspacesProvider = FutureProvider.autoDispose((ref) async {
  if (ref.watch(activeAccountIdProvider) == null) {
    return <Map<String, dynamic>>[];
  }
  return ref.watch(businessRepositoryProvider).workspaces();
});
final businessContextProvider =
    FutureProvider.autoDispose.family<BusinessContext, String>((ref, id) async {
  if (ref.watch(activeAccountIdProvider) == null) {
    throw StateError('BUSINESS_AUTH');
  }
  final timer = Timer(const Duration(seconds: 60), ref.invalidateSelf);
  ref.onDispose(timer.cancel);
  return ref.watch(businessRepositoryProvider).context(id);
});
typedef BusinessListQuery = ({String workspace, String kind, int offset});
final businessRecordsProvider = FutureProvider.autoDispose
    .family<List<BusinessRecord>, BusinessListQuery>((ref, q) async {
  if (ref.watch(activeAccountIdProvider) == null) return [];
  return ref
      .watch(businessRepositoryProvider)
      .records(q.workspace, q.kind, offset: q.offset);
});
final businessRecordProvider = FutureProvider.autoDispose
    .family<BusinessRecord, ({String workspace, String id})>((ref, q) async {
  if (ref.watch(activeAccountIdProvider) == null) {
    throw StateError('BUSINESS_AUTH');
  }
  return ref.watch(businessRepositoryProvider).record(q.workspace, q.id);
});

typedef BusinessSalesQuery = ({
  String workspace,
  String from,
  String until,
  String currency
});
final businessSalesTotalsProvider = FutureProvider.autoDispose
    .family<Map<String, dynamic>, BusinessSalesQuery>((ref, q) async {
  if (ref.watch(activeAccountIdProvider) == null) {
    throw StateError('BUSINESS_AUTH');
  }
  final context = await ref.watch(businessContextProvider(q.workspace).future);
  if (!context.can('finance.read')) throw StateError('BUSINESS_DENIED');
  return ref.watch(businessRepositoryProvider).salesTotals(q);
});

final businessTestOptionsProvider = FutureProvider.autoDispose
    .family<List<Map<String, dynamic>>, bool>((ref, admin) async {
  if (ref.watch(activeAccountIdProvider) == null) return [];
  final timer = Timer(const Duration(seconds: 30), ref.invalidateSelf);
  ref.onDispose(timer.cancel);
  return ref.watch(businessRepositoryProvider).testOptions(admin: admin);
});
