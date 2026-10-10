import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../auth/application/auth_providers.dart';
import '../data/purchase_cleanup_repository.dart';
import 'shopping_assistant_dialogs.dart';
export 'owner_record_management.dart';

class RecordManagementAction {
  const RecordManagementAction(this.id, this.label, this.icon, this.run);
  final String id, label;
  final IconData icon;
  final Future<void> Function() run;
}

/// One operation at a time; failures remain visible and never imply success.
class RecordManagementMenu extends StatefulWidget {
  const RecordManagementMenu({super.key, required this.actions, this.onError});
  final List<RecordManagementAction> actions;
  final String Function(Object)? onError;
  @override
  State<RecordManagementMenu> createState() => _RecordManagementMenuState();
}

class _RecordManagementMenuState extends State<RecordManagementMenu> {
  bool _busy = false;
  @override
  Widget build(BuildContext context) => _busy
      ? const IconButton(onPressed: null, icon: Icon(Icons.hourglass_top))
      : PopupMenuButton<String>(
          tooltip: shopText(context, '관리', 'Manage'),
          enabled: widget.actions.isNotEmpty,
          icon: const Icon(Icons.more_horiz),
          itemBuilder: (_) => [
                for (final a in widget.actions)
                  PopupMenuItem(
                      value: a.id,
                      child: Row(children: [
                        Icon(a.icon, size: 20),
                        const SizedBox(width: 10),
                        Flexible(child: Text(a.label)),
                      ])),
              ],
          onSelected: (id) async {
            final action = widget.actions.where((a) => a.id == id).firstOrNull;
            if (_busy || action == null) return;
            setState(() => _busy = true);
            try {
              await action.run();
            } catch (e) {
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                    content: Text(widget.onError?.call(e) ??
                        shopText(context, '처리하지 못했습니다. 새로고침 후 다시 확인해 주세요.',
                            'Could not complete. Refresh and check again.'))));
              }
            } finally {
              if (mounted) setState(() => _busy = false);
            }
          });
}

Future<bool> confirmRecordManagement(
        BuildContext context, String title, String message) async =>
    await showDialog<bool>(
      context: context,
      builder: (ctx) => ShoppingAccountGuard(
          child: AlertDialog(
        scrollable: true,
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text(shopText(ctx, '취소', 'Cancel'))),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: Text(shopText(ctx, '확인', 'Confirm'))),
        ],
      )),
    ) ==
    true;

/// Fetch the latest archive token, then recheck it atomically on the server.
Future<bool> managePurchaseArchive(BuildContext context, WidgetRef ref,
    {String? workspace,
    required String kind,
    required String id,
    required String title}) async {
  final account = ref.read(activeAccountIdProvider);
  if (account == null) return false;
  final repo = ref.read(purchaseCleanupRepositoryProvider);
  final index = await repo.index(workspace);
  if (!index.available) throw StateError('CLEANUP_UNAVAILABLE');
  final archived = index.contains(kind, id);
  final rows = await repo.list(
      workspace: workspace, kind: kind, archived: archived, query: id);
  final row = rows.where((r) => r.id == id).firstOrNull;
  if (row == null || !row.eligible) throw StateError('CLEANUP_ACTIVE');
  if (!context.mounted || account != ref.read(activeAccountIdProvider)) {
    return false;
  }
  final yes = await confirmRecordManagement(
      context,
      shopText(context, archived ? '기록 복원' : '기록 보관',
          archived ? 'Restore record' : 'Archive record'),
      '$title\n${shopText(context, '목록 표시만 변경합니다. 재고·금액과 처리 이력은 유지됩니다.', 'Only list visibility changes. Stock, totals and history are preserved.')}');
  if (!yes ||
      !context.mounted ||
      account != ref.read(activeAccountIdProvider)) {
    return false;
  }
  await repo.apply(
      workspace: workspace, kind: kind, entries: [row], archive: !archived);
  if (!context.mounted || account != ref.read(activeAccountIdProvider)) {
    return false;
  }
  ref.invalidate(purchaseCleanupIndexProvider(workspace));
  return true;
}
