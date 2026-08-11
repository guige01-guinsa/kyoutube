import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/widgets/centered_state_view.dart';
import '../../auth/application/auth_providers.dart';
import '../application/recipe_providers.dart';
import '../domain/recipe.dart';
import 'recipe_thumbnail.dart';

enum _MyRecipeType {
  personal,
  creator,
}

class _MyRecipeItem {
  const _MyRecipeItem({
    required this.recipe,
    required this.type,
  });

  final Recipe recipe;
  final _MyRecipeType type;
}

class MyRecipesPage extends ConsumerStatefulWidget {
  const MyRecipesPage({super.key});

  @override
  ConsumerState<MyRecipesPage> createState() => _MyRecipesPageState();
}

class _MyRecipesPageState extends ConsumerState<MyRecipesPage> {
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  bool _matchesSearch(Recipe recipe) {
    final query = _searchQuery.trim().toLowerCase();

    if (query.isEmpty) {
      return true;
    }

    final text = <String>[
      recipe.title,
      recipe.summary ?? '',
      recipe.notes ?? '',
      ...recipe.ingredients,
      ...recipe.steps,
    ].join(' ').toLowerCase();

    return text.contains(query);
  }

  Future<void> _refresh() async {
    await Future.wait(<Future<void>>[
      ref.refresh(subscriberRecipesProvider.future),
      ref.refresh(creatorRecipesProvider(_searchQuery).future),
    ]);
  }

  @override
  Widget build(BuildContext context) {
    final authUserAsync = ref.watch(authUserProvider);
    final currentUser = authUserAsync.valueOrNull;

    if (currentUser == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('내 레시피')),
        body: CenteredStateView(
          icon: Icons.lock_outline,
          title: '로그인이 필요합니다.',
          message: '로그인 후 내 요리 노트와 내가 만든 레시피를 관리할 수 있습니다.',
          actionLabel: '로그인하기',
          onAction: () => context.push('/login'),
        ),
      );
    }

    final personalAsync = ref.watch(subscriberRecipesProvider);
    final creatorAsync = ref.watch(creatorRecipesProvider(_searchQuery));

    if (personalAsync.isLoading || creatorAsync.isLoading) {
      return const Scaffold(
        body: Center(
          child: CircularProgressIndicator(),
        ),
      );
    }

    if (personalAsync.hasError || creatorAsync.hasError) {
      return Scaffold(
        appBar: AppBar(title: const Text('내 레시피')),
        body: CenteredStateView(
          icon: Icons.cloud_off_outlined,
          title: '내 레시피를 불러오지 못했습니다.',
          message: '잠시 후 다시 시도해 주세요.',
          actionLabel: '다시 시도',
          onAction: _refresh,
        ),
      );
    }

    final personalRecipes = personalAsync.valueOrNull ?? const <Recipe>[];
    final creatorRecipes = creatorAsync.valueOrNull ?? const <Recipe>[];

    final personalItems = personalRecipes
        .where(_matchesSearch)
        .map(
          (recipe) => _MyRecipeItem(
            recipe: recipe,
            type: _MyRecipeType.personal,
          ),
        )
        .toList();

    final creatorItems = creatorRecipes
        .map(
          (recipe) => _MyRecipeItem(
            recipe: recipe,
            type: _MyRecipeType.creator,
          ),
        )
        .toList();

    final allItems = <_MyRecipeItem>[
      ...personalItems,
      ...creatorItems,
    ]..sort(
        (a, b) => a.recipe.title.compareTo(b.recipe.title),
      );

    return DefaultTabController(
      length: 3,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('내 레시피'),
          bottom: const TabBar(
            tabs: <Widget>[
              Tab(text: '전체'),
              Tab(text: '내 요리 노트'),
              Tab(text: '내가 만든 레시피'),
            ],
          ),
        ),
        floatingActionButton: FloatingActionButton.extended(
          onPressed: () async {
            final created = await context.push<bool>('/creator/new');

            if (created == true) {
              ref.invalidate(creatorRecipesProvider);
            }
          },
          icon: const Icon(Icons.add),
          label: const Text('새 레시피'),
        ),
        body: TabBarView(
          children: <Widget>[
            _MyRecipeList(
              items: allItems,
              searchController: _searchController,
              searchQuery: _searchQuery,
              onSearchChanged: (value) {
                setState(() {
                  _searchQuery = value;
                });
              },
              onClearSearch: () {
                _searchController.clear();

                setState(() {
                  _searchQuery = '';
                });
              },
              onRefresh: _refresh,
            ),
            _MyRecipeList(
              items: personalItems,
              searchController: _searchController,
              searchQuery: _searchQuery,
              onSearchChanged: (value) {
                setState(() {
                  _searchQuery = value;
                });
              },
              onClearSearch: () {
                _searchController.clear();

                setState(() {
                  _searchQuery = '';
                });
              },
              onRefresh: _refresh,
            ),
            _MyRecipeList(
              items: creatorItems,
              searchController: _searchController,
              searchQuery: _searchQuery,
              onSearchChanged: (value) {
                setState(() {
                  _searchQuery = value;
                });
              },
              onClearSearch: () {
                _searchController.clear();

                setState(() {
                  _searchQuery = '';
                });
              },
              onRefresh: _refresh,
            ),
          ],
        ),
      ),
    );
  }
}

