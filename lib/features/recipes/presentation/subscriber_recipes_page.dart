import '../../../core/auth/auth_return.dart';
import 'package:flutter/material.dart';
import 'package:k_youtube/core/localization/localized_text.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../auth/application/auth_providers.dart';
import '../../../core/widgets/centered_state_view.dart';
import '../application/recipe_providers.dart';
import '../domain/recipe.dart';

class SubscriberRecipesPage extends ConsumerWidget {
  const SubscriberRecipesPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final authUserAsync = ref.watch(authUserProvider);
    final currentUser = authUserAsync.valueOrNull;
    final recipesAsync = ref.watch(subscriberRecipesProvider);

    if (currentUser == null) {
      return Scaffold(
        appBar: AppBar(title: const LocalizedText('내 요리 노트')),
        body: CenteredStateView(
          icon: Icons.lock_outline,
          title: '로그인이 필요합니다',
          message: '로그인 후 개인 레시피를 관리할 수 있습니다.',
          actionLabel: context.tr('로그인하기'),
          onAction: () => context.push(loginFor(GoRouterState.of(context).uri.toString(), resume: true)),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(title: const LocalizedText('내 요리 노트')),
      body: recipesAsync.when(
        data: (List<Recipe> recipes) {
          if (recipes.isEmpty) {
            return CenteredStateView(
              icon: Icons.menu_book_outlined,
              title: '아직 저장한 개인 레시피가 없습니다',
              message: '공개 레시피 상세에서 "내 레시피로 복사"를 눌러 시작해 보세요.',
              actionLabel: context.tr('공개 레시피 보기'),
              onAction: () => context.push('/'),
            );
          }

          return RefreshIndicator(
            onRefresh: () async {
              ref.invalidate(subscriberRecipesProvider);
            },
            child: ListView.separated(
              physics: const AlwaysScrollableScrollPhysics(),
              itemCount: recipes.length,
              separatorBuilder: (_, __) => const Divider(height: 1),
              itemBuilder: (BuildContext context, int index) {
                final recipe = recipes[index];
                return ListTile(
                  title: LocalizedText(recipe.title),
                  subtitle: LocalizedText(
                    (recipe.notes ?? '').trim().isEmpty
                        ? '메모 없음'
                        : recipe.notes!,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  trailing: LocalizedText('${recipe.steps.length}단계'),
                  onTap: () => context.push('/my-recipes/${recipe.id}'),
                );
              },
            ),
          );
        },
        error: (Object err, StackTrace stack) => CenteredStateView(
          icon: Icons.cloud_off_outlined,
          title: '개인 레시피를 불러오지 못했습니다',
          message: '잠시 후 다시 시도해 주세요.',
          actionLabel: context.tr('다시 시도'),
          onAction: () => ref.invalidate(subscriberRecipesProvider),
        ),
        loading: () => const Center(child: CircularProgressIndicator()),
      ),
    );
  }
}
