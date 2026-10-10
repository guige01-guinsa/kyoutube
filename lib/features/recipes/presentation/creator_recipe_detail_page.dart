import 'package:flutter/material.dart';
import 'package:k_youtube/core/localization/localized_text.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../../core/widgets/centered_state_view.dart';
import 'widgets/unified_recipe_detail_layout.dart';
import 'widgets/recipe_work_actions.dart';
import '../../cooking/presentation/cooking_completion_feedback_card.dart';
import '../application/recipe_providers.dart';
import '../application/unified_recipe_providers.dart';
import '../domain/recipe.dart';
import '../domain/recipe_content_style.dart';
import 'create_creator_recipe_page.dart';
import 'youtube_recipe_enrichment_page.dart';

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
          const SnackBar(content: LocalizedText('유효한 YouTube 링크가 아닙니다.')),
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
        const SnackBar(content: LocalizedText('YouTube 링크를 열 수 없습니다.')),
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
          title: const LocalizedText('레시피 삭제'),
          content: const LocalizedText('이 레시피를 삭제하시겠습니까?'),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const LocalizedText('취소'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const LocalizedText('삭제'),
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
      // 목록에서 상세로 들어온 경우에는 기존 목록을 유지한 채 돌아가야
      // 삭제 후에도 다른 레시피를 바로 선택하거나 새 레시피를 만들 수 있다.
      if (context.canPop()) {
        context.pop(true);
      } else {
        context.go('/my-recipes');
      }
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
    // 목록을 상세 화면 위에 쌓아, 목록의 뒤로가기가 현재 레시피 상세로
    // 자연스럽게 돌아오도록 한다.
    context.push('/my-recipes');
  }

  void _goShoppingReview(BuildContext context, Recipe recipe) {
    if (recipe.ingredients.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: LocalizedText('재료 정보가 없어 장보기 목록을 만들 수 없습니다.'),
        ),
      );
      return;
    }

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
              title: const LocalizedText('레시피 상세'),
            ),
            body: CenteredStateView(
              icon: Icons.search_off,
              title: '레시피를 찾을 수 없습니다',
              message: '삭제되었거나 접근할 수 없는 레시피입니다.',
              actionLabel: context.tr('내 레시피로 이동'),
              onAction: () => context.go('/my-recipes'),
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
              tooltip: context.tr('수정'),
            ),
            IconButton(
              onPressed: () => _delete(context, ref, recipe),
              icon: const Icon(Icons.delete_outline),
              tooltip: context.tr('삭제'),
            ),
            PopupMenuButton<_RecipeNavigationAction>(
              icon: const Icon(Icons.more_vert),
              tooltip: context.tr('이동 메뉴'),
              onSelected: (_RecipeNavigationAction action) {
                switch (action) {
                  case _RecipeNavigationAction.home:
                    _goHome(context);
                  case _RecipeNavigationAction.myRecipes:
                    _goMyRecipes(context);
                }
              },
              itemBuilder: (BuildContext context) =>
                  const <PopupMenuEntry<_RecipeNavigationAction>>[
                PopupMenuItem<_RecipeNavigationAction>(
                  value: _RecipeNavigationAction.home,
                  child: ListTile(
                    leading: Icon(Icons.home_outlined),
                    title: LocalizedText('홈으로 이동'),
                  ),
                ),
                PopupMenuItem<_RecipeNavigationAction>(
                  value: _RecipeNavigationAction.myRecipes,
                  child: ListTile(
                    leading: Icon(Icons.menu_book_outlined),
                    title: LocalizedText('내 레시피 관리'),
                  ),
                ),
              ],
            ),
          ],
          primaryActions: <Widget>[
            SizedBox(
              width: double.infinity,
              child: RecipeWorkActions(
                onChef: () => context.push(
                    Uri(pathSegments: ['', 'chef', recipe.id]).toString()),
                onShopping: () => _goShoppingReview(context, recipe),
              ),
            ),
            if ((recipe.youtubeUrl ?? '').trim().isNotEmpty)
              OutlinedButton.icon(
                onPressed: () async {
                  final createdRecipeId =
                      await Navigator.of(context).push<Object?>(
                    MaterialPageRoute<Object?>(
                      builder: (_) =>
                          YoutubeRecipeEnrichmentPage(recipe: recipe),
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
                label: const LocalizedText('AI로 레시피 보강'),
              ),
          ],
          extraSections: <Widget>[
            if ((recipe.tips ?? '').trim().isNotEmpty) ...<Widget>[
              const _CreatorExtraSectionTitle(
                title: '팁',
                icon: Icons.tips_and_updates_outlined,
              ),
              const SizedBox(height: 8),
              Text.rich(
                buildRecipeStyledTextSpan(
                  context: context,
                  text: recipe.tips!,
                  ranges: decodeRecipeContentStyles(
                        recipe.contentStyles,
                        legacyFieldLengths: <String, int>{
                          'tips': recipe.tips!.length,
                        },
                      )['tips'] ??
                      const <RecipeContentStyleRange>[],
                  baseStyle: Theme.of(context).textTheme.bodyLarge,
                ),
              ),
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
                label: const LocalizedText('YouTube 열기'),
              ),
              const SizedBox(height: 8),
              SelectableText(
                recipe.youtubeUrl!,
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
            const SizedBox(height: 24),
            CookingCompletionFeedbackCard(
              recipeType: 'creator',
              recipeId: recipe.id,
              recipeTitle: recipe.title,
            ),
            const SizedBox(height: 24),
          ],
        );
      },
      error: (Object err, StackTrace _) {
        return Scaffold(
          appBar: AppBar(
            title: const LocalizedText('레시피 상세'),
          ),
          body: Center(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: LocalizedText(
                '상세 정보를 불러오지 못했습니다.\n$err',
                textAlign: TextAlign.center,
              ),
            ),
          ),
        );
      },
      loading: () => Scaffold(
        appBar: AppBar(
          title: const LocalizedText('레시피 상세'),
        ),
        body: const Center(
          child: CircularProgressIndicator(),
        ),
      ),
    );
  }
}

enum _RecipeNavigationAction {
  home,
  myRecipes,
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
        LocalizedText(
          title,
          style: Theme.of(context).textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w700,
              ),
        ),
      ],
    );
  }
}
