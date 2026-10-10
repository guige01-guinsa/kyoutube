import '../../../core/format/user_number.dart';
import '../../../core/auth/auth_return.dart';
import '../../workspace/application/workspace_profile_controller.dart';
import '../../workspace/application/workspace_navigation.dart';
import '../../workspace/domain/workspace_profile.dart';
import 'package:flutter/material.dart';
import 'package:k_youtube/core/localization/localized_text.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/router/app_router.dart';
import '../../shopping/presentation/shopping_workspace_links.dart';
import '../../shopping/presentation/shopping_assistant_dialogs.dart'
    show shopText, ShoppingAccountGuard;
import '../../../core/widgets/scout_navigation_bar.dart';
import '../../../core/widgets/centered_state_view.dart';
import '../../auth/application/auth_providers.dart';
import '../../recipes/application/recipe_providers.dart';
import '../../recipes/domain/recipe_source_reference.dart';
import '../application/kitchen_providers.dart';
import '../data/kitchen_api.dart';
import '../domain/kitchen_models.dart';
import '../domain/shopping_units.dart';

enum _ShoppingCompletionAction {
  cook,
  ingredients,
  history,
  home,
}

enum _KitchenWorkspaceMenuAction {
  home,
  cleanup,
  restoreRecent,
}

class _KitchenCleanupOptions {
  const _KitchenCleanupOptions({
    required this.clearIngredients,
    required this.clearActiveShopping,
    required this.clearCompletedHistory,
    required this.clearCookHistory,
  });

  final bool clearIngredients;
  final bool clearActiveShopping;
  final bool clearCompletedHistory;
  final bool clearCookHistory;

  bool get hasSelection =>
      clearIngredients ||
      clearActiveShopping ||
      clearCompletedHistory ||
      clearCookHistory;
}

class KitchenPage extends ConsumerStatefulWidget {
  const KitchenPage(
      {super.key,
      this.initialTab = 'shopping',
      this.embedded = false,
      this.toolsOnly = false,
      this.listId,
      this.onCompleted});

  final String initialTab;
  final bool embedded;
  final bool toolsOnly;
  final String? listId;
  final VoidCallback? onCompleted;

  @override
  ConsumerState<KitchenPage> createState() => _KitchenPageState();
}

