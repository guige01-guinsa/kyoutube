import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../auth/application/auth_providers.dart';
import '../application/recipe_providers.dart';
import '../domain/recipe.dart';
import 'recipe_thumbnail.dart';

class CreatorRecipesPage extends ConsumerWidget {
  const CreatorRecipesPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final authUserAsync = ref.watch(authUserProvider);
    final currentUser = authUserAsync.valueOrNull;
    final recipesAsync = ref.watch(creatorRecipesProvider);

    if (currentUser == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('내 레시피 관리')),
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              const Text('로그인 후 크리에이터 레시피를 관리할 수 있습니다.'),
              const SizedBox(height: 12),
              FilledButton(
                onPressed: () => context.push('/login'),
                child: const Text('로그인하기'),
              ),
            ],
          ),
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
            return const Center(child: Text('등록한 크리에이터 레시피가 없습니다.'));
          }

          return RefreshIndicator(
            onRefresh: () async {
              ref.invalidate(creatorRecipesProvider);
            },
            child: ListView.separated(
              physics: const AlwaysScrollableScrollPhysics(),
              itemCount: recipes.length,
              separatorBuilder: (_, __) => const Divider(height: 1),
              itemBuilder: (BuildContext context, int index) {
                final recipe = recipes[index];
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
        error: (Object err, StackTrace stack) => Center(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Text(
              '내 레시피를 불러오지 못했습니다.\n$err',
              textAlign: TextAlign.center,
            ),
          ),
        ),
        loading: () => const Center(child: CircularProgressIndicator()),
      ),
    );
  }
}
