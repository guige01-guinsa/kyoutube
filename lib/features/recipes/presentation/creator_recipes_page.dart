import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../auth/application/auth_providers.dart';
import '../../../core/widgets/centered_state_view.dart';
import '../application/recipe_providers.dart';
import '../domain/recipe.dart';
import 'recipe_thumbnail.dart';

class CreatorRecipesPage extends ConsumerStatefulWidget {
  const CreatorRecipesPage({super.key});

  @override
  ConsumerState<CreatorRecipesPage> createState() => _CreatorRecipesPageState();
}

class _CreatorRecipesPageState extends ConsumerState<CreatorRecipesPage> {
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final authUserAsync = ref.watch(authUserProvider);
    final currentUser = authUserAsync.valueOrNull;
    final recipesAsync = ref.watch(creatorRecipesProvider(_searchQuery));

    if (currentUser == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('내 레시피 관리')),
        body: CenteredStateView(
          icon: Icons.lock_outline,
          title: '로그인이 필요합니다',
          message: '로그인 후 크리에이터 레시피를 관리할 수 있습니다.',
          actionLabel: '로그인하기',
          onAction: () => context.push('/login'),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(title: const Text('내 레시피 관리')),
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
      body: recipesAsync.when(
        data: (List<Recipe> recipes) {
          if (recipes.isEmpty) {
            return ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.only(bottom: 96),
              children: <Widget>[
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                  child: TextField(
                    controller: _searchController,
                    decoration: InputDecoration(
                      labelText: '내 레시피 검색',
                      hintText: '제목으로 검색',
                      prefixIcon: const Icon(Icons.search),
                      suffixIcon: _searchQuery.isEmpty
                          ? null
                          : IconButton(
                              onPressed: () {
                                _searchController.clear();
                                setState(() {
                                  _searchQuery = '';
                                });
                              },
                              icon: const Icon(Icons.clear),
                            ),
                      border: const OutlineInputBorder(),
                    ),
                    onChanged: (String value) {
                      setState(() {
                        _searchQuery = value;
                      });
                    },
                  ),
                ),
                const SizedBox(height: 24),
                CenteredStateView(
                  icon: _searchQuery.isNotEmpty
                      ? Icons.search_off
                      : Icons.post_add,
                  title: _searchQuery.isNotEmpty
                      ? '검색 결과가 없습니다'
                      : '등록한 크리에이터 레시피가 없습니다',
                  message: _searchQuery.isNotEmpty
                      ? '검색어를 바꾸거나 검색을 지워 보세요.'
                      : '첫 크리에이터 레시피를 만들어 시작해 보세요.',
                  actionLabel:
                      _searchQuery.isNotEmpty ? '검색 지우기' : '새 레시피 만들기',
                  onAction: () {
                    if (_searchQuery.isNotEmpty) {
                      _searchController.clear();
                      setState(() {
                        _searchQuery = '';
                      });
                      return;
                    }

                    context.push('/creator/new');
                  },
                ),
              ],
            );
          }

          return RefreshIndicator(
            onRefresh: () async {
              ref.invalidate(creatorRecipesProvider(_searchQuery));
            },
            child: ListView.separated(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.only(bottom: 96),
              itemCount: recipes.length + 1,
              separatorBuilder: (_, __) => const Divider(height: 1),
              itemBuilder: (BuildContext context, int index) {
                if (index == 0) {
                  return Padding(
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                    child: TextField(
                      controller: _searchController,
                      decoration: InputDecoration(
                        labelText: '내 레시피 검색',
                        hintText: '제목으로 검색',
                        prefixIcon: const Icon(Icons.search),
                        suffixIcon: _searchQuery.isEmpty
                            ? null
                            : IconButton(
                                onPressed: () {
                                  _searchController.clear();
                                  setState(() {
                                    _searchQuery = '';
                                  });
                                },
                                icon: const Icon(Icons.clear),
                              ),
                        border: const OutlineInputBorder(),
                      ),
                      onChanged: (String value) {
                        setState(() {
                          _searchQuery = value;
                        });
                      },
                    ),
                  );
                }

                final recipe = recipes[index - 1];
                return ListTile(
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 8,
                  ),
                  leading: RecipeThumbnail(imageUrl: recipe.imageUrl),
                  title: Text(recipe.title),
                  subtitle: Text(recipe.summary ?? '요약 없음'),
                  trailing: Text('${recipe.steps.length}단계'),
                  onTap: () => context.push('/creator/${recipe.id}'),
                );
              },
            ),
          );
        },
        error: (Object err, StackTrace stack) => CenteredStateView(
          icon: Icons.cloud_off_outlined,
          title: '내 레시피를 불러오지 못했습니다',
          message: '잠시 후 다시 시도해 주세요.',
          actionLabel: '다시 시도',
          onAction: () => ref.invalidate(creatorRecipesProvider(_searchQuery)),
        ),
        loading: () => const Center(child: CircularProgressIndicator()),
      ),
    );
  }
}
