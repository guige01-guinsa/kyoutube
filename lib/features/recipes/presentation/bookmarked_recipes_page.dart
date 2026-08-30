import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../application/recipe_providers.dart';
import '../domain/bookmarked_recipe.dart';
import '../../../core/widgets/centered_state_view.dart';

class BookmarkedRecipesPage extends ConsumerWidget {
  const BookmarkedRecipesPage({
    super.key,
    this.showAppBar = true,
  });

  final bool showAppBar;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final bookmarkedAsync = ref.watch(bookmarkedRecipesProvider);

    final body = bookmarkedAsync.when(
      data: (List<BookmarkedRecipe> bookmarks) {
        if (bookmarks.isEmpty) {
          return CenteredStateView(
            icon: Icons.bookmark_outline,
            title: '저장한 북마크가 없습니다',
            message: '공개 또는 크리에이터 상세에서 북마크를 눌러 모아 보세요.',
            actionLabel: '공개 레시피 보기',
            onAction: () => context.push('/'),
          );
        }

        return RefreshIndicator(
          onRefresh: () async {
            ref.invalidate(bookmarkedRecipesProvider);
          },
          child: ListView.separated(
            physics: const AlwaysScrollableScrollPhysics(),
            itemCount: bookmarks.length,
            separatorBuilder: (_, __) => const Divider(height: 1),
            itemBuilder: (BuildContext context, int index) {
              final bookmarked = bookmarks[index];
              final recipe = bookmarked.recipe;
              final route = bookmarked.recipeType == 'creator'
                  ? '/creator/${recipe.id}'
                  : bookmarked.recipeType == 'user'
                      ? '/my-recipes/${recipe.id}'
                      : '/recipes/${recipe.id}';

              return ListTile(
                title: Text(recipe.title),
                subtitle: Text(
                  bookmarked.recipeType == 'creator'
                      ? '크리에이터 레시피'
                      : bookmarked.recipeType == 'user'
                          ? '개인 레시피'
                          : '공개 레시피',
                ),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => context.push(route),
              );
            },
          ),
        );
      },
      error: (Object err, StackTrace stack) => CenteredStateView(
        icon: Icons.cloud_off_outlined,
        title: '북마크를 불러오지 못했습니다',
        message: '잠시 후 다시 시도해 주세요.',
        actionLabel: '다시 시도',
        onAction: () => ref.invalidate(bookmarkedRecipesProvider),
      ),
      loading: () => const Center(child: CircularProgressIndicator()),
    );

    if (!showAppBar) {
      return body;
    }

    return Scaffold(
      appBar: AppBar(title: const Text('저장한 레시피')),
      body: body,
    );
  }
}
