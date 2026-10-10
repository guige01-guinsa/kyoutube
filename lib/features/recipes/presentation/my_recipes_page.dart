import '../../../core/auth/auth_return.dart';
import '../../workspace/presentation/workspace_frame.dart';
import 'package:flutter/material.dart';
import 'package:k_youtube/core/localization/localized_text.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/widgets/centered_state_view.dart';
import '../../../core/widgets/scout_page.dart';
import '../../../core/widgets/scout_navigation_bar.dart';
import '../../../core/theme/app_theme.dart';
import '../../auth/application/auth_providers.dart';
import '../application/unified_recipe_providers.dart';
import '../application/recipe_library_provider.dart';
import '../domain/recipe_library_name.dart';
import '../../../core/localization/app_localizations.dart';
import '../domain/unified_recipe.dart';
import 'recipe_search_exclusions_page.dart';
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
  _RecipeSort _sort = _RecipeSort.reviewFirst;
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

  Future<void> _openRecipe(BuildContext context, UnifiedRecipe recipe) async {
    final encodedId = Uri.encodeComponent(recipe.identity.sourceId);

    Future<void> openAndRefresh(String location) async {
      final deleted = await context.push<bool>(location);

      if (deleted == true && mounted) {
        ref.invalidate(myUnifiedRecipesProvider(_searchQuery));
      }
    }

    switch (recipe.identity.sourceType) {
      case 'creator':
        await openAndRefresh('/creator/$encodedId');
        return;
      case 'user':
        await openAndRefresh('/my-recipes/$encodedId');
        return;
      case 'public':
        context.push('/recipes/$encodedId');
        return;
      default:
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: LocalizedText('열 수 없는 레시피입니다.')),
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    final authUserAsync = ref.watch(authUserProvider);
    final libraryTitle = recipeLibraryName(
        owner: ref.watch(recipeOwnerNameProvider),
        english: AppLocalizations.of(context).isEnglish);

    if (authUserAsync.isLoading) {
      return const Scaffold(
        bottomNavigationBar: ScoutNavigationBar(selectedIndex: 1),
        body: Center(child: CircularProgressIndicator()),
      );
    }

    final currentUser = authUserAsync.valueOrNull;

    if (currentUser == null) {
      return Scaffold(
        bottomNavigationBar: const ScoutNavigationBar(selectedIndex: 1),
        appBar: AppBar(title: Text(libraryTitle)),
        body: CenteredStateView(
          icon: Icons.lock_outline,
          title: '로그인이 필요합니다',
          message: '로그인하면 저장하거나 만든 레시피를 한 곳에서 관리할 수 있습니다.',
          actionLabel: context.tr('로그인하기'),
          onAction: () => context.push(
              loginFor(GoRouterState.of(context).uri.toString(), resume: true)),
        ),
      );
    }

    final recipesAsync = ref.watch(myUnifiedRecipesProvider(_searchQuery));

    return Scaffold(
      bottomNavigationBar: const ScoutNavigationBar(selectedIndex: 1),
      appBar: AppBar(
        title: Text(libraryTitle),
        actions: [
          IconButton(
              key: const Key('recipe-professional-tools'),
              tooltip: context.tr('전문 도구'),
              onPressed: () => context.push('/chef'),
              icon: const Icon(Icons.science_outlined)),
          if (MediaQuery.sizeOf(context).width < 480 ||
              MediaQuery.textScalerOf(context).scale(1) > 1.3)
            IconButton(
              key: const Key('create-recipe-action'),
              tooltip: context.tr('새 레시피'),
              onPressed: () async {
                final created = await context.push<bool>('/creator/new');
                if (created == true) {
                  ref.invalidate(myUnifiedRecipesProvider);
                }
              },
              icon: const Icon(Icons.add_circle_outline),
            )
          else
            TextButton.icon(
              key: const Key('create-recipe-action'),
              label: const LocalizedText('새 레시피'),
              onPressed: () async {
                final created = await context.push<bool>('/creator/new');

                if (created == true) {
                  ref.invalidate(myUnifiedRecipesProvider);
                }
              },
              icon: const Icon(Icons.add_circle_outline),
            ),
        ],
        bottom: TabBar(
          controller: _tabController,
          tabs: <Widget>[
            Tab(
              icon: const Icon(Icons.menu_book_outlined),
              text: context.tr('나의 레시피'),
            ),
            Tab(
              icon: const Icon(Icons.visibility_off_outlined),
              text: context.tr('검색 제외 레시피'),
            ),
          ],
        ),
      ),
      body: Center(
          child: ConstrainedBox(
              constraints: BoxConstraints(
                  maxWidth: WorkspaceScope.active(context)
                      ? 1180
                      : ScoutStyle.contentWidth),
              child: TabBarView(
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
                        sort: _sort,
                        onSortChanged: (value) {
                          setState(() {
                            _sort = value;
                          });
                        },
                        onRefresh: _refresh,
                        onOpenRecipe: (recipe) {
                          _openRecipe(context, recipe);
                        },
                      );
                    },
                    error: (error, stackTrace) {
                      return CenteredStateView(
                        icon: Icons.cloud_off_outlined,
                        title: '레시피를 불러오지 못했습니다',
                        message: '잠시 후 다시 시도해 주세요.',
                        actionLabel: context.tr('다시 시도'),
                        onAction: () => ref.invalidate(
                          myUnifiedRecipesProvider(_searchQuery),
                        ),
                      );
                    },
                    loading: () {
                      return const Center(child: CircularProgressIndicator());
                    },
                  ),
                  const RecipeSearchExclusionsPage(showAppBar: false),
                ],
              ))),
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
    required this.sort,
    required this.onSortChanged,
    required this.onRefresh,
    required this.onOpenRecipe,
  });

  final List<UnifiedRecipe> recipes;
  final TextEditingController searchController;
  final String searchQuery;
  final ValueChanged<String> onSearchChanged;
  final VoidCallback onClearSearch;
  final _RecipeSort sort;
  final ValueChanged<_RecipeSort> onSortChanged;
  final Future<void> Function() onRefresh;
  final ValueChanged<UnifiedRecipe> onOpenRecipe;

  @override
  Widget build(BuildContext context) {
    final sortedRecipes = List<UnifiedRecipe>.from(recipes)
      ..sort((left, right) => _compareRecipes(left, right, sort));
    return LayoutBuilder(builder: (context, box) {
      final columns = box.maxWidth >= 760 &&
              MediaQuery.textScalerOf(context).scale(1) <= 1.3
          ? 2
          : 1;
      final itemCount = sortedRecipes.isEmpty
          ? 2
          : (sortedRecipes.length / columns).ceil() + 1;

      return RefreshIndicator(
        onRefresh: onRefresh,
        child: ListView.separated(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
          itemCount: itemCount,
          separatorBuilder: (_, __) => const SizedBox(height: 14),
          itemBuilder: (BuildContext context, int index) {
            if (index == 0) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  ScoutSectionLabel(
                    title: context.tr('다시 만들고 싶은 맛을 모아두세요.'),
                    subtitle:
                        Localizations.localeOf(context).languageCode != 'ko'
                            ? '${recipes.length} recipes in this result'
                            : '현재 목록 ${recipes.length}개',
                  ),
                  ScoutAdaptiveGrid(minTileWidth: 320, gap: 12, children: [
                    TextField(
                      controller: searchController,
                      decoration: InputDecoration(
                        labelText: context.tr('저장한 레시피 검색'),
                        hintText: context.tr('제목, 재료, 메모로 검색'),
                        prefixIcon: const Icon(Icons.search),
                        suffixIcon: searchQuery.isEmpty
                            ? null
                            : IconButton(
                                onPressed: onClearSearch,
                                tooltip: context.tr('검색 지우기'),
                                icon: const Icon(Icons.clear),
                              ),
                        border: const OutlineInputBorder(),
                      ),
                      onChanged: onSearchChanged,
                    ),
                    DropdownButtonFormField<_RecipeSort>(
                      isExpanded: true,
                      itemHeight: null,
                      initialValue: sort,
                      decoration: InputDecoration(
                        labelText: context.tr('정렬'),
                        prefixIcon: const Icon(Icons.sort),
                        border: const OutlineInputBorder(),
                      ),
                      items: _RecipeSort.values
                          .map(
                            (value) => DropdownMenuItem<_RecipeSort>(
                              value: value,
                              child: LocalizedText(value.label),
                            ),
                          )
                          .toList(growable: false),
                      onChanged: (value) {
                        if (value != null) onSortChanged(value);
                      },
                    ),
                  ]),
                ],
              );
            }

            if (recipes.isEmpty) {
              return SizedBox(
                height: MediaQuery.of(context).size.height * 0.65,
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

            final start = (index - 1) * columns;
            return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              for (var column = 0; column < columns; column++) ...[
                if (column > 0) const SizedBox(width: 16),
                Expanded(
                    child: start + column >= sortedRecipes.length
                        ? const SizedBox.shrink()
                        : _UnifiedRecipeTile(
                            recipe: sortedRecipes[start + column],
                            onTap: () =>
                                onOpenRecipe(sortedRecipes[start + column]))),
              ],
            ]);
          },
        ),
      );
    });
  }

  static int _compareRecipes(
    UnifiedRecipe left,
    UnifiedRecipe right,
    _RecipeSort sort,
  ) {
    return switch (sort) {
      _RecipeSort.reviewFirst =>
        _qualityRank(left).compareTo(_qualityRank(right)),
      _RecipeSort.completeFirst =>
        _qualityRank(right).compareTo(_qualityRank(left)),
      _RecipeSort.mostSteps => right.steps.length.compareTo(left.steps.length),
      _RecipeSort.title =>
        left.title.toLowerCase().compareTo(right.title.toLowerCase()),
    };
  }

  static int _qualityRank(UnifiedRecipe recipe) {
    if (recipe.ingredients.isEmpty || recipe.steps.isEmpty) return 0;
    if (<String>[...recipe.ingredients, ...recipe.steps]
        .any((text) => RegExp(r'확인\s*필요|\[추정\]').hasMatch(text))) {
      return 1;
    }
    return 2;
  }
}

