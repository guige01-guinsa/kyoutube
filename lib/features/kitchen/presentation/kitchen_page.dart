import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/widgets/centered_state_view.dart';
import '../application/kitchen_providers.dart';
import '../domain/kitchen_models.dart';

class KitchenPage extends ConsumerStatefulWidget {
  const KitchenPage({super.key});

  @override
  ConsumerState<KitchenPage> createState() => _KitchenPageState();
}

class _KitchenPageState extends ConsumerState<KitchenPage> {
  bool _isUpdating = false;
  bool _onlyWithOpenItems = true;
  bool _includeCompleted = false;
  int _completedWithinDays = 7;

  KitchenShoppingListsQuery get _query => KitchenShoppingListsQuery(
        includeCompleted: _includeCompleted,
        onlyWithOpenItems: _onlyWithOpenItems,
        completedWithinDays: _completedWithinDays,
      );

  Future<void> _refresh() async {
    ref.invalidate(kitchenShoppingListsProvider(_query));
  }

  Future<void> _toggleItem(KitchenShoppingItem item, bool isChecked) async {
    if (_isUpdating) {
      return;
    }

    setState(() {
      _isUpdating = true;
    });

    try {
      await ref.read(kitchenApiProvider).patchShoppingItem(
            id: item.id,
            isChecked: isChecked,
          );
      await _refresh();
    } catch (error) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('장보기 항목을 업데이트하지 못했습니다.\n$error')),
      );
    } finally {
      if (mounted) {
        setState(() {
          _isUpdating = false;
        });
      }
    }
  }

  Future<void> _completeList(KitchenShoppingList list) async {
    if (_isUpdating) {
      return;
    }

    setState(() {
      _isUpdating = true;
    });

    try {
      await ref.read(kitchenApiProvider).completeShoppingList(list.id);
      await _refresh();
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('“${list.title}” 장보기를 완료했습니다.')),
      );
    } catch (error) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('장보기 리스트를 완료하지 못했습니다.\n$error')),
      );
    } finally {
      if (mounted) {
        setState(() {
          _isUpdating = false;
        });
      }
    }
  }

  Future<void> _resetList(KitchenShoppingList list) async {
    if (_isUpdating) {
      return;
    }

    final checkedItems = list.items
        .where((KitchenShoppingItem item) => item.isChecked)
        .toList(growable: false);
    if (checkedItems.isEmpty) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('초기화할 체크 항목이 없습니다.')),
      );
      return;
    }

    setState(() {
      _isUpdating = true;
    });

    try {
      final api = ref.read(kitchenApiProvider);

      for (final item in checkedItems) {
        await api.patchShoppingItem(id: item.id, isChecked: false);
      }

      await _refresh();
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('“${list.title}” 체크를 초기화했습니다. 다시 장보기를 시작하세요.')),
      );
    } catch (error) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('다시 장보기를 시작하지 못했습니다.\n$error')),
      );
    } finally {
      if (mounted) {
        setState(() {
          _isUpdating = false;
        });
      }
    }
  }

  Widget _buildShoppingListCard(KitchenShoppingList list) {
    final sortedItems = List<KitchenShoppingItem>.from(list.items)
      ..sort((KitchenShoppingItem a, KitchenShoppingItem b) =>
          a.id.compareTo(b.id));
    final openCount = list.openItemCount;
    final completedCount = sortedItems.length - openCount;
    final canReset = completedCount > 0;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              children: <Widget>[
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        list.title,
                        style: Theme.of(context).textTheme.titleLarge?.copyWith(
                              fontWeight: FontWeight.w700,
                            ),
                      ),
                      const SizedBox(height: 4),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: <Widget>[
                          Chip(
                            label: Text('남은 $openCount개'),
                            visualDensity: VisualDensity.compact,
                          ),
                          Chip(
                            label: Text('완료 $completedCount개'),
                            visualDensity: VisualDensity.compact,
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: <Widget>[
                    FilledButton.tonalIcon(
                      onPressed: _isUpdating || list.status == 'completed'
                          ? null
                          : () => _completeList(list),
                      icon: const Icon(Icons.done_all_outlined),
                      label: const Text('완료'),
                    ),
                    const SizedBox(height: 6),
                    OutlinedButton.icon(
                      onPressed: _isUpdating || !canReset
                          ? null
                          : () => _resetList(list),
                      icon: const Icon(Icons.restart_alt),
                      label: const Text('다시 장보기'),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      canReset ? '체크된 항목만 초기화' : '체크된 항목이 없습니다',
                      style: Theme.of(context).textTheme.labelSmall,
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 12),
            if (sortedItems.isEmpty)
              const Text('장보기 항목이 없습니다.')
            else
              ...sortedItems.map(
                (KitchenShoppingItem item) => Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: CheckboxListTile(
                    value: item.isChecked,
                    onChanged: _isUpdating
                        ? null
                        : (bool? value) {
                            if (value == null) {
                              return;
                            }
                            _toggleItem(item, value);
                          },
                    title: Text(
                      item.name,
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            decoration: item.isChecked
                                ? TextDecoration.lineThrough
                                : null,
                          ),
                    ),
                    subtitle: Text(
                      [
                        if (item.quantity != null) '${item.quantity}',
                        if (item.unit != null && item.unit!.trim().isNotEmpty)
                          item.unit!.trim(),
                      ].join(' ').trim(),
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                    controlAffinity: ListTileControlAffinity.leading,
                    contentPadding: const EdgeInsets.symmetric(vertical: 2),
                    visualDensity: VisualDensity.compact,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final shoppingListsAsync = ref.watch(kitchenShoppingListsProvider(_query));

    return Scaffold(
      appBar: AppBar(
        title: const Text('장보기'),
        actions: <Widget>[
          IconButton(
            onPressed: _isUpdating ? null : _refresh,
            icon: const Icon(Icons.refresh),
            tooltip: '새로고침',
          ),
        ],
      ),
      body: shoppingListsAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (Object err, StackTrace _) => CenteredStateView(
          icon: Icons.shopping_cart_outlined,
          title: '장보기 정보를 불러오지 못했습니다',
          message: err.toString(),
          actionLabel: '다시 시도',
          onAction: _refresh,
          secondaryActionLabel: '홈으로 이동',
          onSecondaryAction: () => context.go('/'),
        ),
        data: (List<KitchenShoppingList> lists) {
          if (lists.isEmpty) {
            return CenteredStateView(
              icon: Icons.shopping_cart_checkout_outlined,
              title: '조건에 맞는 장보기 리스트가 없습니다',
              message: _onlyWithOpenItems
                  ? '남은 재료가 있는 리스트만 표시 중입니다. 필터를 바꾸면 완료/빈 리스트도 볼 수 있습니다.'
                  : '레시피 상세에서 장보기 목록을 만들면 여기서 체크하면서 살 수 있습니다.',
              actionLabel: '홈으로 이동',
              onAction: () => context.go('/'),
            );
          }

          return RefreshIndicator(
            onRefresh: _refresh,
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: <Widget>[
                Card(
                  color: Theme.of(context).colorScheme.surfaceContainerHighest,
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Text(
                          '장보기 중심 화면',
                          style: Theme.of(context).textTheme.titleLarge?.copyWith(
                                fontWeight: FontWeight.w700,
                              ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          '재고/냉장고 관리는 제외하고, 레시피 기반 장보기와 체크에만 집중합니다.',
                          style: Theme.of(context).textTheme.bodyMedium,
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: <Widget>[
                            FilterChip(
                              label: const Text('남은 재료만'),
                              selected: _onlyWithOpenItems,
                              onSelected: (bool selected) {
                                setState(() {
                                  _onlyWithOpenItems = selected;
                                });
                              },
                            ),
                            FilterChip(
                              label: const Text('완료 포함'),
                              selected: _includeCompleted,
                              onSelected: (bool selected) {
                                setState(() {
                                  _includeCompleted = selected;
                                });
                              },
                            ),
                          ],
                        ),
                        if (_includeCompleted) ...<Widget>[
                          const SizedBox(height: 8),
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: <int>[3, 7, 14, 30]
                                .map(
                                  (int days) => ChoiceChip(
                                    label: Text('완료 $days일'),
                                    selected: _completedWithinDays == days,
                                    onSelected: (bool selected) {
                                      if (!selected) {
                                        return;
                                      }
                                      setState(() {
                                        _completedWithinDays = days;
                                      });
                                    },
                                  ),
                                )
                                .toList(growable: false),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                ...lists.map(_buildShoppingListCard),
              ],
            ),
          );
        },
      ),
    );
  }
}