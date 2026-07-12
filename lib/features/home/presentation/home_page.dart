import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../auth/application/auth_providers.dart';
import '../../recipes/application/recipe_providers.dart';
import '../../recipes/domain/recipe.dart';
import '../../recipes/presentation/recipe_thumbnail.dart';

class HomePage extends ConsumerWidget {
  const HomePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final recipesAsync = ref.watch(publicRecipesProvider);
    final authUserAsync = ref.watch(authUserProvider);
    final currentUser = authUserAsync.valueOrNull;

    return Scaffold(
      appBar: AppBar(
        title: const Text('AI Cooking Platform'),
        actions: <Widget>[
          IconButton(
            onPressed: () {
              if (currentUser == null) {
                context.push('/login');
                return;
              }
              context.push('/creator');
            },
            icon: const Icon(Icons.menu_book_outlined),
            tooltip: '내 레시피',
          ),
          IconButton(
            onPressed: () async {
              if (currentUser == null) {
                context.push('/login');
                return;
              }
              await Supabase.instance.client.auth.signOut();
            },
            icon: Icon(currentUser == null ? Icons.login : Icons.logout),
            tooltip: currentUser == null ? '로그인' : '로그아웃',
          ),
        ],
      ),
      body: recipesAsync.when(
        data: (List<Recipe> recipes) {
          if (recipes.isEmpty) {
            return const Center(child: Text('표시할 레시피가 없습니다.'));
          }

          return RefreshIndicator(
            onRefresh: () async {
              ref.invalidate(publicRecipesProvider);
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
                  trailing: Text('${recipe.ingredients.length}개 재료'),
                  onTap: () {
                    context.push('/recipes/${recipe.id}');
                  },
                );
              },
            ),
          );
        },
        error: (Object err, StackTrace stack) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Text(
                '레시피를 불러오지 못했습니다.\n$err',
                textAlign: TextAlign.center,
              ),
            ),
          );
        },
        loading: () => const Center(child: CircularProgressIndicator()),
      ),
    );
  }
}
