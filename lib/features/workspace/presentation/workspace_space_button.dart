import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/localization/app_localizations.dart';
import '../../auth/application/auth_providers.dart';
import '../../business/data/business_repository.dart';
import '../application/workspace_profile_controller.dart';
import '../domain/workspace_profile.dart';

/// A space selects data ownership. Professional preferences never grant access.
class WorkspaceModeButton extends ConsumerWidget {
  const WorkspaceModeButton({super.key, this.businessId, this.businessName});
  final String? businessId, businessName;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    String t(String ko, String english) =>
        AppLocalizations.of(context).bilingual(ko, english);
    final owner = ref.watch(activeAccountIdProvider);
    final profile = ref.watch(workspaceProfileProvider).valueOrNull;
    final supplier =
        businessId == null && profile?.active == WorkspaceMode.supplier;
    final spaces = ref.watch(businessWorkspacesProvider);
    final label = businessName ??
        (supplier
            ? t('공급업체 공간', 'Supplier space')
            : t('개인 공간', 'Personal space'));
    Future<void> select(String value) async {
      if (value == 'reload') {
        ref.invalidate(businessWorkspacesProvider);
        return;
      }
      if (value.startsWith('business:')) {
        final id = value.substring('business:'.length);
        context.go(Uri(
            pathSegments: ['', 'business-workspaces', id],
            queryParameters: const {'section': 'collection'}).toString());
      } else if (value == 'personal') {
        // The guarded switch route saves preferences only after editors allow leaving.
        context.go(profile?.active == WorkspaceMode.supplier
            ? '/workspace-switch/personal'
            : '/');
      } else if (value == 'supplier') {
        context.go('/workspace-switch/supplier');
      } else {
        context.go(owner == null ? '/login' : '/business-workspaces');
      }
    }

    return PopupMenuButton<String>(
      key: const Key('workspace-space-picker'),
      tooltip: t('사용 공간 선택', 'Choose space'),
      onSelected: select,
      itemBuilder: (_) => [
        CheckedPopupMenuItem(
            value: 'personal',
            checked: businessId == null && !supplier,
            child: Text(t('개인 공간', 'Personal space'))),
        for (final space in spaces.valueOrNull ?? <Map<String, dynamic>>[])
          CheckedPopupMenuItem(
              value: 'business:${space['id']}',
              checked: businessId == space['id'],
              child: Text(space['name'] as String)),
        if (spaces.isLoading)
          PopupMenuItem(
              enabled: false,
              child: Text(t('소속 업소를 불러오는 중', 'Loading businesses'))),
        if (spaces.hasError)
          PopupMenuItem(
              value: 'reload',
              child: Text(t('소속 업소 다시 불러오기', 'Reload businesses'))),
        if (profile?.enabled.contains(WorkspaceMode.supplier) == true)
          CheckedPopupMenuItem(
              value: 'supplier',
              checked: supplier,
              child: Text(t('공급업체 공간', 'Supplier space'))),
        const PopupMenuDivider(),
        PopupMenuItem(
            value: 'manage',
            child: Text(t('업소 만들기·초대 참여', 'Create or join a business'))),
      ],
      child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(
                businessId == null
                    ? Icons.person_outline
                    : Icons.storefront_outlined,
                size: 19),
            const SizedBox(width: 8),
            Flexible(
                child:
                    Text(label, maxLines: 1, overflow: TextOverflow.ellipsis)),
            const Icon(Icons.expand_more, size: 18),
          ])),
    );
  }
}
