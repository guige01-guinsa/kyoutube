import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../application/recipe_providers.dart';
import '../domain/recipe.dart';

class RecipeDetailPage extends ConsumerWidget {
  const RecipeDetailPage({super.key, required this.recipeId});

  final String recipeId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final recipeAsync = ref.watch(recipeByIdProvider(recipeId));

    return Scaffold(
      appBar: AppBar(title: const Text('Recipe Detail')),
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
            ],
          );
        },
        error: (Object err, StackTrace stack) => Center(
          child: Text('상세를 불러오지 못했습니다.\n$err'),
        ),
        loading: () => const Center(child: CircularProgressIndicator()),
      ),
    );
  }
}