class _MyRecipeList extends StatelessWidget {
  const _MyRecipeList({
    required this.items,
    required this.searchController,
    required this.searchQuery,
    required this.onSearchChanged,
    required this.onClearSearch,
    required this.onRefresh,
  });

  final List<_MyRecipeItem> items;
  final TextEditingController searchController;
  final String searchQuery;
  final ValueChanged<String> onSearchChanged;
  final VoidCallback onClearSearch;
  final Future<void> Function() onRefresh;

  @override
  Widget build(BuildContext context) {
    return RefreshIndicator(
      onRefresh: onRefresh,
      child: ListView.separated(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
        itemCount: items.length + 1,
        separatorBuilder: (_, __) => const Divider(height: 24),
        itemBuilder: (BuildContext context, int index) {
          if (index == 0) {
            return TextField(
              controller: searchController,
              decoration: InputDecoration(
                labelText: '내 레시피 검색',
                hintText: '제목, 재료, 메모로 검색',
                prefixIcon: const Icon(Icons.search),
                suffixIcon: searchQuery.isEmpty
                    ? null
                    : IconButton(
                        onPressed: onClearSearch,
                        icon: const Icon(Icons.clear),
                      ),
                border: const OutlineInputBorder(),
              ),
              onChanged: onSearchChanged,
            );
          }

          if (items.isEmpty) {
            return const CenteredStateView(
              icon: Icons.menu_book_outlined,
              title: '등록한 레시피가 없습니다.',
              message: '공개 레시피를 내 요리 노트에 저장하거나 새 레시피를 만들어 보세요.',
            );
          }

          final item = items[index - 1];
          final recipe = item.recipe;
          final isPersonal = item.type == _MyRecipeType.personal;

          final subtitle = isPersonal
              ? ((recipe.notes ?? '').trim().isEmpty
                  ? '내 요리 노트'
                  : recipe.notes!)
              : (recipe.summary ?? '내가 만든 레시피');

          return ListTile(
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 4,
              vertical: 4,
            ),
            leading: RecipeThumbnail(imageUrl: recipe.imageUrl),
            title: Text(recipe.title),
            subtitle: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                const SizedBox(height: 4),
                Text(
                  subtitle,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 6),
                _RecipeTypeBadge(type: item.type),
              ],
            ),
            trailing: Text('${recipe.steps.length}단계'),
            isThreeLine: true,
            onTap: () {
              if (isPersonal) {
                context.push('/my-recipes/${recipe.id}');
              } else {
                context.push('/creator/${recipe.id}');
              }
            },
          );
        },
      ),
    );
  }
}

class _RecipeTypeBadge extends StatelessWidget {
  const _RecipeTypeBadge({
    required this.type,
  });

  final _MyRecipeType type;

  @override
  Widget build(BuildContext context) {
    final isPersonal = type == _MyRecipeType.personal;

    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: 8,
        vertical: 3,
      ),
      decoration: BoxDecoration(
        color: isPersonal
            ? Theme.of(context).colorScheme.secondaryContainer
            : Theme.of(context).colorScheme.primaryContainer,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        isPersonal ? '내 요리 노트' : '내가 만든 레시피',
        style: Theme.of(context).textTheme.labelSmall,
      ),
    );
  }
}