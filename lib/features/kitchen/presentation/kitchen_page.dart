import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/widgets/centered_state_view.dart';
import '../../auth/application/auth_providers.dart';
import '../../recipes/application/recipe_providers.dart';
import '../../recipes/domain/recipe_source_reference.dart';
import '../application/kitchen_providers.dart';
import '../data/kitchen_api.dart';
import '../domain/kitchen_models.dart';

enum _ShoppingCompletionAction {
  cook,
  ingredients,
  history,
  home,
}

class KitchenPage extends ConsumerStatefulWidget {
  const KitchenPage({super.key, this.initialTab = 'ingredients'});

  final String initialTab;

  @override
  ConsumerState<KitchenPage> createState() => _KitchenPageState();
}

class _KitchenPageState extends ConsumerState<KitchenPage>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;
  final TextEditingController _addController = TextEditingController();
  final Set<String> _itemProcessing = <String>{};
  bool _completionProcessing = false;

  @override
  void initState() {
    super.initState();
    int tabIndex = 0;
    if (widget.initialTab == 'shopping') {
      tabIndex = 1;
    } else if (widget.initialTab == 'history') {
      tabIndex = 2;
    }
    _tabController =
        TabController(length: 3, vsync: this, initialIndex: tabIndex);
  }

  @override
  void dispose() {
    _tabController.dispose();
    _addController.dispose();
    super.dispose();
  }

  Future<void> _refreshAll() async {
    ref.invalidate(kitchenSummaryProvider);
    ref.invalidate(kitchenIngredientsProvider);
    ref.invalidate(kitchenShoppingListsProvider);
    ref.invalidate(kitchenCookSessionsProvider);
  }

  Future<void> _addIngredient() async {
    final name = _addController.text.trim();
    if (name.isEmpty) {
      return;
    }

    try {
      await ref.read(kitchenApiProvider).createIngredient(name: name);
      _addController.clear();
      await _refreshAll();
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('재료를 추가했습니다: $name')),
      );
    } catch (_) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('재료 추가에 실패했습니다. 잠시 후 다시 시도해 주세요.')),
      );
    }
  }

  Future<void> _deleteIngredient(KitchenIngredient ingredient) async {
    try {
      await ref.read(kitchenApiProvider).deleteIngredient(ingredient.id);
      await _refreshAll();
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('재료를 삭제했습니다: ${ingredient.name}')),
      );
    } catch (_) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('재료 삭제에 실패했습니다.')),
      );
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
      await _refreshAll();
    } on KitchenApiException catch (error) {
      if (!mounted) {
        return;
      }
      if (error.kind == KitchenApiErrorKind.conflict ||
          error.kind == KitchenApiErrorKind.notFound) {
        await _refreshAll();
        if (!mounted) return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(_shoppingErrorMessage(error))),
      );
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('장보기 항목 변경에 실패했습니다. 다시 시도해 주세요.')),
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
      await _refreshAll();
    } on KitchenApiException catch (error) {
      await _refreshAll();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(_shoppingErrorMessage(error))),
      );
    } catch (_) {
      await _refreshAll();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('검토는 저장되었지만 구매 상태 변경에 실패했습니다.')),
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
      await _refreshAll();
    } on KitchenApiException catch (error) {
      if (error.kind == KitchenApiErrorKind.conflict ||
          error.kind == KitchenApiErrorKind.notFound) {
        await _refreshAll();
      }
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(_shoppingErrorMessage(error))),
      );
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('재료 정보 수정에 실패했습니다.')),
        );
      }
    } finally {
      if (mounted) setState(() => _itemProcessing.remove(item.id));
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
                Text(
                  '장보기가 완료되었습니다',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                ),
                const SizedBox(height: 8),
                Text(
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
                    label: const Text('요리 시작하기'),
                  ),
                  const SizedBox(height: 8),
                  OutlinedButton.icon(
                    onPressed: () => Navigator.pop(
                      context,
                      _ShoppingCompletionAction.ingredients,
                    ),
                    icon: const Icon(Icons.kitchen_outlined),
                    label: const Text('새 재료 확인하기'),
                  ),
                ] else ...<Widget>[
                  FilledButton.icon(
                    onPressed: () => Navigator.pop(
                      context,
                      _ShoppingCompletionAction.ingredients,
                    ),
                    icon: const Icon(Icons.kitchen_outlined),
                    label: const Text('새 재료 확인하기'),
                  ),
                ],
                const SizedBox(height: 8),
                OutlinedButton.icon(
                  onPressed: () => Navigator.pop(
                    context,
                    _ShoppingCompletionAction.history,
                  ),
                  icon: const Icon(Icons.history),
                  label: const Text('장보기 완료 내역 보기'),
                ),
                if (!hasRecipeRoute) ...<Widget>[
                  const SizedBox(height: 8),
                  TextButton.icon(
                    onPressed: () => Navigator.pop(
                      context,
                      _ShoppingCompletionAction.home,
                    ),
                    icon: const Icon(Icons.home_outlined),
                    label: const Text('홈으로'),
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
        _tabController.animateTo(2);
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
      await _showShoppingCompletionActions(list);
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
        const SnackBar(content: Text('장보기 완료 처리에 실패했습니다.')),
      );
    } finally {
      if (mounted) setState(() => _completionProcessing = false);
    }
  }

  Future<_ReviewSubmission?> _showReviewDialog(KitchenShoppingItem item,
      {bool purchase = false}) async {
    final nameController = TextEditingController(
        text: item.reviewStatus == KitchenShoppingItemReviewStatus.confirmed
            ? item.name
            : '');
    final quantityController =
        TextEditingController(text: item.quantity?.toString() ?? '');
    String? unit = item.unit;
    String? validationError;
    final result = await showDialog<_ReviewSubmission>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text(purchase ? '재료 검토 후 구매함' : '재료 정보 수정'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text('원문: ${item.ingredientText}',
                    semanticsLabel: '읽기 전용 원문 재료 ${item.ingredientText}'),
                const SizedBox(height: 12),
                TextField(
                    controller: nameController,
                    autofocus: true,
                    textInputAction: TextInputAction.next,
                    decoration: const InputDecoration(
                        labelText: '재료 이름', helperText: '필수')),
                TextField(
                    controller: quantityController,
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                    textInputAction: TextInputAction.next,
                    decoration: const InputDecoration(labelText: '수량')),
                DropdownButtonFormField<String>(
                  initialValue: unit,
                  decoration: const InputDecoration(labelText: '단위'),
                  items: const <DropdownMenuItem<String>>[
                    DropdownMenuItem(value: 'g', child: Text('g')),
                    DropdownMenuItem(value: 'kg', child: Text('kg')),
                    DropdownMenuItem(value: 'ml', child: Text('ml')),
                    DropdownMenuItem(value: 'l', child: Text('L')),
                    DropdownMenuItem(value: 'ea', child: Text('개')),
                  ],
                  onChanged: (value) => setDialogState(() => unit = value),
                ),
                if (validationError != null)
                  Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Text(validationError!,
                          style: TextStyle(
                              color: Theme.of(context).colorScheme.error))),
              ],
            ),
          ),
          actions: <Widget>[
            TextButton(
                onPressed: () => Navigator.pop(dialogContext),
                child: const Text('취소')),
            FilledButton(
              onPressed: () {
                final name = nameController.text.trim();
                final rawQuantity = quantityController.text.trim();
                final quantity =
                    rawQuantity.isEmpty ? null : double.tryParse(rawQuantity);
                if (name.isEmpty) {
                  setDialogState(() => validationError = '재료 이름을 입력하세요.');
                  return;
                }
                if ((quantity == null) != (unit == null) ||
                    (quantity != null &&
                        (quantity <= 0 || !quantity.isFinite))) {
                  setDialogState(
                      () => validationError = '수량과 단위를 함께 올바르게 입력하세요.');
                  return;
                }
                if (purchase && (quantity == null || unit == null)) {
                  setDialogState(
                      () => validationError = '구매함으로 변경하려면 수량과 단위가 필요합니다.');
                  return;
                }
                Navigator.pop(
                    dialogContext,
                    _ReviewSubmission(
                        name: name, quantity: quantity, unit: unit));
              },
              child: const Text('저장'),
            ),
          ],
        ),
      ),
    );
    nameController.dispose();
    quantityController.dispose();
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
        title: const Text('장보기 완료'),
        content: Text(
            '구매함 $purchased개 · 건너뜀 $skipped개 · 구매하지 못함 $unavailable개\n구매함 항목만 재고에 반영됩니다. 완료 후 목록이 사라질 수 있습니다.'),
        actions: <Widget>[
          TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('취소')),
          FilledButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: const Text('완료')),
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
        appBar: AppBar(title: const Text('주방')),
        body: CenteredStateView(
          icon: Icons.lock_outline,
          title: '로그인이 필요합니다',
          message: '주방 재료와 장보기는 개인 데이터라 로그인 후 사용할 수 있습니다.',
          actionLabel: '로그인',
          onAction: () => context.push('/login'),
        ),
      );
    }

    final summaryAsync = ref.watch(kitchenSummaryProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('주방'),
        bottom: TabBar(
          controller: _tabController,
          tabs: const <Tab>[
            Tab(text: '재료 관리'),
            Tab(text: '장보기'),
            Tab(text: '히스토리'),
          ],
        ),
      ),
      body: Column(
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: _KitchenSummaryHeader(summaryAsync: summaryAsync),
          ),
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: <Widget>[
                _IngredientsTab(
                  addController: _addController,
                  onAddIngredient: _addIngredient,
                  onDeleteIngredient: _deleteIngredient,
                ),
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
        ],
      ),
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

            return Wrap(
              spacing: 12,
              runSpacing: 8,
              children: <Widget>[
                _MetricChip(label: '보유 재료', value: ingredientCount),
                _MetricChip(label: '유통기한 임박', value: expiringSoonCount),
                _MetricChip(label: '진행 중 장보기', value: activeShoppingListCount),
                _MetricChip(label: '미체크 항목', value: openShoppingItemCount),
              ],
            );
          },
          loading: () => const SizedBox(
            height: 28,
            child: Center(child: CircularProgressIndicator()),
          ),
          error: (_, __) => const Text('주방 요약을 불러오지 못했습니다.'),
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
    return Chip(
      label: Text('$label $value'),
    );
  }
}