class _KitchenPageState extends ConsumerState<KitchenPage>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;
  final Set<String> _itemProcessing = <String>{};
  bool _completionProcessing = false;
  bool _cleanupProcessing = false;

  @override
  void initState() {
    super.initState();
    int tabIndex = 0;
    if (widget.initialTab == 'history') {
      tabIndex = 1;
    }
    _tabController =
        TabController(length: 2, vsync: this, initialIndex: tabIndex);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _refreshAll() async {
    ref.invalidate(kitchenSummaryProvider);
    ref.invalidate(kitchenIngredientsProvider);
    ref.invalidate(kitchenShoppingListsProvider);
    ref.invalidate(kitchenCompletedShoppingListsProvider);
    ref.invalidate(kitchenCookSessionsProvider);
  }

  Future<void> _refreshActiveShopping({bool includeSummary = true}) async {
    ref.invalidate(kitchenShoppingListsProvider);
    if (includeSummary) {
      ref.invalidate(kitchenSummaryProvider);
    }
  }

  Future<void> _changeShoppingItemStatus(
      KitchenShoppingItem item, KitchenShoppingItemStatus desired) async {
    if (_completionProcessing || _itemProcessing.contains(item.id)) return;
    if (item.status == desired) return;
    setState(() => _itemProcessing.add(item.id));
    try {
      await ref.read(shoppingItemMutationControllerProvider).setStatus(
            itemId: item.id,
            status: desired,
            expectedRevision: item.revision,
          );
      await _refreshActiveShopping();
    } on KitchenApiException catch (error) {
      if (!mounted) {
        return;
      }
      if (error.kind == KitchenApiErrorKind.conflict ||
          error.kind == KitchenApiErrorKind.notFound) {
        await _refreshActiveShopping();
        if (!mounted) return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: LocalizedText(_shoppingErrorMessage(error))),
      );
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: LocalizedText('장보기 항목 변경에 실패했습니다. 다시 시도해 주세요.')),
        );
      }
    } finally {
      if (mounted) setState(() => _itemProcessing.remove(item.id));
    }
  }

  Future<void> _reviewAndMaybePurchase(KitchenShoppingItem item) async {
    final input = await _showReviewDialog(item, purchase: true);
    if (input == null || !mounted || _completionProcessing) return;
    setState(() => _itemProcessing.add(item.id));
    try {
      await ref.read(shoppingItemMutationControllerProvider).reviewThenStatus(
            itemId: item.id,
            name: input.name,
            quantity: input.quantity!,
            unit: input.unit!,
            expectedRevision: item.revision,
            status: KitchenShoppingItemStatus.purchased,
          );
      await _refreshActiveShopping();
    } on KitchenApiException catch (error) {
      await _refreshActiveShopping();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: LocalizedText(_shoppingErrorMessage(error))),
      );
    } catch (_) {
      await _refreshActiveShopping();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: LocalizedText('검토는 저장되었지만 구매 상태 변경에 실패했습니다.')),
      );
    } finally {
      if (mounted) setState(() => _itemProcessing.remove(item.id));
    }
  }

  Future<void> _editReview(KitchenShoppingItem item) async {
    final input = await _showReviewDialog(item);
    if (input == null || !mounted || _completionProcessing) return;
    setState(() => _itemProcessing.add(item.id));
    try {
      await ref.read(shoppingItemMutationControllerProvider).review(
            itemId: item.id,
            name: input.name,
            quantity: input.quantity,
            unit: input.unit,
            expectedRevision: item.revision,
          );
      await _refreshActiveShopping(includeSummary: false);
    } on KitchenApiException catch (error) {
      if (error.kind == KitchenApiErrorKind.conflict ||
          error.kind == KitchenApiErrorKind.notFound) {
        await _refreshActiveShopping(includeSummary: false);
      }
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: LocalizedText(_shoppingErrorMessage(error))),
      );
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: LocalizedText('재료 정보 수정에 실패했습니다.')),
        );
      }
    } finally {
      if (mounted) setState(() => _itemProcessing.remove(item.id));
    }
  }

  Future<void> _leaveKitchen() async {
    if (_cleanupProcessing) return;

    if (context.canPop()) {
      context.pop();
      return;
    }
    context.go('/');
  }

  Future<void> _openKitchenCleanupDialog() async {
    if (_cleanupProcessing) {
      return;
    }

    bool clearIngredients = false;
    bool clearActiveShopping = false;
    bool clearCompletedHistory = false;
    bool clearCookHistory = false;

    final options = await showDialog<_KitchenCleanupOptions>(
      context: context,
      builder: (BuildContext dialogContext) {
        return ShoppingAccountGuard(child: StatefulBuilder(
          builder: (BuildContext context, StateSetter setDialogState) {
            final hasSelection = clearIngredients ||
                clearActiveShopping ||
                clearCompletedHistory ||
                clearCookHistory;

            return AlertDialog(
              title: const LocalizedText('주방 정리'),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    const LocalizedText(
                      '정리할 항목을 선택하세요. 최근 정리 3건은 각각 30분 동안 되돌릴 수 있습니다.',
                    ),
                    const SizedBox(height: 12),
                    CheckboxListTile(
                      value: clearIngredients,
                      contentPadding: EdgeInsets.zero,
                      title: const LocalizedText('보유 재료 삭제'),
                      subtitle: const LocalizedText(
                        '보유 재료와 유통기한 정보가 삭제됩니다. 되돌리기 전에는 복구할 수 있습니다.',
                      ),
                      onChanged: (bool? value) {
                        setDialogState(() => clearIngredients = value ?? false);
                      },
                    ),
                    CheckboxListTile(
                      value: clearActiveShopping,
                      contentPadding: EdgeInsets.zero,
                      title: const LocalizedText('진행 중 장보기 정리'),
                      subtitle: const LocalizedText(
                        '진행 중 목록과 미체크 항목이 숨겨집니다. 구매 완료로 처리되지는 않습니다.',
                      ),
                      onChanged: (bool? value) {
                        setDialogState(
                          () => clearActiveShopping = value ?? false,
                        );
                      },
                    ),
                    CheckboxListTile(
                      value: clearCompletedHistory,
                      contentPadding: EdgeInsets.zero,
                      title: const LocalizedText('장보기 완료 내역 정리'),
                      subtitle: const LocalizedText(
                        '완료된 장보기 기록이 히스토리에서 숨겨집니다.',
                      ),
                      onChanged: (bool? value) {
                        setDialogState(
                          () => clearCompletedHistory = value ?? false,
                        );
                      },
                    ),
                    CheckboxListTile(
                      value: clearCookHistory,
                      contentPadding: EdgeInsets.zero,
                      title: const LocalizedText('조리 완료 기록 정리'),
                      subtitle: const LocalizedText('조리 완료 기록이 히스토리에서 숨겨집니다.'),
                      onChanged: (bool? value) {
                        setDialogState(
                          () => clearCookHistory = value ?? false,
                        );
                      },
                    ),
                  ],
                ),
              ),
              actions: <Widget>[
                TextButton(
                  onPressed: () => Navigator.pop(dialogContext),
                  child: const LocalizedText('취소'),
                ),
                FilledButton(
                  onPressed: hasSelection
                      ? () => Navigator.pop(
                            dialogContext,
                            _KitchenCleanupOptions(
                              clearIngredients: clearIngredients,
                              clearActiveShopping: clearActiveShopping,
                              clearCompletedHistory: clearCompletedHistory,
                              clearCookHistory: clearCookHistory,
                            ),
                          )
                      : null,
                  child: const LocalizedText('선택 항목 정리'),
                ),
              ],
            );
          },
        ));
      },
    );

    if (!mounted || options == null || !options.hasSelection) {
      return;
    }

    final impacts = <String>[
      if (options.clearIngredients) '보유 재료와 유통기한 정보',
      if (options.clearActiveShopping) '진행 중 장보기와 미체크 항목',
      if (options.clearCompletedHistory) '장보기 완료 내역',
      if (options.clearCookHistory) '조리 완료 기록',
    ];

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (BuildContext dialogContext) => ShoppingAccountGuard(
          child: AlertDialog(
        title: const LocalizedText('주방 데이터를 정리할까요?'),
        content: LocalizedText(
          '${impacts.join(', ')}가 정리됩니다. 최근 정리 3건은 각각 30분 동안 되돌릴 수 있습니다.',
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const LocalizedText('취소'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const LocalizedText('정리하기'),
          ),
        ],
      )),
    );

    if (confirmed != true || !mounted) {
      return;
    }

    await _runKitchenCleanup(options);
  }

  Future<void> _runKitchenCleanup(_KitchenCleanupOptions options) async {
    if (_cleanupProcessing) {
      return;
    }

    setState(() => _cleanupProcessing = true);

    try {
      final result = await ref.read(kitchenApiProvider).cleanupWorkspace(
            clearIngredients: options.clearIngredients,
            clearActiveShopping: options.clearActiveShopping,
            clearCompletedHistory: options.clearCompletedHistory,
            clearCookHistory: options.clearCookHistory,
            idempotencyKey: KitchenApi.createIdempotencyKey(),
          );

      await _refreshAll();

      if (!mounted) {
        return;
      }

      final changes = <String>[
        if (result.ingredientCount > 0) '재료 ${result.ingredientCount}개',
        if (result.activeListCount > 0) '진행 중 장보기 ${result.activeListCount}개',
        if (result.completedListCount > 0)
          '완료 내역 ${result.completedListCount}개',
        if (result.cookSessionCount > 0) '조리 완료 기록 ${result.cookSessionCount}개',
      ];

      ScaffoldMessenger.of(context).hideCurrentSnackBar();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          // 완료 안내는 짧게 보여 주고, 되돌리기는 상단 메뉴에서 30분 동안
          // 계속 제공한다. 화면을 가리는 긴 안내문은 피한다.
          duration: const Duration(seconds: 2),
          content: LocalizedText(
            changes.isEmpty
                ? '정리할 주방 데이터가 없습니다.'
                : '${changes.join(', ')}를 정리했습니다. 30분 안에 되돌릴 수 있습니다.',
          ),
        ),
      );
    } on KitchenApiException catch (error) {
      if (!mounted) {
        return;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: LocalizedText(_shoppingErrorMessage(error))),
      );
    } catch (_) {
      if (!mounted) {
        return;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: LocalizedText('주방 데이터를 정리하지 못했습니다. 다시 시도해 주세요.')),
      );
    } finally {
      if (mounted) {
        setState(() => _cleanupProcessing = false);
      }
    }
  }

  Future<void> _restoreKitchenCleanup(String snapshotId) async {
    if (_cleanupProcessing) {
      return;
    }

    setState(() => _cleanupProcessing = true);

    try {
      final result = await ref
          .read(kitchenApiProvider)
          .restoreWorkspaceCleanup(snapshotId);

      await _refreshAll();

      if (!mounted) {
        return;
      }

      final restored = <String>[
        if (result.restoredIngredientCount > 0)
          '재료 ${result.restoredIngredientCount}개',
        if (result.restoredActiveListCount > 0)
          '진행 중 장보기 ${result.restoredActiveListCount}개',
        if (result.restoredCompletedListCount > 0)
          '완료 내역 ${result.restoredCompletedListCount}개',
        if (result.restoredCookSessionCount > 0)
          '조리 완료 기록 ${result.restoredCookSessionCount}개',
      ];

      ScaffoldMessenger.of(context).hideCurrentSnackBar();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: LocalizedText(
            restored.isEmpty
                ? '되돌릴 주방 데이터가 없습니다.'
                : '${restored.join(', ')}를 복구했습니다.',
          ),
        ),
      );
    } on KitchenApiException catch (error) {
      if (!mounted) {
        return;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: LocalizedText(_shoppingErrorMessage(error))),
      );
    } catch (_) {
      if (!mounted) {
        return;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content:
              LocalizedText('정리를 되돌리지 못했습니다. Undo 시간이 지났거나 데이터가 변경되었을 수 있습니다.'),
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _cleanupProcessing = false);
      }
    }
  }

  Future<void> _showRecentCleanupRestores() async {
    if (_cleanupProcessing) {
      return;
    }

    setState(() => _cleanupProcessing = true);

    try {
      final snapshots =
          await ref.read(kitchenApiProvider).listWorkspaceCleanupSnapshots();

      if (!mounted) {
        return;
      }

      if (snapshots.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: LocalizedText('되돌릴 수 있는 최근 주방 정리가 없습니다.')),
        );
        return;
      }

      final selected =
          await showModalBottomSheet<KitchenWorkspaceCleanupSnapshot>(
        context: context,
        showDragHandle: true,
        builder: (BuildContext context) {
          return ShoppingAccountGuard(
              child: SafeArea(
            child: ListView.separated(
              shrinkWrap: true,
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 20),
              itemCount: snapshots.length + 1,
              separatorBuilder: (_, __) => const Divider(height: 1),
              itemBuilder: (BuildContext context, int index) {
                if (index == 0) {
                  return const ListTile(
                    title: LocalizedText('최근 정리 되돌리기'),
                    subtitle:
                        LocalizedText('최근 3건은 각각 정리 후 30분 동안 복구할 수 있습니다.'),
                  );
                }

                final snapshot = snapshots[index - 1];
                final remaining = snapshot.expiresAt
                    .difference(DateTime.now())
                    .inMinutes
                    .clamp(0, 30);
                final changes = <String>[
                  if (snapshot.ingredientCount > 0)
                    '재료 ${snapshot.ingredientCount}개',
                  if (snapshot.activeListCount > 0)
                    '진행 중 ${snapshot.activeListCount}개',
                  if (snapshot.completedListCount > 0)
                    '완료 내역 ${snapshot.completedListCount}개',
                  if (snapshot.cookSessionCount > 0)
                    '조리 완료 기록 ${snapshot.cookSessionCount}개',
                ];

                return ListTile(
                  leading: const Icon(Icons.restore_outlined),
                  title: LocalizedText(
                    changes.isEmpty ? '빈 정리 작업' : changes.join(', '),
                  ),
                  subtitle: LocalizedText('약 $remaining분 남음'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => Navigator.pop(context, snapshot),
                );
              },
            ),
          ));
        },
      );

      if (!mounted || selected == null) {
        return;
      }

      final confirmed = await showDialog<bool>(
        context: context,
        builder: (BuildContext dialogContext) => ShoppingAccountGuard(
            child: AlertDialog(
          title: const LocalizedText('최근 정리를 되돌릴까요?'),
          content:
              const LocalizedText('정리 후 새로 추가한 같은 이름의 재료가 있으면 복구할 수 없습니다.'),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const LocalizedText('취소'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: const LocalizedText('되돌리기'),
            ),
          ],
        )),
      );

      if (confirmed == true && mounted) {
        setState(() => _cleanupProcessing = false);
        await _restoreKitchenCleanup(selected.snapshotId);
      }
    } on KitchenApiException catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: LocalizedText(_shoppingErrorMessage(error))),
        );
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: LocalizedText('최근 주방 정리 목록을 불러오지 못했습니다.')),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _cleanupProcessing = false);
      }
    }
  }

  String? _routeForRecipeSource(String? sourceRecipeId) {
    final value = sourceRecipeId?.trim();
    if (value == null || value.isEmpty) {
      return null;
    }

    try {
      final source = RecipeSourceReference.parse(value);
      final encodedId = Uri.encodeComponent(source.id);

      return switch (source.type) {
        'public' => '/recipes/$encodedId',
        'creator' => '/creator/$encodedId',
        'user' => '/my-recipes/$encodedId',
        _ => null,
      };
    } catch (_) {
      return null;
    }
  }

  Future<void> _showShoppingCompletionActions(KitchenShoppingList list) async {
    final recipeRoute = _routeForRecipeSource(list.sourceRecipeId);
    final hasRecipeRoute = recipeRoute != null;

    final action = await showModalBottomSheet<_ShoppingCompletionAction>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (BuildContext context) {
        final colorScheme = Theme.of(context).colorScheme;

        return SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                Icon(
                  Icons.check_circle_outline,
                  size: 44,
                  color: colorScheme.primary,
                ),
                const SizedBox(height: 12),
                LocalizedText(
                  '장보기가 완료되었습니다',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                ),
                const SizedBox(height: 8),
                LocalizedText(
                  hasRecipeRoute
                      ? '구매한 재료가 보유 재료에 반영되었습니다. 이제 요리를 시작해 보세요.'
                      : '구매한 재료가 보유 재료에 반영되었습니다. 다음 작업을 선택해 주세요.',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
                const SizedBox(height: 20),
                if (hasRecipeRoute) ...<Widget>[
                  FilledButton.icon(
                    onPressed: () => Navigator.pop(
                      context,
                      _ShoppingCompletionAction.cook,
                    ),
                    icon: const Icon(Icons.restaurant_menu_outlined),
                    label: const LocalizedText('요리 시작하기'),
                  ),
                  const SizedBox(height: 8),
                  OutlinedButton.icon(
                    onPressed: () => Navigator.pop(
                      context,
                      _ShoppingCompletionAction.ingredients,
                    ),
                    icon: const Icon(Icons.kitchen_outlined),
                    label: const LocalizedText('새 재료 확인하기'),
                  ),
                ] else ...<Widget>[
                  FilledButton.icon(
                    onPressed: () => Navigator.pop(
                      context,
                      _ShoppingCompletionAction.ingredients,
                    ),
                    icon: const Icon(Icons.kitchen_outlined),
                    label: const LocalizedText('새 재료 확인하기'),
                  ),
                ],
                const SizedBox(height: 8),
                OutlinedButton.icon(
                  onPressed: () => Navigator.pop(
                    context,
                    _ShoppingCompletionAction.history,
                  ),
                  icon: const Icon(Icons.history),
                  label: const LocalizedText('장보기 완료 내역 보기'),
                ),
                if (!hasRecipeRoute) ...<Widget>[
                  const SizedBox(height: 8),
                  TextButton.icon(
                    onPressed: () => Navigator.pop(
                      context,
                      _ShoppingCompletionAction.home,
                    ),
                    icon: const Icon(Icons.home_outlined),
                    label: const LocalizedText('홈으로'),
                  ),
                ],
              ],
            ),
          ),
        );
      },
    );

    if (!mounted || action == null) {
      return;
    }

    switch (action) {
      case _ShoppingCompletionAction.cook:
        if (recipeRoute != null) {
          context.go(recipeRoute);
        }
        break;
      case _ShoppingCompletionAction.ingredients:
        _tabController.animateTo(0);
        break;
      case _ShoppingCompletionAction.history:
        _tabController.animateTo(1);
        break;
      case _ShoppingCompletionAction.home:
        context.go('/');
        break;
    }
  }

  Future<void> _completeShoppingList(KitchenShoppingList list) async {
    if (_completionProcessing || _itemProcessing.isNotEmpty) return;
    final confirmed = await _showCompletionDialog(list);
    if (confirmed != true || !mounted) return;
    setState(() => _completionProcessing = true);
    try {
      final completion =
          await ref.read(shoppingListCompletionControllerProvider.future);
      await completion.complete(list.id);
      await _refreshAll();
      if (!mounted) {
        return;
      }
      if (widget.embedded) {
        widget.onCompleted?.call();
      } else {
        await _showShoppingCompletionActions(list);
      }
    } catch (error) {
      if (!mounted) {
        return;
      }
      if (error is KitchenApiException &&
          (error.kind == KitchenApiErrorKind.conflict ||
              error.kind == KitchenApiErrorKind.notFound)) {
        await _refreshAll();
      }
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: LocalizedText('장보기 완료 처리에 실패했습니다.')),
      );
    } finally {
      if (mounted) setState(() => _completionProcessing = false);
    }
  }

  Future<_ReviewSubmission?> _showReviewDialog(KitchenShoppingItem item,
      {bool purchase = false}) async {
    final nameController = TextEditingController(text: item.name);
    final quantityController = TextEditingController(
        text: isPurchaseUnit(item.unit) ? item.quantity?.toString() ?? '' : '');
    final quantityFocusNode = FocusNode();
    // 조리 계량 단위가 남은 이전 항목은 구매량을 다시 입력합니다.
    // 기존 조리 수량을 다른 구매 단위의 수량으로 바꾸지 않습니다.
    String unit =
        isPurchaseUnit(item.unit) ? item.unit! : purchaseUnits.first.code;
    String categoryForUnit(String? code) {
      return purchaseUnits
          .firstWhere(
            (ShoppingUnit option) => option.code == code,
            orElse: () => purchaseUnits.first,
          )
          .category;
    }

    String selectedUnitCategory = categoryForUnit(unit);
    String? validationError;
    void changePurchaseUnit(String next) {
      if (next == unit) return;
      final quantity = parseUserNumber(quantityController.text.trim());
      final converted = quantity == null
          ? null
          : convertPurchaseQuantity(quantity, unit, next);
      quantityController.text = converted?.toString() ?? '';
      validationError = quantity != null && converted == null
          ? '환산 기준이 없는 단위입니다. 구매 수량을 직접 입력해 주세요.'
          : null;
      unit = next;
    }

    final needsQuantity = item.quantity == null || !isPurchaseUnit(item.unit);
    final result = await showDialog<_ReviewSubmission>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) {
          final textTheme = Theme.of(context).textTheme;
          final compactFieldDecoration = InputDecoration(
            isDense: true,
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
            labelStyle: textTheme.labelMedium?.copyWith(fontSize: 11),
          );

          return AlertDialog(
            insetPadding:
                const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
            titleTextStyle: textTheme.titleLarge?.copyWith(
              fontSize: 18,
              fontWeight: FontWeight.w700,
            ),
            contentTextStyle: textTheme.bodySmall?.copyWith(fontSize: 12),
            contentPadding: const EdgeInsets.fromLTRB(20, 8, 20, 8),
            actionsPadding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
            title: LocalizedText(purchase ? '재료 검토 후 구매함' : '재료 정보 수정'),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  LocalizedText('조리 원문: ${item.ingredientText}',
                      semanticsLabel:
                          context.tr('읽기 전용 조리 원문 ${item.ingredientText}')),
                  const SizedBox(height: 8),
                  TextField(
                    controller: nameController,
                    textInputAction: TextInputAction.next,
                    style: textTheme.bodyMedium?.copyWith(fontSize: 14),
                    decoration: compactFieldDecoration.copyWith(
                      labelText: context.tr('재료 이름 *'),
                    ),
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: <Widget>[
                      Expanded(
                        child: TextField(
                          controller: quantityController,
                          focusNode: quantityFocusNode,
                          autofocus: needsQuantity,
                          keyboardType: const TextInputType.numberWithOptions(
                              decimal: true),
                          textInputAction: TextInputAction.next,
                          style: textTheme.bodyMedium?.copyWith(fontSize: 14),
                          decoration: compactFieldDecoration.copyWith(
                            labelText: context.tr('구매 수량 *'),
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: DropdownButtonFormField<String>(
                          key: ValueKey<String>(
                            '$selectedUnitCategory:$unit',
                          ),
                          initialValue: unit,
                          style: textTheme.bodyMedium?.copyWith(fontSize: 14),
                          decoration: compactFieldDecoration.copyWith(
                            labelText: context.tr('구매 단위 *'),
                          ),
                          items: purchaseUnits
                              .where((ShoppingUnit option) =>
                                  option.category == selectedUnitCategory)
                              .map(
                                (ShoppingUnit option) =>
                                    DropdownMenuItem<String>(
                                  value: option.code,
                                  child: LocalizedText(option.label),
                                ),
                              )
                              .toList(growable: false),
                          onChanged: (value) {
                            if (value != null) {
                              setDialogState(() => changePurchaseUnit(value));
                            }
                          },
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  LocalizedText(
                    '구매 단위끼리만 환산합니다. 포장량이 다르면 환산 기준 또는 최종 구매량을 입력해 주세요.',
                    style: textTheme.bodySmall?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                      fontSize: 11,
                    ),
                  ),
                  const SizedBox(height: 8),
                  SizedBox(
                    height: 40,
                    child: Row(
                      children: shoppingUnitCategories.map((String category) {
                        final selected = selectedUnitCategory == category;
                        return Expanded(
                          child: Padding(
                            padding: EdgeInsets.only(
                              right: category == shoppingUnitCategories.last
                                  ? 0
                                  : 6,
                            ),
                            child: Material(
                              color: selected
                                  ? Theme.of(context)
                                      .colorScheme
                                      .primaryContainer
                                  : Theme.of(context)
                                      .colorScheme
                                      .surfaceContainerLowest,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(10),
                                side: BorderSide(
                                  color: selected
                                      ? Theme.of(context).colorScheme.primary
                                      : Theme.of(context)
                                          .colorScheme
                                          .outlineVariant,
                                ),
                              ),
                              clipBehavior: Clip.antiAlias,
                              child: InkWell(
                                onTap: () {
                                  setDialogState(() {
                                    selectedUnitCategory = category;
                                    if (!purchaseUnits.any(
                                      (ShoppingUnit option) =>
                                          option.category == category &&
                                          option.code == unit,
                                    )) {
                                      changePurchaseUnit(purchaseUnits
                                          .firstWhere(
                                            (ShoppingUnit option) =>
                                                option.category == category,
                                          )
                                          .code);
                                    }
                                  });
                                },
                                child: Center(
                                  child: LocalizedText(
                                    category,
                                    maxLines: 1,
                                    style: textTheme.labelMedium?.copyWith(
                                      fontSize: 12,
                                      fontWeight: selected
                                          ? FontWeight.w700
                                          : FontWeight.w600,
                                      color: selected
                                          ? Theme.of(context)
                                              .colorScheme
                                              .onPrimaryContainer
                                          : Theme.of(context)
                                              .colorScheme
                                              .onSurface,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        );
                      }).toList(growable: false),
                    ),
                  ),
                  if (validationError != null)
                    Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: LocalizedText(validationError!,
                            style: TextStyle(
                                color: Theme.of(context).colorScheme.error))),
                ],
              ),
            ),
            actions: <Widget>[
              TextButton(
                onPressed: () => Navigator.pop(dialogContext),
                style: TextButton.styleFrom(
                  minimumSize: const Size(0, 36),
                  textStyle: textTheme.labelLarge?.copyWith(fontSize: 14),
                ),
                child: const LocalizedText('취소'),
              ),
              FilledButton(
                onPressed: () {
                  final name = nameController.text.trim();
                  final rawQuantity = quantityController.text.trim();
                  final quantity =
                      rawQuantity.isEmpty ? null : parseUserNumber(rawQuantity);
                  if (name.isEmpty) {
                    setDialogState(() => validationError = '재료 이름을 입력하세요.');
                    return;
                  }
                  if (quantity == null || quantity <= 0 || !quantity.isFinite) {
                    setDialogState(
                        () => validationError = '구매 수량과 단위를 모두 입력해 주세요.');
                    quantityFocusNode.requestFocus();
                    return;
                  }
                  if (!isPurchaseUnit(unit)) {
                    setDialogState(
                      () => validationError = '구매 단위를 선택해 주세요.',
                    );
                    return;
                  }
                  if ((quantity * 1000000 - (quantity * 1000000).round())
                          .abs() >
                      0.0001) {
                    setDialogState(
                        () => validationError = '구매 수량은 소수점 여섯째 자리까지 입력해 주세요.');
                    return;
                  }
                  Navigator.pop(
                      dialogContext,
                      _ReviewSubmission(
                          name: name, quantity: quantity, unit: unit));
                },
                style: FilledButton.styleFrom(
                  minimumSize: const Size(0, 36),
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  textStyle: textTheme.labelLarge?.copyWith(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                child: const LocalizedText('저장'),
              ),
            ],
          );
        },
      ),
    );
    // Dialog 종료 애니메이션 동안 TextField가 controller를 참조할 수 있으므로
    // route가 완전히 정리된 뒤 controller를 dispose합니다.
    await Future<void>.delayed(const Duration(milliseconds: 250));

    nameController.dispose();
    quantityController.dispose();
    quantityFocusNode.dispose();

    return result;
  }

  Future<bool?> _showCompletionDialog(KitchenShoppingList list) {
    final purchased = list.items
        .where((item) => item.status == KitchenShoppingItemStatus.purchased)
        .length;
    final skipped = list.items
        .where((item) => item.status == KitchenShoppingItemStatus.skipped)
        .length;
    final unavailable = list.items
        .where((item) => item.status == KitchenShoppingItemStatus.unavailable)
        .length;
    return showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const LocalizedText('장보기 완료'),
        content: LocalizedText(
            '구매함 $purchased개 · 건너뜀 $skipped개 · 구매하지 못함 $unavailable개\n구매함 항목만 재고에 반영됩니다. 완료 후 목록이 사라질 수 있습니다.'),
        actions: <Widget>[
          TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const LocalizedText('취소')),
          FilledButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: const LocalizedText('완료')),
        ],
      ),
    );
  }

  String _shoppingErrorMessage(KitchenApiException error) {
    return switch (error.kind) {
      KitchenApiErrorKind.unauthorized => '로그인이 필요합니다.',
      KitchenApiErrorKind.notFound => '장보기 목록이 갱신되었습니다. 다시 확인해 주세요.',
      KitchenApiErrorKind.conflict => '다른 변경이 반영되었습니다. 목록을 다시 불러왔습니다.',
      KitchenApiErrorKind.validation => '재료 검토 정보 또는 상태를 확인해 주세요.',
      _ => '장보기 요청에 실패했습니다. 다시 시도해 주세요.',
    };
  }

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(authUserProvider).valueOrNull;
    if (user == null) {
      return Scaffold(
        bottomNavigationBar: const ScoutNavigationBar(selectedIndex: 2),
        appBar: AppBar(title: const LocalizedText('나의 장보기')),
        body: CenteredStateView(
          icon: Icons.lock_outline,
          title: '로그인이 필요합니다',
          message: '주방 재료와 장보기는 개인 데이터라 로그인 후 사용할 수 있습니다.',
          actionLabel: context.tr('로그인'),
          onAction: () => context.push(loginFor(GoRouterState.of(context).uri.toString(), resume: true)),
        ),
      );
    }

    if (widget.toolsOnly) {
      return WorkspaceEditGuard(
          dirty: false,
          busy: _cleanupProcessing,
          confirmLeave: () async => false,
          child: PopScope(
              canPop: !_cleanupProcessing,
              child: Scaffold(
                  appBar: AppBar(title: const LocalizedText('주방 정리')),
                  body: ListView(padding: const EdgeInsets.all(20), children: [
                    const LocalizedText(
                        '정리할 항목을 선택하세요. 최근 정리 3건은 각각 30분 동안 되돌릴 수 있습니다.'),
                    const SizedBox(height: 16),
                    FilledButton.icon(
                        key: const Key('open-kitchen-cleanup'),
                        onPressed: _cleanupProcessing
                            ? null
                            : _openKitchenCleanupDialog,
                        icon: const Icon(Icons.cleaning_services_outlined),
                        label: const LocalizedText('정리할 항목 선택')),
                    const SizedBox(height: 12),
                    OutlinedButton.icon(
                        key: const Key('restore-kitchen-cleanup'),
                        onPressed: _cleanupProcessing
                            ? null
                            : _showRecentCleanupRestores,
                        icon: const Icon(Icons.restore),
                        label: const LocalizedText('최근 정리 되돌리기')),
                  ]))));
    }
    if (widget.embedded) {
      return WorkspaceEditGuard(
          dirty: false,
          busy: _completionProcessing || _itemProcessing.isNotEmpty,
          confirmLeave: () async => false,
          child: widget.initialTab == 'history'
              ? const _HistoryTab()
              : _ShoppingTab(
                  onChangeStatus: _changeShoppingItemStatus,
                  onReviewAndPurchase: _reviewAndMaybePurchase,
                  onEditReview: _editReview,
                  onCompleteList: _completeShoppingList,
                  processingItemIds: _itemProcessing,
                  completionProcessing: _completionProcessing,
                  listId: widget.listId,
                  embedded: true));
    }
    final summaryAsync = ref.watch(kitchenSummaryProvider);

    return Scaffold(
      bottomNavigationBar: ScoutNavigationBar(
          selectedIndex: 2,
          enabled: !_cleanupProcessing && !_completionProcessing),
      appBar: AppBar(
        title: const LocalizedText('나의 장보기'),
        leading: IconButton(
          tooltip: context.tr(context.canPop() ? '이전 화면' : '홈으로 이동'),
          icon: Icon(context.canPop() ? Icons.arrow_back : Icons.home_outlined),
          onPressed: _cleanupProcessing ? null : _leaveKitchen,
        ),
        actions: <Widget>[
          IconButton(
            tooltip: context.tr('재료 찾기'),
            icon: const Icon(Icons.auto_awesome_outlined),
            onPressed: () => context.push('/ingredient-search'),
          ),
          PopupMenuButton<_KitchenWorkspaceMenuAction>(
            tooltip: context.tr('주방 메뉴'),
            enabled: !_cleanupProcessing,
            onSelected: (_KitchenWorkspaceMenuAction action) async {
              switch (action) {
                case _KitchenWorkspaceMenuAction.home:
                  await _leaveKitchen();
                  break;
                case _KitchenWorkspaceMenuAction.cleanup:
                  await _openKitchenCleanupDialog();
                  break;
                case _KitchenWorkspaceMenuAction.restoreRecent:
                  await _showRecentCleanupRestores();
                  break;
              }
            },
            itemBuilder: (BuildContext context) =>
                const <PopupMenuEntry<_KitchenWorkspaceMenuAction>>[
              PopupMenuItem<_KitchenWorkspaceMenuAction>(
                value: _KitchenWorkspaceMenuAction.home,
                child: ListTile(
                  leading: Icon(Icons.home_outlined),
                  title: LocalizedText('홈으로 이동'),
                ),
              ),
              PopupMenuItem<_KitchenWorkspaceMenuAction>(
                value: _KitchenWorkspaceMenuAction.cleanup,
                child: ListTile(
                  leading: Icon(Icons.cleaning_services_outlined),
                  title: LocalizedText('주방 정리'),
                ),
              ),
              PopupMenuItem<_KitchenWorkspaceMenuAction>(
                value: _KitchenWorkspaceMenuAction.restoreRecent,
                child: ListTile(
                  leading: Icon(Icons.restore_outlined),
                  title: LocalizedText('최근 정리 되돌리기'),
                ),
              ),
            ],
          ),
        ],
        bottom: TabBar(
          controller: _tabController,
          tabs: const <Tab>[
            Tab(text: '장보기'),
            Tab(text: '히스토리'),
          ],
        ),
      ),
      body: Center(
          child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: ScoutStyle.contentWidth),
        child: NestedScrollView(
          headerSliverBuilder: (_, __) => <Widget>[
            SliverToBoxAdapter(
                child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: <Widget>[
                    LocalizedText('필요한 만큼, 빠짐없이.',
                        style: Theme.of(context).textTheme.headlineSmall),
                    const SizedBox(height: 6),
                    LocalizedText('레시피에서 고른 재료를 하나씩 준비해요.',
                        style: Theme.of(context).textTheme.bodySmall),
                    const SizedBox(height: 16),
                    _KitchenSummaryHeader(summaryAsync: summaryAsync),
                    const SizedBox(height: 12),
                    ShoppingWorkspaceLinks(
                        enabled: !_cleanupProcessing && !_completionProcessing),
                  ]),
            )),
          ],
          body: TabBarView(
            controller: _tabController,
            children: <Widget>[
              _ShoppingTab(
                onChangeStatus: _changeShoppingItemStatus,
                onReviewAndPurchase: _reviewAndMaybePurchase,
                onEditReview: _editReview,
                onCompleteList: _completeShoppingList,
                processingItemIds: _itemProcessing,
                completionProcessing: _completionProcessing,
              ),
              const _HistoryTab(),
            ],
          ),
        ),
      )),
    );
  }
}

