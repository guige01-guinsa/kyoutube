import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/widgets/centered_state_view.dart';
import '../../auth/application/auth_providers.dart';
import '../../recipes/application/recipe_providers.dart';
import '../application/kitchen_providers.dart';
import '../domain/kitchen_models.dart';

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

  @override
  void initState() {
    super.initState();
    int tabIndex = 0;
    if (widget.initialTab == 'shopping') {
      tabIndex = 1;
    } else if (widget.initialTab == 'history') {
      tabIndex = 2;
    }
    _tabController = TabController(length: 3, vsync: this, initialIndex: tabIndex);
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

  Future<void> _toggleShoppingItem(KitchenShoppingItem item, bool value) async {
    try {
      await ref.read(kitchenApiProvider).patchShoppingItem(
            id: item.id,
            isChecked: value,
          );
      ref.invalidate(kitchenShoppingListsProvider);
      ref.invalidate(kitchenSummaryProvider);
    } catch (_) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('장보기 항목 변경에 실패했습니다.')),
      );
    }
  }

  Future<void> _completeShoppingList(KitchenShoppingList list) async {
    try {
      await ref.read(kitchenApiProvider).completeShoppingList(list.id);
      await _refreshAll();
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('장보기를 완료 처리했습니다.')),
      );
    } catch (_) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('장보기 완료 처리에 실패했습니다.')),
      );
    }
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
                  onToggleItem: _toggleShoppingItem,
                  onCompleteList: _completeShoppingList,
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
            final activeShoppingListCount = data['active_shopping_list_count'] ?? 0;
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
                      final suffix = ingredient.unit == null ? '' : ' ${ingredient.unit}';
                      subtitleChunks.add('수량 ${ingredient.quantity}$suffix');
                    }
                    if (ingredient.expiresOn != null && ingredient.expiresOn!.isNotEmpty) {
                      subtitleChunks.add('유통기한 ${ingredient.expiresOn}');
                    }
                    if (ingredient.storageLocation != null && ingredient.storageLocation!.isNotEmpty) {
                      subtitleChunks.add('보관 ${ingredient.storageLocation}');
                    }

                    return ListTile(
                      title: Text(ingredient.name),
                      subtitle: subtitleChunks.isEmpty ? null : Text(subtitleChunks.join(' · ')),
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
    required this.onToggleItem,
    required this.onCompleteList,
  });

  final Future<void> Function(KitchenShoppingItem item, bool value) onToggleItem;
  final Future<void> Function(KitchenShoppingList list) onCompleteList;

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
                          Text('미체크 ${list.openItemCount}개'),
                        ],
                      ),
                      const SizedBox(height: 8),
                      ...list.items.map(
                        (KitchenShoppingItem item) => CheckboxListTile(
                          value: item.isChecked,
                          dense: true,
                          contentPadding: EdgeInsets.zero,
                          title: Text(item.name),
                          subtitle: item.quantity == null
                              ? null
                              : Text(
                                  item.unit == null
                                      ? '수량 ${item.quantity}'
                                      : '수량 ${item.quantity} ${item.unit}',
                                ),
                          onChanged: (bool? value) {
                            if (value == null) {
                              return;
                            }
                            onToggleItem(item, value);
                          },
                        ),
                      ),
                      const SizedBox(height: 4),
                      Align(
                        alignment: Alignment.centerRight,
                        child: FilledButton.tonal(
                          onPressed: () => onCompleteList(list),
                          child: const Text('장보기 완료'),
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
      error: (Object err, StackTrace _) => Center(
        child: Text(
          '장보기 목록을 불러오지 못했습니다.\n$err',
          textAlign: TextAlign.center,
        ),
      ),
    );
  }
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
                contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                title: Text(session.recipeTitle),
                subtitle: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(session.createdAt.replaceFirst('T', ' ').split('.').first),
                    if (feedback.isNotEmpty) Text(feedback.join(' · ')),
                    if (session.note != null && session.note!.isNotEmpty) Text(session.note!),
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
