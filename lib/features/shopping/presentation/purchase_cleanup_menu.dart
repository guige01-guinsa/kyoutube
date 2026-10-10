import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../auth/application/auth_providers.dart';
import 'shopping_assistant_dialogs.dart';

class PurchaseCleanupMenu extends ConsumerWidget {
  const PurchaseCleanupMenu({super.key, this.workspace});
  final String? workspace;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (ref.watch(activeAccountIdProvider) == null) {
      return const SizedBox.shrink();
    }
    String t(String ko, String en) => shopText(context, ko, en);
    final base = workspace == null
        ? '/shopping/organize'
        : '/business-workspaces/$workspace/organize';
    return PopupMenuButton<String>(
        key: const Key('purchase-cleanup-menu'),
        tooltip: t('장보기 메뉴', 'Shopping menu'),
        onSelected: (value) => context.push(value),
        itemBuilder: (_) => [
              PopupMenuItem(
                  value: base, child: Text(t('기록 정리', 'Organize records'))),
              PopupMenuItem(
                  value: '$base?archived=true',
                  child: Text(t('보관함', 'Archive'))),
              if (workspace == null)
                PopupMenuItem(
                    value: '/shopping/kitchen',
                    child: Text(t('주방 정리', 'Kitchen cleanup'))),
            ]);
  }
}