class _ReviewSubmission {
  const _ReviewSubmission(
      {required this.name, required this.quantity, required this.unit});

  final String name;
  final double? quantity;
  final String? unit;
}

class _KitchenSummaryHeader extends StatelessWidget {
  const _KitchenSummaryHeader({required this.summaryAsync});

  final AsyncValue<Map<String, int>> summaryAsync;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: summaryAsync.when(
          data: (Map<String, int> data) {
            final ingredientCount = data['ingredient_count'] ?? 0;
            final expiringSoonCount = data['expiring_soon_count'] ?? 0;
            final activeShoppingListCount =
                data['active_shopping_list_count'] ?? 0;
            final openShoppingItemCount = data['open_shopping_item_count'] ?? 0;

            return LayoutBuilder(
              builder: (BuildContext context, BoxConstraints constraints) {
                final itemWidth = (constraints.maxWidth - 12) / 2;
                return Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  children: <Widget>[
                    SizedBox(
                      width: itemWidth,
                      child:
                          _MetricChip(label: '보유 재료', value: ingredientCount),
                    ),
                    SizedBox(
                      width: itemWidth,
                      child: _MetricChip(
                          label: '유통기한 임박', value: expiringSoonCount),
                    ),
                    SizedBox(
                      width: itemWidth,
                      child: _MetricChip(
                          label: '진행 중 장보기', value: activeShoppingListCount),
                    ),
                    SizedBox(
                      width: itemWidth,
                      child: _MetricChip(
                          label: '미체크 항목', value: openShoppingItemCount),
                    ),
                  ],
                );
              },
            );
          },
          loading: () => const SizedBox(
            height: 28,
            child: Center(child: CircularProgressIndicator()),
          ),
          error: (_, __) => const LocalizedText('주방 요약을 불러오지 못했습니다.'),
        ),
      ),
    );
  }
}

