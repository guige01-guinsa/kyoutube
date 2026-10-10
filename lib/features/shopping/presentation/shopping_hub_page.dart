import '../../../core/auth/auth_return.dart';
import 'purchase_cleanup_menu.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/widgets/scout_navigation_bar.dart';
import '../../auth/application/auth_providers.dart';
import '../../kitchen/presentation/kitchen_page.dart';
import '../../workspace/application/workspace_navigation.dart';
import '../application/purchase_workspace.dart';
import '../domain/shopping_navigation.dart';
import 'shopping_assistant_dialogs.dart' show shopText;
import 'shopping_assistant_page.dart';
import 'shopping_preparation_page.dart';
import 'shopping_stage_tabs.dart';
import 'supplier_requests_page.dart';
import 'request_ledger_page.dart';

/// One destination; the existing controllers retain ownership of each operation.
class ShoppingHubPage extends ConsumerWidget {
  const ShoppingHubPage(
      {super.key, required this.stage, this.listId, this.view, this.requestId});
  final ShoppingStage stage;
  final String? listId, view, requestId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    String t(String ko, String en) => shopText(context, ko, en);
    Future<void> open(ShoppingStage next, [String? panel]) async {
      // Query-only navigation does not run GoRoute.onExit.
      if (!await ref.read(workspaceNavigationProvider).confirmLeave()) return;
      if (context.mounted) {
        context.go(shoppingPath(stage: next, listId: listId, view: panel));
      }
    }

    final owner = ref.watch(activeAccountIdProvider);
    final requests = view == 'requests' || requestId != null;
    final panel = requests
        ? 'requests'
        : view == 'lists'
            ? 'lists'
            : view == 'favorites' && stage == ShoppingStage.records
                ? 'favorites'
                : 'items';
    Widget body;
    if (owner == null) {
      body = Center(
          child: FilledButton(
              onPressed: () => context.push(loginFor(
                  GoRouterState.of(context).uri.toString(),
                  resume: true)),
              child: Text(t('로그인하고 장보기', 'Sign in to shop'))));
    } else if (requests &&
        (stage != ShoppingStage.records || requestId != null)) {
      body = SupplierRequestsPage(
          embedded: true,
          listId: listId,
          requestId: requestId,
          initialStage: switch (stage) {
            ShoppingStage.prepare => PurchaseStage.preparing,
            ShoppingStage.active => PurchaseStage.active,
            ShoppingStage.records => PurchaseStage.completed,
          });
    } else if (requests) {
      body = const RequestLedgerPage(embedded: true);
    } else if (panel == 'lists') {
      body = KitchenPage(
          key: ValueKey('$owner:${stage.name}:$listId'),
          embedded: true,
          listId: listId,
          initialTab: stage == ShoppingStage.records ? 'history' : 'shopping',
          onCompleted: () => open(ShoppingStage.records, 'lists'));
    } else if (stage == ShoppingStage.records) {
      body = ShoppingAssistantPage(
          embedded: true,
          initialTab: panel == 'favorites' ? 2 : 1,
          listId: listId);
    } else {
      body = ShoppingPreparationPage(
          embedded: true,
          listId: listId,
          purchasing: stage == ShoppingStage.active,
          onEditing: () => open(ShoppingStage.prepare),
          onConfirmed: () => open(ShoppingStage.active));
    }
    return Scaffold(
      appBar: AppBar(
          toolbarHeight: 48,
          title: Text(t('장보기', 'Shopping')),
          actions: [
            const PurchaseCleanupMenu(),
            IconButton(
                tooltip: t('구매처 선택·관리', 'Manage stores'),
                onPressed: () => context.push('/shopping-stores'),
                icon: const Icon(Icons.storefront_outlined)),
          ]),
      bottomNavigationBar: const ScoutNavigationBar(selectedIndex: 2),
      body: Column(children: [
        Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 6),
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              ShoppingStageTabs(
                  stage: stage,
                  onChanged: (next) =>
                      open(next, requests ? 'requests' : null)),
              const SizedBox(height: 4),
              Wrap(spacing: 8, runSpacing: 4, children: [
                for (final option in [
                  (
                    'items',
                    stage == ShoppingStage.records
                        ? t('상품별 기록', 'Items')
                        : t('재료·구매처', 'Ingredients')
                  ),
                  if (stage != ShoppingStage.prepare)
                    (
                      'lists',
                      stage == ShoppingStage.records
                          ? t('완료한 목록', 'Completed lists')
                          : t('목록 확인·완료', 'Review & complete')
                    ),
                  ('requests', t('거래처 요청', 'Supplier requests')),
                  if (stage == ShoppingStage.records)
                    ('favorites', t('저장 상품', 'Saved products')),
                ])
                  ChoiceChip(
                      key: ValueKey('shopping-view-${option.$1}'),
                      label: Text(option.$2),
                      selected: panel == option.$1,
                      onSelected: (_) => open(stage, option.$1)),
              ]),
            ])),
        Expanded(child: KeyedSubtree(key: ValueKey(owner), child: body)),
      ]),
    );
  }
}
