import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/widgets/centered_state_view.dart';
import '../../auth/application/auth_providers.dart';
import '../application/unified_recipe_providers.dart';
import '../domain/unified_recipe.dart';
import 'bookmarked_recipes_page.dart';
import 'recipe_thumbnail.dart';

class MyRecipesPage extends ConsumerStatefulWidget {
  const MyRecipesPage({
    super.key,
    this.initialTab = 0,
  });

  final int initialTab;

  @override
  ConsumerState<MyRecipesPage> createState() => _MyRecipesPageState();
}

class _MyRecipesPageState extends ConsumerState<MyRecipesPage>
    with SingleTickerProviderStateMixin {
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';
  late final TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(
      length: 2,
      vsync: this,
      initialIndex: widget.initialTab.clamp(0, 1).toInt(),
    );
  }

  @override
  void dispose() {
    _searchController.dispose();
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _refresh() async {
    ref.invalidate(myUnifiedRecipesProvider(_searchQuery));
    await ref.read(myUnifiedRecipesProvider(_searchQuery).future);
  }

  void _clearSearch() {
    _searchController.clear();

    setState(() {
      _searchQuery = '';
    });
  }

  void _openRecipe(BuildContext context, UnifiedRecipe recipe) {
    final encodedId = Uri.encodeComponent(recipe.identity.sourceId);

    switch (recipe.identity.sourceType) {
      case 'creator':
        context.push('/creator/$encodedId');
        return;
      case 'user':
        context.push('/my-recipes/$encodedId');
        return;
      case 'public':
        context.push('/recipes/$encodedId');
        return;
      default:
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('열 수 없는 레시피입니다.')),
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    final authUserAsync = ref.watch(authUserProvider);

    if (authUserAsync.isLoading) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    final currentUser = authUserAsync.valueOrNull;

    if (currentUser == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('내 레시피 관리')),
        body: CenteredStateView(
          icon: Icons.lock_outline,
          title: '로그인이 필요합니다',
          message: '로그인하면 저장하거나 만든 레시피를 한 곳에서 관리할 수 있습니다.',
          actionLabel: '로그인하기',
          onAction: () => context.push('/login'),
        ),
      );
    }

    final recipesAsync = ref.watch(myUnifiedRecipesProvider(_searchQuery));

    return Scaffold(
      appBar: AppBar(
        title: const Text('내 레시피 관리'),
        bottom: TabBar(
          controller: _tabController,
          tabs: const <Widget>[
            Tab(
              icon: Icon(Icons.menu_book_outlined),
              text: '직접 만든 레시피',
            ),
            Tab(
              icon: Icon(Icons.bookmark_outline),
              text: '저장한 레시피',
            ),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () async {
          final created = await context.push<bool>('/creator/new');

          if (created == true) {
            ref.invalidate(myUnifiedRecipesProvider);
          }
        },
        icon: const Icon(Icons.add),
        label: const Text('새 레시피'),
      ),
      body: TabBarView(
        controller: _tabController,
        children: <Widget>[
          recipesAsync.when(
            data: (recipes) {
              return _MyRecipeList(
                recipes: recipes,
                searchController: _searchController,
                searchQuery: _searchQuery,
                onSearchChanged: (value) {
                  setState(() {
                    _searchQuery = value;
                  });
                },
                onClearSearch: _clearSearch,
                onRefresh: _refresh,
                onOpenRecipe: (recipe) => _openRecipe(context, recipe),
              );
            },
            error: (error, stackTrace) {
              return CenteredStateView(
                icon: Icons.cloud_off_outlined,
                title: '레시피를 불러오지 못했습니다',
                message: '잠시 후 다시 시도해 주세요.',
                actionLabel: '다시 시도',
                onAction: () => ref.invalidate(
                  myUnifiedRecipesProvider(_searchQuery),
                ),
              );
            },
            loading: () {
              return const Center(child: CircularProgressIndicator());
            },
          ),
          const BookmarkedRecipesPage(showAppBar: false),
        ],
      ),
    );
  }
}

class _MyRecipeList extends StatelessWidget {
  const _MyRecipeList({
    required this.recipes,
    required this.searchController,
    required this.searchQuery,
    required this.onSearchChanged,
    required this.onClearSearch,
    required this.onRefresh,
    required this.onOpenRecipe,
  });

  final List<UnifiedRecipe> recipes;
  final TextEditingController searchController;
  final String searchQuery;
  final ValueChanged<String> onSearchChanged;
  final VoidCallback onClearSearch;
  final Future<void> Function() onRefresh;
  final ValueChanged<UnifiedRecipe> onOpenRecipe;

  @override
  Widget build(BuildContext context) {
    final itemCount = recipes.isEmpty ? 2 : recipes.length + 1;

    return RefreshIndicator(
      onRefresh: onRefresh,
      child: ListView.separated(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
        itemCount: itemCount,
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

          if (recipes.isEmpty) {
            return SizedBox(
              height: MediaQuery.of(context).size.height * 0.45,
              child: CenteredStateView(
                icon: searchQuery.trim().isEmpty
                    ? Icons.menu_book_outlined
                    : Icons.search_off,
                title: searchQuery.trim().isEmpty
                    ? '아직 저장된 레시피가 없습니다'
                    : '검색 결과가 없습니다',
                message: searchQuery.trim().isEmpty
                    ? '유튜브에서 저장하거나 새 레시피를 직접 만들어 보세요.'
                    : '검색어를 바꾸거나 검색을 지워보세요.',
              ),
            );
          }

          final recipe = recipes[index - 1];

          return _UnifiedRecipeTile(
            recipe: recipe,
            onTap: () => onOpenRecipe(recipe),
          );
        },
      ),
    );
  }
}

class _UnifiedRecipeTile extends StatelessWidget {
  const _UnifiedRecipeTile({
    required this.recipe,
    required this.onTap,
  });

  final UnifiedRecipe recipe;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final summary = (recipe.summary ?? '').trim();
    final subtitle = summary.isEmpty ? recipe.origin.label : summary;

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
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: <Widget>[
              _RecipeBadge(label: recipe.origin.label),
              _RecipeBadge(label: _provenanceLabel(recipe.provenance.type)),
            ],
          ),
        ],
      ),
      trailing: Text('${recipe.steps.length}단계'),
      isThreeLine: true,
      onTap: onTap,
    );
  }

  String _provenanceLabel(RecipeProvenanceType type) {
    return switch (type) {
      RecipeProvenanceType.youtube => 'YouTube',
      RecipeProvenanceType.manual => '직접 작성',
      RecipeProvenanceType.copied => '공개 레시피에서 저장',
      RecipeProvenanceType.imported => '가져온 레시피',
      RecipeProvenanceType.unknown => '출처 미확인',
    };
  }
}

class _RecipeBadge extends StatelessWidget {
  const _RecipeBadge({
    required this.label,
  });

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: 8,
        vertical: 3,
      ),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.secondaryContainer,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: Theme.of(context).textTheme.labelSmall,
      ),
    );
  }
}
