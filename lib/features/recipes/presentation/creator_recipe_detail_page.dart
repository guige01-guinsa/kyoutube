import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';
import 'widgets/unified_recipe_detail_layout.dart';
import '../application/recipe_providers.dart';
import '../application/unified_recipe_providers.dart';
import '../domain/recipe.dart';
import 'create_creator_recipe_page.dart';
import 'recipe_enrichment_page.dart';

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
    ref.invalidate(myUnifiedRecipesProvider);

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
        builder: (_) => CreateCreatorRecipePage(
          initialRecipe: recipe,
          editRecipeId: recipe.id,
        ),
      ),
    );

    if (updated == true) {
      ref.invalidate(creatorRecipeByIdProvider(recipeId));
      ref.invalidate(creatorRecipesProvider);
      ref.invalidate(myUnifiedRecipesProvider);
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

    return recipeAsync.when(
      data: (Recipe? recipe) {
        if (recipe == null) {
          return Scaffold(
            appBar: AppBar(
              title: const Text('레시피 상세'),
            ),
            body: const Center(
              child: Text('레시피를 찾을 수 없습니다.'),
            ),
          );
        }

        return UnifiedRecipeDetailLayout(
          recipe: recipe,
          appBarTitle: '레시피 상세',
          appBarActions: <Widget>[
            IconButton(
              onPressed: () => _edit(context, ref, recipe),
              icon: const Icon(Icons.edit_outlined),
              tooltip: '수정',
            ),
            IconButton(
              onPressed: () => _delete(context, ref, recipe),
              icon: const Icon(Icons.delete_outline),
              tooltip: '삭제',
            ),
          ],
          primaryActions: <Widget>[
            OutlinedButton.icon(
              onPressed: () async {
                final createdRecipeId =
                    await Navigator.of(context).push<Object?>(
                  MaterialPageRoute<Object?>(
                    builder: (_) => RecipeEnrichmentPage(recipe: recipe),
                  ),
                );

                if (createdRecipeId is String &&
                    createdRecipeId.trim().isNotEmpty &&
                    context.mounted) {
                  ref.invalidate(creatorRecipesProvider);
                  ref.invalidate(myUnifiedRecipesProvider);

                  context.go(
                    '/creator/',
                  );
                }
              },
              icon: const Icon(Icons.auto_awesome),
              label: const Text('AI로 레시피 보강'),
            ),
            FilledButton.icon(
              onPressed: () => _goShoppingReview(context),
              icon: const Icon(Icons.shopping_cart_outlined),
              label: const Text('장보기 준비'),
            ),
          ],
          extraSections: <Widget>[
            if ((recipe.tips ?? '').trim().isNotEmpty) ...<Widget>[
              const _CreatorExtraSectionTitle(
                title: '팁',
                icon: Icons.tips_and_updates_outlined,
              ),
              const SizedBox(height: 8),
              Text(recipe.tips!),
              const SizedBox(height: 24),
            ],
            if ((recipe.youtubeUrl ?? '').trim().isNotEmpty) ...<Widget>[
              const _CreatorExtraSectionTitle(
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
          ],
          footer: Card(
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
                    onPressed: () => _goHome(context),
                    icon: const Icon(Icons.home_outlined),
                    label: const Text('홈으로 이동'),
                  ),
                  const SizedBox(height: 8),
                  OutlinedButton.icon(
                    onPressed: () => _goMyRecipes(context),
                    icon: const Icon(Icons.menu_book_outlined),
                    label: const Text('내 레시피 관리'),
                  ),
                ],
              ),
            ),
          ),
        );
      },
      error: (Object err, StackTrace _) {
        return Scaffold(
          appBar: AppBar(
            title: const Text('레시피 상세'),
          ),
          body: Center(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Text(
                '상세 정보를 불러오지 못했습니다.\n$err',
                textAlign: TextAlign.center,
              ),
            ),
          ),
        );
      },
      loading: () => Scaffold(
        appBar: AppBar(
          title: const Text('레시피 상세'),
        ),
        body: const Center(
          child: CircularProgressIndicator(),
        ),
      ),
    );
  }
}

class _CreatorExtraSectionTitle extends StatelessWidget {
  const _CreatorExtraSectionTitle({
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