class _MetricChip extends StatelessWidget {
  const _MetricChip({required this.label, required this.value});

  final String label;
  final int value;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: colorScheme.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: colorScheme.outlineVariant),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: <Widget>[
          Flexible(
            child: LocalizedText(
              label,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.labelMedium?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                    fontWeight: FontWeight.w600,
                  ),
            ),
          ),
          const SizedBox(width: 8),
          LocalizedText(
            '$value',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  color: colorScheme.primary,
                  fontWeight: FontWeight.w800,
                ),
          ),
        ],
      ),
    );
  }
}

class _ShoppingTab extends ConsumerWidget {
  const _ShoppingTab({
    required this.onChangeStatus,
    required this.onReviewAndPurchase,
    required this.onEditReview,
    required this.onCompleteList,
    required this.processingItemIds,
    required this.completionProcessing,
    this.listId,
    this.embedded = false,
  });

  final Future<void> Function(
          KitchenShoppingItem item, KitchenShoppingItemStatus status)
      onChangeStatus;
  final Future<void> Function(KitchenShoppingItem item) onReviewAndPurchase;
  final Future<void> Function(KitchenShoppingItem item) onEditReview;
  final Future<void> Function(KitchenShoppingList list) onCompleteList;
  final Set<String> processingItemIds;
  final bool completionProcessing;
  final String? listId;
  final bool embedded;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final shoppingAsync = ref.watch(kitchenShoppingListsProvider);