class _IngredientsTab extends ConsumerWidget {
  const _IngredientsTab({
    required this.addController,
    required this.onAddIngredient,
    required this.onDeleteIngredient,
  });

  final TextEditingController addController;
  final Future<void> Function() onAddIngredient;
  final Future<void> Function(KitchenIngredient ingredient) onDeleteIngredient;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ingredientsAsync = ref.watch(kitchenIngredientsProvider);

    return Column(
      children: <Widget>[
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
          child: Row(
            children: <Widget>[
              Expanded(
                child: TextField(
                  controller: addController,
                  decoration: const InputDecoration(
                    border: OutlineInputBorder(),
                    labelText: '재료 빠른 추가',
                    hintText: '예: 감자, 양파, 간장',
                  ),
                  onSubmitted: (_) => onAddIngredient(),
                ),
              ),
              const SizedBox(width: 8),
              FilledButton(
                onPressed: onAddIngredient,
                child: const Text('추가'),
              ),
            ],
          ),
        ),
        Expanded(
          child: ingredientsAsync.when(
            data: (List<KitchenIngredient> ingredients) {
              if (ingredients.isEmpty) {
                return const Center(
                  child: Text('재료가 없습니다. 먼저 재료를 추가해 주세요.'),
                );
              }

              return RefreshIndicator(
                onRefresh: () async {
                  ref.invalidate(kitchenIngredientsProvider);
                  ref.invalidate(kitchenSummaryProvider);
                },
                child: ListView.separated(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: const EdgeInsets.only(bottom: 24),
                  itemCount: ingredients.length,
                  separatorBuilder: (_, __) => const Divider(height: 1),
                  itemBuilder: (BuildContext context, int index) {
                    final ingredient = ingredients[index];
                    final subtitleChunks = <String>[];

                    if (ingredient.quantity != null) {
                      final suffix =
                          ingredient.unit == null ? '' : ' ${ingredient.unit}';
                      subtitleChunks.add('수량 ${ingredient.quantity}$suffix');
                    }
                    if (ingredient.expiresOn != null &&
                        ingredient.expiresOn!.isNotEmpty) {
                      subtitleChunks.add('유통기한 ${ingredient.expiresOn}');
                    }
                    if (ingredient.storageLocation != null &&
                        ingredient.storageLocation!.isNotEmpty) {
                      subtitleChunks.add('보관 ${ingredient.storageLocation}');
                    }

                    return ListTile(
                      title: Text(ingredient.name),
                      subtitle: subtitleChunks.isEmpty
                          ? null
                          : Text(subtitleChunks.join(' · ')),
                      trailing: IconButton(
                        tooltip: '삭제',
                        icon: const Icon(Icons.delete_outline),
                        onPressed: () => onDeleteIngredient(ingredient),
                      ),
                    );
                  },
                ),
              );
            },
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (Object err, StackTrace _) => Center(
              child: Text(
                '재료 목록을 불러오지 못했습니다.\n$err',
                textAlign: TextAlign.center,
              ),
            ),
          ),
        ),
      ],
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
  });

  final Future<void> Function(
          KitchenShoppingItem item, KitchenShoppingItemStatus status)
      onChangeStatus;
  final Future<void> Function(KitchenShoppingItem item) onReviewAndPurchase;
  final Future<void> Function(KitchenShoppingItem item) onEditReview;
  final Future<void> Function(KitchenShoppingList list) onCompleteList;
  final Set<String> processingItemIds;
  final bool completionProcessing;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final shoppingAsync = ref.watch(kitchenShoppingListsProvider);

    return shoppingAsync.when(
      data: (List<KitchenShoppingList> lists) {
        if (lists.isEmpty) {
          return const Center(
            child: Text('진행 중인 장보기 목록이 없습니다.'),
          );
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
              return Card(
                margin: const EdgeInsets.fromLTRB(16, 10, 16, 0),
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Row(
                        children: <Widget>[
                          Expanded(
                            child: Text(
                              list.title,
                              style: Theme.of(context).textTheme.titleMedium,
                            ),
                          ),
                          Text(
                              '결정 필요 ${list.items.where((item) => item.status == KitchenShoppingItemStatus.pending).length}개'),
                        ],
                      ),
                      const SizedBox(height: 8),
                      ...list.items
                          .map((item) => _shoppingItemTile(context, item)),
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
                          child: const Text('장보기 완료'),
                        ),
                      ),
                      if (list.items.any((item) =>
                          item.status == KitchenShoppingItemStatus.pending))
                        Padding(
                          padding: const EdgeInsets.only(top: 8),
                          child: Text(
                              '구매 여부를 결정하지 않은 재료가 ${list.items.where((item) => item.status == KitchenShoppingItemStatus.pending).length}개 있습니다.'),
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
      error: (Object err, StackTrace _) => Center(
        child: Text(
          '장보기 목록을 불러오지 못했습니다.\n$err',
          textAlign: TextAlign.center,
        ),
      ),
    );
  }

  Widget _shoppingItemTile(BuildContext context, KitchenShoppingItem item) {
    final processing =
        completionProcessing || processingItemIds.contains(item.id);
    final status = _statusPresentation(item.status);
    final needsReview = item.needsReview ||
        item.reviewStatus == KitchenShoppingItemReviewStatus.required;
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsets.all(8),
        child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Row(children: <Widget>[
                Icon(status.icon, semanticLabel: status.label),
                const SizedBox(width: 8),
                Expanded(
                    child: Text(item.name,
                        semanticsLabel: '${item.name}, 상태 ${status.label}')),
                if (processing)
                  const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2)),
              ]),
              const SizedBox(height: 4),
              Wrap(spacing: 6, children: <Widget>[
                Chip(
                    avatar: Icon(status.icon, size: 16),
                    label: Text(status.label)),
                if (needsReview)
                  const Chip(
                      avatar: Icon(Icons.rate_review_outlined, size: 16),
                      label: Text('검토 필요')),
              ]),
              Text('원문: ${item.ingredientText}',
                  semanticsLabel: '읽기 전용 원문 ${item.ingredientText}'),
              if (item.quantity != null)
                Text('수량 ${item.quantity} ${item.unit ?? ''}'.trim()),
              if (item.reviewStatus ==
                  KitchenShoppingItemReviewStatus.confirmed)
                TextButton.icon(
                    onPressed: processing ? null : () => onEditReview(item),
                    icon: const Icon(Icons.edit_outlined),
                    label: const Text('재료 정보 수정')),
              DropdownButtonFormField<KitchenShoppingItemStatus>(
                initialValue: item.status,
                decoration: const InputDecoration(labelText: '구매 상태'),
                items: KitchenShoppingItemStatus.values.map((value) {
                  final presentation = _statusPresentation(value);
                  return DropdownMenuItem(
                      value: value, child: Text(presentation.label));
                }).toList(),
                onChanged: processing
                    ? null
                    : (desired) {
                        if (desired == null) return;
                        if (desired == KitchenShoppingItemStatus.purchased &&
                            needsReview) {
                          onReviewAndPurchase(item);
                        } else {
                          onChangeStatus(item, desired);
                        }
                      },
              ),
            ]),
      ),
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

