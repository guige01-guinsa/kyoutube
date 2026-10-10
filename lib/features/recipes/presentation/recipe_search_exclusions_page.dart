import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:k_youtube/core/localization/localized_text.dart';

import '../../../core/widgets/centered_state_view.dart';
import '../application/recipe_providers.dart';
import '../application/unified_recipe_providers.dart';
import '../domain/recipe_search_exclusion.dart';
import 'create_creator_recipe_page.dart';
import 'recipe_thumbnail.dart';

class RecipeSearchExclusionsPage extends ConsumerWidget {
  const RecipeSearchExclusionsPage({super.key, this.showAppBar = true});

  final bool showAppBar;

  Future<void> _edit(BuildContext context, WidgetRef ref,
      RecipeSearchExclusion exclusion) async {
    final createdId = await Navigator.of(context).push<Object?>(
      MaterialPageRoute<Object?>(
        builder: (_) => CreateCreatorRecipePage(
          initialRecipe: exclusion.toEditableDraft(),
          returnCreatedRecipeId: true,
        ),
      ),
    );
    if (createdId is! String || createdId.trim().isEmpty) return;
    try {
      await ref
          .read(recipeRepositoryProvider)
          .resolveRecipeSearchExclusion(exclusion.id);
      ref.invalidate(recipeSearchExclusionsProvider);
      ref.invalidate(myUnifiedRecipesProvider);
    } catch (_) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: LocalizedText(
              '레시피는 저장했지만 검색 제외 목록을 갱신하지 못했습니다.',
            ),
          ),
        );
      }
    }
  }

  Future<void> _restore(BuildContext context, WidgetRef ref,
      RecipeSearchExclusion exclusion) async {
    try {
      await ref
          .read(recipeRepositoryProvider)
          .deleteRecipeSearchExclusion(exclusion.id);
      ref.invalidate(recipeSearchExclusionsProvider);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: LocalizedText('이 레시피를 검색에 다시 표시합니다.')),
        );
      }
    } catch (_) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: LocalizedText('검색 제외 설정을 변경하지 못했습니다.')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final exclusionsAsync = ref.watch(recipeSearchExclusionsProvider);
    final body = exclusionsAsync.when(
      data: (items) {
        if (items.isEmpty) {
          return const CenteredStateView(
            icon: Icons.visibility_off_outlined,
            title: '검색 제외 레시피가 없습니다',
            message: '정보가 부족한 AI 초안과 직접 숨긴 검색 결과가 여기에 표시됩니다.',
          );
        }
        return RefreshIndicator(
          onRefresh: () async {
            ref.invalidate(recipeSearchExclusionsProvider);
            await ref.read(recipeSearchExclusionsProvider.future);
          },
          child: ListView.separated(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
            itemCount: items.length,
            separatorBuilder: (_, __) => const SizedBox(height: 12),
            itemBuilder: (context, index) {
              final exclusion = items[index];
              return Card(
                clipBehavior: Clip.antiAlias,
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          RecipeThumbnail(
                            imageUrl: exclusion.imageUrl,
                            width: 76,
                            height: 82,
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: <Widget>[
                                LocalizedText(
                                  exclusion.title,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style:
                                      Theme.of(context).textTheme.titleMedium,
                                ),
                                const SizedBox(height: 6),
                                LocalizedText(_reasonLabel(exclusion)),
                                const SizedBox(height: 4),
                                LocalizedText(
                                  exclusion.sourceType == 'youtube'
                                      ? 'YouTube 영상'
                                      : '공개 레시피',
                                  style: Theme.of(context).textTheme.bodySmall,
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: <Widget>[
                          TextButton(
                            onPressed: () => _restore(context, ref, exclusion),
                            child: const LocalizedText('검색에 다시 표시'),
                          ),
                          const SizedBox(width: 8),
                          FilledButton.icon(
                            onPressed: () => _edit(context, ref, exclusion),
                            icon: const Icon(Icons.edit_outlined),
                            label: const LocalizedText('직접 편집'),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        );
      },
      error: (_, __) => CenteredStateView(
        icon: Icons.cloud_off_outlined,
        title: '검색 제외 레시피를 불러오지 못했습니다',
        message: '잠시 후 다시 시도해 주세요.',
        actionLabel: context.tr('다시 시도'),
        onAction: () => ref.invalidate(recipeSearchExclusionsProvider),
      ),
      loading: () => const Center(child: CircularProgressIndicator()),
    );

    if (!showAppBar) return body;
    return Scaffold(
      appBar: AppBar(title: const LocalizedText('검색 제외 레시피')),
      body: body,
    );
  }

  String _reasonLabel(RecipeSearchExclusion exclusion) {
    final reasons = exclusion.reasonCodes;
    if (reasons.contains('missing_steps')) return '조리순서가 부족한 초안';
    if (reasons.contains('missing_ingredient_measure')) {
      return '재료 수량·단위가 부족한 초안';
    }
    if (reasons.contains('incomplete_draft')) return '정보가 부족한 AI 초안';
    return '사용자가 검색에서 제외함';
  }
}