    return shoppingAsync.when(
      data: (List<KitchenShoppingList> lists) {
        lists = lists.where((l) => listId == null || l.id == listId).toList();
        if (lists.isEmpty) {
          return CenteredStateView(
              icon: Icons.shopping_basket_outlined,
              title: '장바구니가 비어 있어요',
              message: '레시피에서 장보기 준비를 누르면 필요한 재료를 여기에서 확인할 수 있어요.',
              actionLabel: context.tr('레시피 둘러보기'),
              onAction: () => context.go('/'));
        }

        return RefreshIndicator(
          onRefresh: () async {
            ref.invalidate(kitchenShoppingListsProvider);
            ref.invalidate(kitchenSummaryProvider);
          },
          child: ListView.builder(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.only(bottom: 24),
            itemCount: lists.length,
            itemBuilder: (BuildContext context, int index) {
              final list = lists[index];
              final pendingItems = list.items
                  .where((item) =>
                      item.status == KitchenShoppingItemStatus.pending)
                  .toList(growable: false);

              final purchasedItems = list.items
                  .where((item) =>
                      item.status == KitchenShoppingItemStatus.purchased)
                  .toList(growable: false);

              final otherItems = list.items
                  .where(
                    (item) =>
                        item.status == KitchenShoppingItemStatus.skipped ||
                        item.status == KitchenShoppingItemStatus.unavailable,
                  )
                  .toList(growable: false);

              return Card(
                elevation: 0,
                margin: const EdgeInsets.fromLTRB(16, 10, 16, 0),
                color: Theme.of(context).colorScheme.surface,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(20),
                  side: BorderSide(
                    color: Theme.of(context).colorScheme.outlineVariant,
                  ),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Row(
                        children: <Widget>[
                          Expanded(
                            child: LocalizedText(
                              list.title,
                              style: Theme.of(context).textTheme.titleMedium,
                            ),
                          ),
                          _ShoppingCountBadge(
                            count: pendingItems.length,
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      LocalizedText(
                          '구매 ${purchasedItems.length}개 · 남은 재료 ${pendingItems.length}개',
                          style: Theme.of(context).textTheme.bodySmall),
                      const SizedBox(height: 10),
                      LinearProgressIndicator(
                        value: list.items.isEmpty
                            ? 0
                            : (list.items.length - pendingItems.length) /
                                list.items.length,
                        minHeight: 5,
                        borderRadius: BorderRadius.circular(8),
                        semanticsLabel: context.tr('장보기 처리 진행률'),
                      ),
                      const SizedBox(height: 14),
                      if (!embedded &&
                          pendingItems.isNotEmpty &&
                          ref
                                  .watch(workspaceProfileProvider)
                                  .valueOrNull
                                  ?.active ==
                              WorkspaceMode.professional)
                        FilledButton.tonalIcon(
                            onPressed: () => context.push(Uri(
                                path: '/supplier-plan',
                                queryParameters: {'list': list.id}).toString()),
                            icon: const Icon(Icons.receipt_long_outlined,
                                size: 18),
                            label: Text(shopText(context, '이 목록으로 구매요청',
                                'Request these ingredients'))),
                      if (pendingItems.isNotEmpty)
                        TextButton.icon(
                            onPressed: () => context.push(Uri(
                                path: AppRoutes.shoppingAssistant,
                                queryParameters: {'list': list.id}).toString()),
                            icon:
                                const Icon(Icons.storefront_outlined, size: 18),
                            label: Text(shopText(context, '이 목록 구매처 찾기',
                                'Find stores for this list'))),
                      if ((list.sourceRecipeId ?? '').trim().isNotEmpty)
                        _ShoppingRecipeLink(
                          sourceRecipeReference: list.sourceRecipeId!,
                          recipeTitle: list.title,
                        ),
                      if ((list.sourceRecipeId ?? '').trim().isNotEmpty)
                        const SizedBox(height: 8),
                      if (pendingItems.isNotEmpty) ...<Widget>[
                        _ShoppingSectionHeader(
                          title: '장보기 필요 ${pendingItems.length}개',
                          icon: Icons.shopping_cart_outlined,
                        ),
                        const SizedBox(height: 8),
                        ...pendingItems.map(
                          (item) => _shoppingItemTile(context, item),
                        ),
                      ],
                      if (purchasedItems.isNotEmpty) ...<Widget>[
                        const SizedBox(height: 12),
                        _ShoppingSectionHeader(
                          title: '구매 완료 ${purchasedItems.length}개',
                          icon: Icons.check_circle_outline,
                          completed: true,
                        ),
                        const SizedBox(height: 8),
                        ...purchasedItems.map(
                          (item) => _shoppingItemTile(context, item),
                        ),
                      ],
                      if (otherItems.isNotEmpty) ...<Widget>[
                        const SizedBox(height: 12),
                        _ShoppingSectionHeader(
                          title: '보류/구매 불가 ${otherItems.length}개',
                          icon: Icons.info_outline,
                        ),
                        const SizedBox(height: 8),
                        ...otherItems.map(
                          (item) => _shoppingItemTile(context, item),
                        ),
                      ],
                      const SizedBox(height: 4),
                      Align(
                        alignment: Alignment.centerRight,
                        child: FilledButton.tonal(
                          onPressed: completionProcessing ||
                                  processingItemIds.isNotEmpty ||
                                  list.status != 'active' ||
                                  list.items.any((item) =>
                                      item.status ==
                                      KitchenShoppingItemStatus.pending)
                              ? null
                              : () => onCompleteList(list),
                          child: const LocalizedText('장보기 완료'),
                        ),
                      ),
                      if (list.items.any((item) =>
                          item.status == KitchenShoppingItemStatus.pending))
                        Padding(
                          padding: const EdgeInsets.only(top: 8),
                          child: LocalizedText(
                            '아직 결정하지 않은 재료가 ${pendingItems.length}개 있습니다.',
                            style:
                                Theme.of(context).textTheme.bodySmall?.copyWith(
                                      color: Theme.of(context)
                                          .colorScheme
                                          .onSurfaceVariant,
                                    ),
                          ),
                        ),
                    ],
                  ),
                ),
              );
            },
          ),
        );
      },
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (_, __) => CenteredStateView(
        icon: Icons.cloud_off_outlined,
        title: '장보기 목록을 불러오지 못했어요',
        message: '연결 상태를 확인하고 다시 시도해 주세요.',
        actionLabel: context.tr('다시 시도'),
        onAction: () => ref.invalidate(kitchenShoppingListsProvider),
      ),
    );
  }

  Widget _shoppingItemTile(BuildContext context, KitchenShoppingItem item) {
    final processing =
        completionProcessing || processingItemIds.contains(item.id);
    final needsReview = item.needsReview ||
        item.reviewStatus == KitchenShoppingItemReviewStatus.required;
    final needsIngredientInfo = item.needsIngredientInfo;
    final purchased = item.status == KitchenShoppingItemStatus.purchased;
    final colors = Theme.of(context).colorScheme;
    final quantity = item.quantity == null
        ? null
        : item.quantity! % 1 == 0
            ? item.quantity!.toInt().toString()
            : item.quantity.toString();
    void changeStatus(KitchenShoppingItemStatus desired) {
      if (desired == item.status) return;
      if (desired == KitchenShoppingItemStatus.purchased && needsReview) {
        onReviewAndPurchase(item);
      } else {
        onChangeStatus(item, desired);
      }
    }

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      color: purchased ? ScoutStyle.mint : colors.surface,
      shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(
              color: needsIngredientInfo || needsReview
                  ? colors.tertiary
                  : colors.outlineVariant)),
      child: Padding(
          padding: const EdgeInsets.fromLTRB(4, 10, 8, 10),
          child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      if (processing)
                        const Padding(
                            padding: EdgeInsets.all(14),
                            child: SizedBox(
                                width: 20,
                                height: 20,
                                child:
                                    CircularProgressIndicator(strokeWidth: 2)))
                      else
                        Checkbox(
                          value: purchased,
                          semanticLabel: '${item.name} 구매 완료',
                          onChanged: (checked) => changeStatus(checked == true
                              ? KitchenShoppingItemStatus.purchased
                              : KitchenShoppingItemStatus.pending),
                        ),
                      Expanded(
                          child: Padding(
                              padding: const EdgeInsets.only(top: 10),
                              child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: <Widget>[
                                    LocalizedText(item.name,
                                        style: Theme.of(context)
                                            .textTheme
                                            .titleMedium),
                                    if (quantity != null)
                                      LocalizedText(
                                          '구매 $quantity ${shoppingUnitLabel(item.unit)}',
                                          style: Theme.of(context)
                                              .textTheme
                                              .bodySmall),
                                    const SizedBox(height: 4),
                                    LocalizedText('원문 · ${item.ingredientText}',
                                        semanticsLabel: context.tr(
                                            '읽기 전용 원문 ${item.ingredientText}'),
                                        style: Theme.of(context)
                                            .textTheme
                                            .bodySmall),
                                    if (item.status !=
                                        KitchenShoppingItemStatus.pending)
                                      LocalizedText(
                                          _statusPresentation(item.status)
                                              .label,
                                          style: Theme.of(context)
                                              .textTheme
                                              .labelMedium
                                              ?.copyWith(
                                                  color: colors.primary)),
                                  ]))),
                      PopupMenuButton<KitchenShoppingItemStatus>(
                        tooltip: context.tr('${item.name} 구매 상태 변경'),
                        enabled: !processing,
                        icon: const Icon(Icons.more_horiz),
                        onSelected: changeStatus,
                        itemBuilder: (_) => KitchenShoppingItemStatus.values
                            .map((value) => PopupMenuItem(
                                  value: value,
                                  child: LocalizedText(
                                      _statusPresentation(value).label),
                                ))
                            .toList(),
                      ),
                    ]),
                Padding(
                    padding: const EdgeInsets.only(left: 44, top: 4),
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: needsIngredientInfo || needsReview
                          ? TextButton.icon(
                              onPressed:
                                  processing ? null : () => onEditReview(item),
                              icon: const Icon(Icons.edit_note, size: 18),
                              label: LocalizedText(
                                  needsIngredientInfo ? '수량·단위 입력' : '재료 확인하기'))
                          : IconButton(
                              onPressed:
                                  processing ? null : () => onEditReview(item),
                              icon: const Icon(Icons.edit_outlined, size: 18),
                              tooltip: context.tr('${item.name} 재료 정보 수정')),
                    )),
              ])),
    );
  }

  _StatusPresentation _statusPresentation(KitchenShoppingItemStatus status) {
    return switch (status) {
      KitchenShoppingItemStatus.pending =>
        const _StatusPresentation('구매 결정 필요', Icons.help_outline),
      KitchenShoppingItemStatus.purchased =>
        const _StatusPresentation('구매함', Icons.check_circle_outline),
      KitchenShoppingItemStatus.skipped =>
        const _StatusPresentation('이번에는 건너뜀', Icons.skip_next_outlined),
      KitchenShoppingItemStatus.unavailable =>
        const _StatusPresentation('구매하지 못함', Icons.block_outlined),
    };
  }
}