class _StatusPresentation {
  const _StatusPresentation(this.label, this.icon);

  final String label;
  final IconData icon;
}

class _HistoryTab extends ConsumerWidget {
  const _HistoryTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final historyAsync = ref.watch(kitchenCookSessionsProvider);

    return historyAsync.when(
      data: (List<KitchenCookSession> sessions) {
        if (sessions.isEmpty) {
          return const Center(
            child: Text('아직 조리 완료 기록이 없습니다.'),
          );
        }

        return RefreshIndicator(
          onRefresh: () async {
            ref.invalidate(kitchenCookSessionsProvider);
            ref.invalidate(kitchenSummaryProvider);
          },
          child: ListView.separated(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.only(bottom: 24),
            itemCount: sessions.length,
            separatorBuilder: (_, __) => const Divider(height: 1),
            itemBuilder: (BuildContext context, int index) {
              final session = sessions[index];
              final feedback = <String>[];

              if (session.liked != null) {
                feedback.add(session.liked == true ? '좋아요' : '아쉬워요');
              }
              if (session.rating != null) {
                feedback.add('평점 ${session.rating}/5');
              }

              return ListTile(
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                title: Text(session.recipeTitle),
                subtitle: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(session.createdAt
                        .replaceFirst('T', ' ')
                        .split('.')
                        .first),
                    if (feedback.isNotEmpty) Text(feedback.join(' · ')),
                    if (session.note != null && session.note!.isNotEmpty)
                      Text(session.note!),
                  ],
                ),
              );
            },
          ),
        );
      },
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (Object err, StackTrace _) => Center(
        child: Text(
          '히스토리를 불러오지 못했습니다.\n$err',
          textAlign: TextAlign.center,
        ),
      ),
    );
  }
}
