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

    final launched = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!launched && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('링크를 열지 못했습니다.')),
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
        // Keep recipe deletion successful even if storage cleanup is best-effort.
      }
    }

    ref.invalidate(creatorRecipesProvider);

    if (context.mounted) {
      context.pop();
    }
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
                onPressed: () async {
                  final updated = await Navigator.of(context).push<bool>(
                    MaterialPageRoute<bool>(
                      builder: (_) =>
                          CreateCreatorRecipePage(initialRecipe: recipe),
                    ),
                  );
                  if (updated == true) {
                    ref.invalidate(creatorRecipeByIdProvider(recipeId));
                    ref.invalidate(creatorRecipesProvider);
                  }
                },
                icon: const Icon(Icons.edit_outlined),
                tooltip: '수정',
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
            return const Center(child: Text('레시피를 찾을 수 없습니다.'));
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
                          child: Center(child: Text('이미지를 불러오지 못했습니다.')),
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
              Text(recipe.summary ?? '요약 정보가 없습니다.'),
              const SizedBox(height: 20),
              Text('재료', style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 8),
              ...recipe.ingredients.map((String item) => Text('- $item')),
              const SizedBox(height: 20),
              Text('조리 순서', style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 8),
              ...recipe.steps.asMap().entries.map(
                    (entry) => Text('${entry.key + 1}. ${entry.value}'),
                  ),
              if ((recipe.youtubeUrl ?? '').isNotEmpty) ...<Widget>[
                const SizedBox(height: 20),
                Text('YouTube', style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 8),
                OutlinedButton.icon(
                  onPressed: () => _openYoutubeUrl(context, recipe.youtubeUrl!),
                  icon: const Icon(Icons.open_in_new),
                  label: const Text('YouTube 열기'),
                ),
                const SizedBox(height: 8),
                SelectableText(recipe.youtubeUrl!),
              ],
            ],
          );
        },
        error: (Object err, StackTrace stack) => Center(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Text('상세를 불러오지 못했습니다.\n$err'),
          ),
        ),
        loading: () => const Center(child: CircularProgressIndicator()),
      ),
    );
  }
}
