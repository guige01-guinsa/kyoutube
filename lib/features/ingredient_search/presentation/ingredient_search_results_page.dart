import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../recipes/application/recipe_providers.dart';
import '../../recipes/domain/recipe.dart';
import '../../recipes/presentation/recipe_thumbnail.dart';

class IngredientSearchResultsPage extends ConsumerStatefulWidget {
  const IngredientSearchResultsPage({
    super.key,
    required this.ingredients,
  });

  final List<String> ingredients;

  @override
  ConsumerState<IngredientSearchResultsPage> createState() =>
      _IngredientSearchResultsPageState();
}

class _IngredientSearchResultsPageState
    extends ConsumerState<IngredientSearchResultsPage> {
  late Future<List<Recipe>> _recipesFuture;

  @override
  void initState() {
    super.initState();
    _recipesFuture = _loadRecipes();
  }

  Future<List<Recipe>> _loadRecipes() async {
    final query = widget.ingredients.join(' ');

    return ref.read(recipeRepositoryProvider).listPublicRecipes(
          search: query,
          useAiSearch: true,
        );
  }

  int _matchCount(Recipe recipe) {
    final recipeIngredientText = recipe.ingredients.join(' ').toLowerCase();

    return widget.ingredients
        .where(
          (ingredient) =>
              recipeIngredientText.contains(ingredient.toLowerCase()),
        )
        .length;
  }

  List<String> _matchedIngredients(Recipe recipe) {
    final recipeIngredientText = recipe.ingredients.join(' ').toLowerCase();

    return widget.ingredients
        .where(
          (ingredient) =>
              recipeIngredientText.contains(ingredient.toLowerCase()),
        )
        .toList(growable: false);
  }

  void _retry() {
    setState(() {
      _recipesFuture = _loadRecipes();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('보유 재료 검색 결과'),
      ),
      body: FutureBuilder<List<Recipe>>(
        future: _recipesFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.waiting &&
              snapshot.hasError) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    const Text(
                      '레시피를 찾지 못했습니다.\n잠시 후 다시 시도해 주세요.',
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 16),
                    FilledButton(
                      onPressed: _retry,
                      child: const Text('다시 시도'),
                    ),
                  ],
                ),
              ),
            );
          }

          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }

          final matches = snapshot.data!
              .map(
                (recipe) => (
                  recipe: recipe,
                  count: _matchCount(recipe),
                  matched: _matchedIngredients(recipe),
                ),
              )
              .where((item) => item.count > 0)
              .toList()
            ..sort((a, b) => b.count.compareTo(a.count));

          return Column(
            children: <Widget>[
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: widget.ingredients
                        .map((ingredient) => Chip(label: Text(ingredient)))
                        .toList(growable: false),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    matches.isEmpty
                        ? '선택 재료와 일치하는 레시피가 없습니다.'
                        : '${matches.length}개의 레시피를 찾았습니다.',
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Expanded(
                child: matches.isEmpty
                    ? const Center(
                        child: Text('다른 재료 조합으로 다시 검색해 보세요.'),
                      )
                    : ListView.separated(
                        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                        itemCount: matches.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 10),
                        itemBuilder: (context, index) {
                          final item = matches[index];
                          final recipe = item.recipe;
                          final missing =
                              widget.ingredients.length - item.count;

                          return Card(
                            child: Padding(
                              padding: const EdgeInsets.all(12),
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: <Widget>[
                                  SizedBox(
                                    width: 88,
                                    height: 88,
                                    child: RecipeThumbnail(
                                      imageUrl: recipe.imageUrl,
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: <Widget>[
                                        Text(
                                          recipe.title,
                                          style: Theme.of(context)
                                              .textTheme
                                              .titleMedium
                                              ?.copyWith(
                                                fontWeight: FontWeight.w700,
                                              ),
                                        ),
                                        const SizedBox(height: 4),
                                        Text(
                                          missing == 0
                                              ? '보유 재료 일치 ${item.count}/${widget.ingredients.length}'
                                              : '보유 재료 일치 ${item.count}/${widget.ingredients.length} · 재료 $missing개 부족',
                                        ),
                                        const SizedBox(height: 6),
                                        Wrap(
                                          spacing: 4,
                                          runSpacing: 4,
                                          children: item.matched
                                              .map(
                                                (ingredient) => Chip(
                                                  visualDensity:
                                                      VisualDensity.compact,
                                                  label: Text('✓ $ingredient'),
                                                ),
                                              )
                                              .toList(growable: false),
                                        ),
                                        const SizedBox(height: 8),
                                        Wrap(
                                          spacing: 8,
                                          children: <Widget>[
                                            TextButton(
                                              onPressed: () => context.push(
                                                '/recipes/${Uri.encodeComponent(recipe.id)}',
                                              ),
                                              child: const Text('레시피 보기'),
                                            ),
                                            OutlinedButton(
                                              onPressed: () {
                                                final source =
                                                    Uri.encodeQueryComponent(
                                                  'public:${recipe.id}',
                                                );

                                                context.push(
                                                  '/shopping-review?source=$source',
                                                );
                                              },
                                              child: const Text('장보기 준비'),
                                            ),
                                          ],
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
              ),
            ],
          );
        },
      ),
    );
  }
}