class _ShoppingSectionHeader extends StatelessWidget {
  const _ShoppingSectionHeader({
    required this.title,
    required this.icon,
    this.completed = false,
  });

  final String title;
  final IconData icon;
  final bool completed;

  @override
  Widget build(BuildContext context) {
    final color = completed
        ? Theme.of(context).colorScheme.primary
        : Theme.of(context).colorScheme.onSurface;

    return Row(
      children: <Widget>[
        Icon(icon, size: 20, color: color),
        const SizedBox(width: 8),
        Expanded(
            child: LocalizedText(
          title,
          style: Theme.of(context).textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w700,
                color: color,
              ),
        )),
      ],
    );
  }
}

class _ShoppingCountBadge extends StatelessWidget {
  const _ShoppingCountBadge({required this.count});

  final int count;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: colorScheme.primaryContainer,
        borderRadius: BorderRadius.circular(999),
      ),
      child: LocalizedText(
        '결정 필요 $count개',
        style: Theme.of(context).textTheme.labelMedium?.copyWith(
              color: colorScheme.onPrimaryContainer,
              fontWeight: FontWeight.w700,
            ),
      ),
    );
  }
}

class _StatusPresentation {
  const _StatusPresentation(this.label, this.icon);

  final String label;
  final IconData icon;
}