enum _RecipeSort {
  reviewFirst('확인 필요 우선'),
  completeFirst('기본 정보가 많은 순'),
  mostSteps('조리 단계가 많은 순'),
  title('이름순');

  const _RecipeSort(this.label);

  final String label;
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

    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        RecipeThumbnail(
                            imageUrl: recipe.imageUrl, width: 76, height: 88),
                        const SizedBox(width: 14),
                        Expanded(
                            child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: <Widget>[
                              LocalizedText(recipe.title,
                                  style:
                                      Theme.of(context).textTheme.titleMedium),
                              const SizedBox(height: 5),
                              LocalizedText(subtitle,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: Theme.of(context).textTheme.bodySmall),
                              const SizedBox(height: 8),
                              LocalizedText(
                                  '재료 ${recipe.ingredients.length}개 · ${recipe.steps.length}단계',
                                  style: Theme.of(context)
                                      .textTheme
                                      .labelMedium
                                      ?.copyWith(color: ScoutStyle.muted)),
                            ])),
                      ]),
                  const SizedBox(height: 14),
                  Wrap(spacing: 6, runSpacing: 6, children: <Widget>[
                    _RecipeBadge(
                        label: _provenanceLabel(recipe.provenance.type)),
                    _RecipeBadge(label: _qualityLabel(recipe)),
                  ]),
                ]),
          )),
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

  String _qualityLabel(UnifiedRecipe recipe) {
    if (recipe.ingredients.isEmpty || recipe.steps.isEmpty) {
      return '정보 부족';
    }
    if (<String>[...recipe.ingredients, ...recipe.steps]
        .any((text) => RegExp(r'확인\s*필요|\[추정\]').hasMatch(text))) {
      return '검토 필요';
    }
    return '기본 정보 있음';
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
      child: LocalizedText(
        label,
        style: Theme.of(context).textTheme.labelSmall,
      ),
    );
  }
}
