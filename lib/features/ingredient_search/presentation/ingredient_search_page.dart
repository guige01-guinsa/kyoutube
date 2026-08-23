import 'dart:collection';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../kitchen/data/shopping_persistence.dart';
import '../data/ingredient_search_history_store.dart';

import '../../auth/application/auth_providers.dart';
import '../../kitchen/application/kitchen_providers.dart';
import '../../kitchen/domain/kitchen_models.dart';

class IngredientSearchPage extends ConsumerStatefulWidget {
  const IngredientSearchPage({super.key});

  @override
  ConsumerState<IngredientSearchPage> createState() =>
      _IngredientSearchPageState();
}

class _IngredientSearchPageState extends ConsumerState<IngredientSearchPage> {
  final TextEditingController _manualIngredientController =
      TextEditingController();

  final LinkedHashSet<String> _selectedIngredients = LinkedHashSet<String>();

  List<List<String>> _recentSearches = const <List<String>>[];
  bool _historyLoading = true;

  @override
  void initState() {
    super.initState();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadHistory();
    });
  }

  @override
  void dispose() {
    _manualIngredientController.dispose();
    super.dispose();
  }

  Future<IngredientSearchHistoryStore> _historyStore() async {
    return IngredientSearchHistoryStore(
      storage: SharedPreferencesKeyValueStore(
        await SharedPreferences.getInstance(),
      ),
    );
  }

  Future<void> _loadHistory() async {
    final user = ref.read(authUserProvider).valueOrNull;

    if (user == null) {
      if (mounted) {
        setState(() {
          _historyLoading = false;
        });
      }
      return;
    }

    try {
      final history = await (await _historyStore()).load(user.id);

      if (!mounted) {
        return;
      }

      setState(() {
        _recentSearches = history;
        _historyLoading = false;
      });
    } catch (_) {
      if (mounted) {
        setState(() {
          _historyLoading = false;
        });
      }
    }
  }

  Future<void> _clearHistory() async {
    final user = ref.read(authUserProvider).valueOrNull;

    if (user == null) {
      return;
    }

    await (await _historyStore()).clear(user.id);

    if (mounted) {
      setState(() {
        _recentSearches = const <List<String>>[];
      });
    }
  }

  void _toggleIngredient(String rawName) {
    final name = rawName.trim();

    if (name.isEmpty) {
      return;
    }

    final existing = _selectedIngredients
        .where((item) => item.toLowerCase() == name.toLowerCase())
        .toList(growable: false);

    setState(() {
      if (existing.isNotEmpty) {
        _selectedIngredients.remove(existing.first);
        return;
      }

      if (_selectedIngredients.length >= 5) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('한 번에 최대 5개의 재료를 선택할 수 있습니다.'),
          ),
        );
        return;
      }

      _selectedIngredients.add(name);
    });
  }

  void _addManualIngredient() {
    final ingredient = _manualIngredientController.text.trim();

    if (ingredient.isEmpty) {
      return;
    }

    _manualIngredientController.clear();
    _toggleIngredient(ingredient);
  }

  Future<void> _search() async {
    final user = ref.read(authUserProvider).valueOrNull;

    if (user == null) {
      context.push('/login');
      return;
    }

    if (_selectedIngredients.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('최소 1개 이상의 재료를 선택해 주세요.')),
      );
      return;
    }

    final selected = _selectedIngredients.toList(growable: false);
    final historyStore = await _historyStore();
    final history = await historyStore.add(user.id, selected);

    if (!mounted) {
      return;
    }

    setState(() {
      _recentSearches = history;
    });

    final query = Uri.encodeQueryComponent(selected.join(','));

    context.push('/ingredient-search/results?ingredients=$query');
  }

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(authUserProvider).valueOrNull;

    if (user == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('보유 재료로 찾기')),
        body: Center(
          child: FilledButton(
            onPressed: () => context.push('/login'),
            child: const Text('로그인하기'),
          ),
        ),
      );
    }

    final ingredientsAsync = ref.watch(kitchenIngredientsProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('보유 재료로 찾기')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 20, 16, 28),
          children: <Widget>[
            Text(
              '보유한 재료를 선택하면\n만들 수 있는 레시피를 찾아드려요.',
              style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
            ),
            const SizedBox(height: 24),
            Row(
              children: <Widget>[
                Expanded(
                  child: Text(
                    '선택 재료',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
                TextButton(
                  onPressed: _selectedIngredients.isEmpty
                      ? null
                      : () => setState(_selectedIngredients.clear),
                  child: const Text('전체 해제'),
                ),
              ],
            ),
            Container(
              width: double.infinity,
              constraints: const BoxConstraints(minHeight: 76),
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                border: Border.all(
                  color: Theme.of(context).colorScheme.primary,
                  width: 1.5,
                ),
                borderRadius: BorderRadius.circular(14),
              ),
              child: _selectedIngredients.isEmpty
                  ? const Align(
                      alignment: Alignment.centerLeft,
                      child: Text('냉장고 재료를 선택하거나 직접 입력해 주세요.'),
                    )
                  : Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: _selectedIngredients
                          .map(
                            (ingredient) => InputChip(
                              label: Text(ingredient),
                              onDeleted: () => _toggleIngredient(ingredient),
                            ),
                          )
                          .toList(growable: false),
                    ),
            ),
            const SizedBox(height: 8),
            const Text('최대 5개까지 선택할 수 있습니다.'),
            const SizedBox(height: 20),
            Row(
              children: <Widget>[
                Expanded(
                  child: TextField(
                    controller: _manualIngredientController,
                    textInputAction: TextInputAction.done,
                    onSubmitted: (_) => _addManualIngredient(),
                    decoration: const InputDecoration(
                      border: OutlineInputBorder(),
                      hintText: '재료를 직접 입력하세요',
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                FilledButton(
                  onPressed: _addManualIngredient,
                  child: const Text('추가'),
                ),
              ],
            ),
            const SizedBox(height: 24),
            Text(
              '내 냉장고 재료',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            ingredientsAsync.when(
              data: (List<KitchenIngredient> ingredients) {
                if (ingredients.isEmpty) {
                  return const Text('냉장고 재료가 없습니다. 재료 관리에서 추가해 주세요.');
                }

                return Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: ingredients.map((ingredient) {
                    final selected = _selectedIngredients.any(
                      (item) =>
                          item.toLowerCase() == ingredient.name.toLowerCase(),
                    );

                    return FilterChip(
                      selected: selected,
                      label: Text(ingredient.name),
                      onSelected: (_) => _toggleIngredient(ingredient.name),
                    );
                  }).toList(growable: false),
                );
              },
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (_, __) => const Text('냉장고 재료를 불러오지 못했습니다.'),
            ),
            const SizedBox(height: 24),
            Row(
              children: <Widget>[
                Expanded(
                  child: Text(
                    '최근 검색어',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
                TextButton(
                  onPressed: _historyLoading || _recentSearches.isEmpty
                      ? null
                      : _clearHistory,
                  child: const Text('전체 삭제'),
                ),
              ],
            ),
            if (_historyLoading)
              const Padding(
                padding: EdgeInsets.all(12),
                child: Center(child: CircularProgressIndicator()),
              )
            else if (_recentSearches.isEmpty)
              const Text('최근 재료 검색어가 없습니다.')
            else
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: _recentSearches.map((entry) {
                  return ActionChip(
                    label: Text(entry.join(' · ')),
                    onPressed: () {
                      setState(() {
                        _selectedIngredients
                          ..clear()
                          ..addAll(entry.take(5));
                      });
                    },
                  );
                }).toList(growable: false),
              ),
            const SizedBox(height: 28),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: _search,
                icon: const Icon(Icons.search),
                label: const Text('보유 재료로 레시피 찾기'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