class _HistoryTab extends ConsumerWidget {
  const _HistoryTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final completedShoppingAsync =
        ref.watch(kitchenCompletedShoppingListsProvider);
    final cookSessionsAsync = ref.watch(kitchenCookSessionsProvider);

    return RefreshIndicator(
      onRefresh: () async {
        ref.invalidate(kitchenCompletedShoppingListsProvider);
        ref.invalidate(kitchenCookSessionsProvider);
        ref.invalidate(kitchenSummaryProvider);
      },
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
        children: <Widget>[
          LocalizedText(
            '장보기 완료 내역',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
          ),
          const SizedBox(height: 8),
          completedShoppingAsync.when(
            data: (lists) {
              if (lists.isEmpty) {
                return const Card(
                  child: Padding(
                    padding: EdgeInsets.all(16),
                    child: LocalizedText('완료된 장보기 목록이 없습니다.'),
                  ),
                );
              }

              return Column(
                children: lists.map((list) {
                  final purchasedCount = list.items
                      .where(
                        (item) =>
                            item.status == KitchenShoppingItemStatus.purchased,
                      )
                      .length;

                  final skippedCount = list.items
                      .where(
                        (item) =>
                            item.status == KitchenShoppingItemStatus.skipped,
                      )
                      .length;

                  final unavailableCount = list.items
                      .where(
                        (item) =>
                            item.status ==
                            KitchenShoppingItemStatus.unavailable,
                      )
                      .length;

                  return Card(
                    child: ListTile(
                      leading: const Icon(Icons.shopping_cart_checkout),
                      title: LocalizedText(list.title),
                      subtitle: LocalizedText(
                        '구매함 $purchasedCount개'
                        ' · 건너뜀 $skippedCount개'
                        ' · 구매하지 못함 $unavailableCount개',
                      ),
                    ),
                  );
                }).toList(growable: false),
              );
            },
            loading: () => const Card(
              child: Padding(
                padding: EdgeInsets.all(16),
                child: Center(child: CircularProgressIndicator()),
              ),
            ),
            error: (_, __) => const Card(
              child: Padding(
                padding: EdgeInsets.all(16),
                child: LocalizedText('장보기 완료 내역을 불러오지 못했습니다.'),
              ),
            ),
          ),
          const SizedBox(height: 28),
          LocalizedText(
            '조리 완료 기록',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
          ),
          const SizedBox(height: 8),
          cookSessionsAsync.when(
            data: (sessions) {
              if (sessions.isEmpty) {
                return const Card(
                  child: Padding(
                    padding: EdgeInsets.all(16),
                    child: LocalizedText('아직 조리 완료 기록이 없습니다.'),
                  ),
                );
              }

              return Column(
                children: sessions.map((session) {
                  final feedback = <String>[
                    if (session.liked != null)
                      session.liked == true ? '좋아요' : '아쉬워요',
                    if (session.rating != null) '평점 ${session.rating}/5',
                  ];

                  return Card(
                    child: ListTile(
                      leading: const Icon(Icons.restaurant_menu_outlined),
                      title: LocalizedText(session.recipeTitle),
                      subtitle: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          LocalizedText(
                            session.createdAt
                                .replaceFirst('T', ' ')
                                .split('.')
                                .first,
                          ),
                          if (feedback.isNotEmpty)
                            LocalizedText(feedback.join(' · ')),
                          if (session.note != null && session.note!.isNotEmpty)
                            LocalizedText(session.note!),
                        ],
                      ),
                    ),
                  );
                }).toList(growable: false),
              );
            },
            loading: () => const Card(
              child: Padding(
                padding: EdgeInsets.all(16),
                child: Center(child: CircularProgressIndicator()),
              ),
            ),
            error: (_, __) => const Card(
              child: Padding(
                padding: EdgeInsets.all(16),
                child: LocalizedText('조리 완료 기록을 불러오지 못했습니다.'),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ShoppingRecipeLink extends StatelessWidget {
  const _ShoppingRecipeLink({
    required this.sourceRecipeReference,
    required this.recipeTitle,
  });

  final String sourceRecipeReference;
  final String recipeTitle;

  String? _routeForSource() {
    try {
      final source = RecipeSourceReference.parse(sourceRecipeReference);
      final encodedId = Uri.encodeComponent(source.id);

      return switch (source.type) {
        'public' => '/recipes/$encodedId',
        'creator' => '/creator/$encodedId',
        'user' => '/my-recipes/$encodedId',
        _ => null,
      };
    } catch (_) {
      return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final route = _routeForSource();
    final normalizedTitle = recipeTitle.trim();

    final displayTitle = normalizedTitle.isEmpty || normalizedTitle == '장보기 목록'
        ? '연결된 레시피'
        : normalizedTitle;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.primaryContainer,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: <Widget>[
          const Icon(Icons.menu_book_outlined),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                LocalizedText(
                  '요리할 레시피',
                  style: Theme.of(context).textTheme.labelMedium,
                ),
                const SizedBox(height: 2),
                LocalizedText(
                  displayTitle,
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                ),
              ],
            ),
          ),
          if (route != null)
            TextButton(
              onPressed: () => context.push(route),
              child: const LocalizedText('레시피 보기'),
            ),
        ],
      ),
    );
  }
}
