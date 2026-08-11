import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import '../application/recipe_providers.dart';
import '../domain/recipe.dart';
import 'create_creator_recipe_page.dart';

class CreatorRecipeDetailPage extends ConsumerWidget {
  const CreatorRecipeDetailPage({
    super.key,
    required this.recipeId,
  });

  final String recipeId;

  Future<void> _openYoutubeUrl(BuildContext context, String url) async {
    final uri = Uri.tryParse(url);

    if (uri == null || !(uri.isScheme('http') || uri.isScheme('https'))) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('유효한 YouTube 링크가 아닙니다.')),
        );
      }
      return;
    }

    final launched = await launchUrl(
      uri,
      mode: LaunchMode.externalApplication,
    );

    if (!launched && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('YouTube 링크를 열 수 없습니다.')),
      );
    }
  }

  Future<void> _delete(
    BuildContext context,
    WidgetRef ref,
    Recipe recipe,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('레시피 삭제'),
          content: const Text('이 레시피를 삭제하시겠습니까?'),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('취소'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('삭제'),
            ),
          ],
        );
      },
    );

    if (confirmed != true) {
      return;
    }

    final repository = ref.read(recipeRepositoryProvider);
    final imageService = ref.read(recipeImageServiceProvider);

    await repository.deleteCreatorRecipe(recipeId);

    final imageUrl = recipe.imageUrl;
    if ((imageUrl ?? '').isNotEmpty) {
      try {
        await imageService.deleteCreatorRecipeImageByUrl(imageUrl!);
      } catch (_) {
        // 이미지 삭제 실패는 레시피 삭제 성공을 막지 않습니다.
      }
    }

    ref.invalidate(creatorRecipesProvider);
    ref.invalidate(creatorRecipeByIdProvider(recipeId));

    if (context.mounted) {
      context.go('/my-recipes');
    }
  }

  Future<void> _edit(
    BuildContext context,
    WidgetRef ref,
    Recipe recipe,
  ) async {
    final updated = await Navigator.of(context).push<bool>(
      MaterialPageRoute<bool>(
        builder: (_) => CreateCreatorRecipePage(initialRecipe: recipe),
      ),
    );

    if (updated == true) {
      ref.invalidate(creatorRecipeByIdProvider(recipeId));
      ref.invalidate(creatorRecipesProvider);
    }
  }

  void _goHome(BuildContext context) {
    context.go('/');
  }

  void _goMyRecipes(BuildContext context) {
    context.go('/my-recipes');
  }

  void _goShoppingReview(BuildContext context) {
    final source = Uri.encodeQueryComponent('creator:$recipeId');
    context.push('/shopping-review?source=$source');
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final recipeAsync = ref.watch(creatorRecipeByIdProvider(recipeId));

    return Scaffold(
      appBar: AppBar(
        title: const Text('내 레시피 상세'),
        actions: <Widget>[
          recipeAsync.maybeWhen(
            data: (Recipe? recipe) {
              if (recipe == null) {
                return const SizedBox.shrink();
              }

              return IconButton(
                onPressed: () => _edit(context, ref, recipe),
                icon: const Icon(Icons.edit_outlined),
                tooltip: '편집',
              );
            },
            orElse: () => const SizedBox.shrink(),
          ),
          recipeAsync.maybeWhen(
            data: (Recipe? recipe) {
              if (recipe == null) {
                return const SizedBox.shrink();
              }

              return IconButton(
                onPressed: () => _delete(context, ref, recipe),
                icon: const Icon(Icons.delete_outline),
                tooltip: '삭제',
              );
            },
            orElse: () => const SizedBox.shrink(),
          ),
        ],
      ),
      body: recipeAsync.when(
        data: (Recipe? recipe) {
          if (recipe == null) {
            return const Center(
              child: Text('레시피를 찾을 수 없습니다.'),
            );
          }

          return ListView(
            padding: const EdgeInsets.all(16),
            children: <Widget>[
              if ((recipe.imageUrl ?? '').isNotEmpty) ...<Widget>[
                ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: AspectRatio(
                    aspectRatio: 16 / 9,
                    child: Image.network(
                      recipe.imageUrl!,
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) {
                        return const ColoredBox(
                          color: Color(0x11000000),
                          child: Center(
                            child: Text('이미지를 불러올 수 없습니다.'),
                          ),
                        );
                      },
                    ),
                  ),
                ),
                const SizedBox(height: 16),
              ],
              Text(
                recipe.title,
                style: Theme.of(context).textTheme.headlineSmall,
              ),
              const SizedBox(height: 8),
              Text(
                (recipe.summary ?? '').trim().isEmpty
                    ? '요약 정보가 없습니다.'
                    : recipe.summary!,
              ),
              const SizedBox(height: 24),
              const _SectionTitle(
                title: '재료',
                icon: Icons.soup_kitchen_outlined,
              ),
              const SizedBox(height: 8),
              if (recipe.ingredients.isEmpty)
                const Text('등록된 재료가 없습니다.')
              else
                ...recipe.ingredients.map(
                  (String item) => Padding(
                    padding: const EdgeInsets.only(bottom: 4),
                    child: Text('- $item'),
                  ),
                ),
              const SizedBox(height: 24),
              const _SectionTitle(
                title: '조리 순서',
                icon: Icons.format_list_numbered,
              ),
              const SizedBox(height: 8),
              if (recipe.steps.isEmpty)
                const Text('등록된 조리 순서가 없습니다.')
              else
                ...recipe.steps.asMap().entries.map(
                      (entry) => Padding(
                        padding: const EdgeInsets.only(bottom: 6),
                        child: Text('${entry.key + 1}. ${entry.value}'),
                      ),
                    ),
              if ((recipe.tips ?? '').trim().isNotEmpty) ...<Widget>[
                const SizedBox(height: 24),
                const _SectionTitle(
                  title: '팁',
                  icon: Icons.tips_and_updates_outlined,
                ),
                const SizedBox(height: 8),
                Text(recipe.tips!),
              ],
              if ((recipe.youtubeUrl ?? '').isNotEmpty) ...<Widget>[
                const SizedBox(height: 24),
                const _SectionTitle(
                  title: 'YouTube',
                  icon: Icons.ondemand_video_outlined,
                ),
                const SizedBox(height: 8),
                OutlinedButton.icon(
                  onPressed: () => _openYoutubeUrl(
                    context,
                    recipe.youtubeUrl!,
                  ),
                  icon: const Icon(Icons.open_in_new),
                  label: const Text('YouTube 열기'),
                ),
                const SizedBox(height: 8),
                SelectableText(
                  recipe.youtubeUrl!,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
              const SizedBox(height: 28),
              _NextActions(
                onGoHome: () => _goHome(context),
                onGoMyRecipes: () => _goMyRecipes(context),
                onGoShoppingReview: () => _goShoppingReview(context),
              ),
            ],
          );
        },
        error: (Object err, StackTrace stack) => Center(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Text('상세 정보를 불러올 수 없습니다.\n$err'),
          ),
        ),
        loading: () => const Center(
          child: CircularProgressIndicator(),
        ),
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle({
    required this.title,
    required this.icon,
  });

  final String title;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: <Widget>[
        Icon(icon, size: 20),
        const SizedBox(width: 8),
        Text(
          title,
          style: Theme.of(context).textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w700,
              ),
        ),
      ],
    );
  }
}

class _NextActions extends StatelessWidget {
  const _NextActions({
    required this.onGoHome,
    required this.onGoMyRecipes,
    required this.onGoShoppingReview,
  });

  final VoidCallback onGoHome;
  final VoidCallback onGoMyRecipes;
  final VoidCallback onGoShoppingReview;

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 0,
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Text(
              '다음 작업',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
            ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: onGoHome,
              icon: const Icon(Icons.home_outlined),
              label: const Text('홈으로 이동'),
            ),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: onGoMyRecipes,
              icon: const Icon(Icons.menu_book_outlined),
              label: const Text('내 레시피 목록'),
            ),
            const SizedBox(height: 8),
            FilledButton.icon(
              onPressed: onGoShoppingReview,
              icon: const Icon(Icons.shopping_cart_outlined),
              label: const Text('장보기 목록 만들기'),
            ),
          ],
        ),
      ),
    );
  }
}
