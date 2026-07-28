import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../ai/application/ai_service.dart';
import '../../kitchen/application/kitchen_providers.dart';
import '../application/recipe_capability_evaluator.dart';
import '../application/recipe_providers.dart';
import '../data/local_youtube_metadata_override_service.dart';
import '../domain/recipe.dart';
import '../domain/youtube_metadata.dart';
import 'create_creator_recipe_page.dart';
import 'youtube_link_card.dart';

bool _isLoggedInSafely() {
  try {
    return Supabase.instance.client.auth.currentSession != null;
  } catch (_) {
    return false;
  }
}

class _CookFeedbackDraft {
  const _CookFeedbackDraft({
    this.rating,
    this.liked,
    this.note,
  });

  final int? rating;
  final bool? liked;
  final String? note;
}

class CreatorRecipeDetailPage extends ConsumerWidget {
  const CreatorRecipeDetailPage({
    super.key,
    required this.recipeId,
  });

  final String recipeId;

  String _cookFeedbackKey(String recipeId) =>
      'creator.recipe.cook.feedback.$recipeId';

  Future<void> _saveCookFeedbackDraft(
    String recipeId,
    _CookFeedbackDraft draft,
  ) async {
    final prefs = await SharedPreferences.getInstance();
    if (draft.rating != null) {
      await prefs.setInt('${_cookFeedbackKey(recipeId)}.rating', draft.rating!);
    } else {
      await prefs.remove('${_cookFeedbackKey(recipeId)}.rating');
    }
    if (draft.liked != null) {
      await prefs.setBool('${_cookFeedbackKey(recipeId)}.liked', draft.liked!);
    } else {
      await prefs.remove('${_cookFeedbackKey(recipeId)}.liked');
    }
    final note = (draft.note ?? '').trim();
    if (note.isNotEmpty) {
      await prefs.setString('${_cookFeedbackKey(recipeId)}.note', note);
    } else {
      await prefs.remove('${_cookFeedbackKey(recipeId)}.note');
    }
  }

  Future<_CookFeedbackDraft> _loadCookFeedbackDraft(String recipeId) async {
    final prefs = await SharedPreferences.getInstance();
    return _CookFeedbackDraft(
      rating: prefs.getInt('${_cookFeedbackKey(recipeId)}.rating'),
      liked: prefs.getBool('${_cookFeedbackKey(recipeId)}.liked'),
      note: prefs.getString('${_cookFeedbackKey(recipeId)}.note'),
    );
  }

  Future<_CookFeedbackDraft?> _openFeedbackDialog(
    BuildContext context,
    _CookFeedbackDraft initial,
  ) async {
    int? rating = initial.rating;
    bool? liked = initial.liked;
    final noteController = TextEditingController(text: initial.note ?? '');

    return showDialog<_CookFeedbackDraft>(
      context: context,
      builder: (BuildContext context) {
        return StatefulBuilder(
          builder: (BuildContext context, StateSetter setDialogState) {
            return AlertDialog(
              title: const Text('조리 완료 피드백'),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    DropdownButtonFormField<int>(
                      initialValue: rating,
                      decoration: const InputDecoration(
                        labelText: '평점(선택)',
                        border: OutlineInputBorder(),
                      ),
                      items: const <DropdownMenuItem<int>>[
                        DropdownMenuItem<int>(value: 1, child: Text('1점')),
                        DropdownMenuItem<int>(value: 2, child: Text('2점')),
                        DropdownMenuItem<int>(value: 3, child: Text('3점')),
                        DropdownMenuItem<int>(value: 4, child: Text('4점')),
                        DropdownMenuItem<int>(value: 5, child: Text('5점')),
                      ],
                      onChanged: (int? value) {
                        setDialogState(() {
                          rating = value;
                        });
                      },
                    ),
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 8,
                      children: <Widget>[
                        ChoiceChip(
                          label: const Text('좋아요'),
                          selected: liked == true,
                          onSelected: (_) {
                            setDialogState(() {
                              liked = true;
                            });
                          },
                        ),
                        ChoiceChip(
                          label: const Text('별로예요'),
                          selected: liked == false,
                          onSelected: (_) {
                            setDialogState(() {
                              liked = false;
                            });
                          },
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: noteController,
                      minLines: 1,
                      maxLines: 3,
                      decoration: const InputDecoration(
                        labelText: '한 줄 메모(선택)',
                        border: OutlineInputBorder(),
                      ),
                    ),
                  ],
                ),
              ),
              actions: <Widget>[
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('취소'),
                ),
                FilledButton(
                  onPressed: () {
                    Navigator.of(context).pop(
                      _CookFeedbackDraft(
                        rating: rating,
                        liked: liked,
                        note: noteController.text.trim(),
                      ),
                    );
                  },
                  child: const Text('피드백 저장'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Future<void> _startQuickCook(BuildContext context, Recipe recipe) async {
    await context.push('/quick-cook/${recipe.id}?source=creator');
  }

  Future<void> _generateAiSummary(
    BuildContext context,
    WidgetRef ref,
    Recipe recipe,
  ) async {
    final aiService = AiService();
    final sourceText = <String>[
      if ((recipe.summary ?? '').trim().isNotEmpty) recipe.summary!.trim(),
      ...recipe.ingredients,
      ...recipe.steps,
    ].join('\n');

    final result = await aiService.summarizeRecipe(
      sourceText,
      title: recipe.title,
      ingredients: recipe.ingredients,
      steps: recipe.steps,
    );

    final summary = result.summary.trim();
    if (summary.isEmpty) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('생성된 요약이 없습니다. 잠시 후 다시 시도해 주세요.')),
        );
      }
      return;
    }

    final repository = ref.read(recipeRepositoryProvider);
    await repository.updateCreatorRecipe(
      id: recipe.id,
      title: recipe.title,
      summary: summary,
      ingredients: recipe.ingredients,
      steps: recipe.steps,
      tips: recipe.tips,
      imagePath: recipe.imageUrl,
      youtubeUrl: recipe.youtubeUrl,
    );

    ref.invalidate(creatorRecipeByIdProvider(recipe.id));
    ref.invalidate(creatorRecipesProvider(''));

    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            result.degraded
                ? 'AI 요약을 생성했습니다. (보조 초안)'
                : 'AI 요약을 생성했습니다.',
          ),
        ),
      );
    }
  }

  Future<void> _createShoppingList(
    BuildContext context,
    WidgetRef ref,
    Recipe recipe,
  ) async {
    if (recipe.ingredients.isEmpty) {
      if (!context.mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('재료 정보가 없어 장보기 목록을 만들 수 없습니다.')),
      );
      return;
    }

    try {
      final repository = ref.read(recipeRepositoryProvider);
      final result = await repository.createKitchenShoppingFromRecipe(
        recipeType: 'creator',
        recipe: recipe,
      );
      ref.invalidate(kitchenSummaryProvider);
      ref.invalidate(kitchenShoppingListsProvider(kitchenDefaultShoppingListsQuery));

      if (!context.mounted) {
        return;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            result.reopenedFromCompleted
                ? '완료된 장보기를 다시 열었습니다. 남은 항목 ${result.missingCount}개'
                : result.resetFromFullyChecked
                    ? '이전 장보기를 다시 시작합니다. 체크를 초기화했습니다.'
                    : result.noMissingItems
                        ? '이미 보유 중인 재료라 장보기 항목이 없습니다.'
                        : result.reusedActiveList
                            ? '기존 장보기 리스트를 이어서 사용합니다. 남은 항목 ${result.missingCount}개'
                            : '장보기 리스트를 만들었습니다. 항목 ${result.missingCount}개',
          ),
        ),
      );
      context.push('/kitchen');
    } catch (error) {
      if (!context.mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('장보기 목록 생성에 실패했습니다.\n$error')),
      );
    }
  }

  Future<void> _captureCookFeedback(BuildContext context, Recipe recipe) async {
    final initial = await _loadCookFeedbackDraft(recipe.id);
    if (!context.mounted) {
      return;
    }
    final updated = await _openFeedbackDialog(context, initial);
    if (updated == null) {
      return;
    }
    await _saveCookFeedbackDraft(recipe.id, updated);
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('조리 완료 피드백을 임시 저장했습니다.')),
      );
    }
  }

  Future<void> _recordCookCompletion(
    BuildContext context,
    WidgetRef ref,
    Recipe recipe,
  ) async {
    var draft = await _loadCookFeedbackDraft(recipe.id);
    if (!context.mounted) {
      return;
    }
    if (draft.rating == null && draft.liked == null && (draft.note ?? '').trim().isEmpty) {
      final captured = await _openFeedbackDialog(context, draft);
      if (captured == null) {
        return;
      }
      draft = captured;
      await _saveCookFeedbackDraft(recipe.id, captured);
    }

    await ref.read(kitchenApiProvider).completeCook(
          recipeType: 'creator',
          recipeId: recipe.id,
          recipeTitle: recipe.title,
          rating: draft.rating,
          liked: draft.liked,
          note: draft.note,
        );

    ref.invalidate(kitchenCookSessionsProvider);

    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('조리 완료 기록을 저장했습니다.')),
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
          content: Text(
            '"${recipe.title}" 레시피를 삭제하시겠습니까?\n\n삭제 후에는 복구할 수 없습니다.',
          ),
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

    try {
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

      ref.invalidate(creatorRecipesProvider(''));

      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('레시피를 삭제했습니다.')),
        );
        context.go('/creator');
      }
    } catch (error) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('삭제에 실패했습니다: $error')),
        );
      }
    }
  }

  Future<void> _editYoutubeMetadata(
    BuildContext context,
    WidgetRef ref,
    Recipe recipe,
    RecipeYoutubeMetadata? metadata,
    CreatorYoutubeMetadataOverride? override,
  ) async {
    final displayTitleController = TextEditingController(
      text: override?.displayTitle ?? metadata?.title ?? '',
    );
    final noteController = TextEditingController(
      text: override?.note ?? '',
    );

    final saved = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('YouTube 메타데이터 편집'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                TextFormField(
                  controller: displayTitleController,
                  decoration: const InputDecoration(
                    labelText: '표시 제목',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: noteController,
                  maxLines: 4,
                  decoration: const InputDecoration(
                    labelText: '메모',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    '원본 YouTube 링크는 레시피의 핵심 데이터로 유지됩니다.',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ),
              ],
            ),
          ),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('취소'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('저장'),
            ),
          ],
        );
      },
    );

    if (saved != true) {
      return;
    }

    final service = ref.read(localYoutubeMetadataOverrideServiceProvider);
    await service.saveForRecipe(
      recipeId: recipe.id,
      displayTitle: displayTitleController.text,
      note: noteController.text,
    );

    ref.invalidate(creatorYoutubeMetadataOverrideProvider(recipe.id));

    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('YouTube 메타데이터를 저장했습니다.')),
      );
    }
  }

  Future<void> _resetYoutubeMetadata(
    BuildContext context,
    WidgetRef ref,
    Recipe recipe,
  ) async {
    final service = ref.read(localYoutubeMetadataOverrideServiceProvider);
    await service.clearForRecipe(recipe.id);
    ref.invalidate(creatorYoutubeMetadataOverrideProvider(recipe.id));

    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('YouTube 메타데이터를 초기화했습니다.')),
      );
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final recipeAsync = ref.watch(creatorRecipeByIdProvider(recipeId));
    final youtubeMetadataAsync = ref.watch(creatorRecipeYoutubeMetadataProvider(recipeId));
    final youtubeOverrideAsync = ref.watch(creatorYoutubeMetadataOverrideProvider(recipeId));

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
                    ref.invalidate(creatorRecipesProvider(''));
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('레시피 수정 내용을 저장했습니다.')),
                      );
                    }
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

          final youtubeMetadata = youtubeMetadataAsync.asData?.value;
          final youtubeOverride = youtubeOverrideAsync.asData?.value;
          final isLoggedIn = _isLoggedInSafely();
          final capability = RecipeCapabilityEvaluator.evaluateCreatorDetail(
            recipe: recipe,
            isLoggedIn: isLoggedIn,
          );

          Widget buildActionButton({
            required String label,
            required IconData icon,
            required RecipeActionCapability action,
            required Future<void> Function() onPressed,
          }) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: action.enabled ? () => unawaited(onPressed()) : null,
                    icon: Icon(icon),
                    label: Text(label),
                  ),
                ),
                if (!action.enabled && (action.reason ?? '').trim().isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 6, left: 2, right: 2),
                    child: Text(
                      action.reason!,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ),
              ],
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
              const SizedBox(height: 12),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        capability.stateLabel,
                        style: Theme.of(context).textTheme.titleSmall?.copyWith(
                              fontWeight: FontWeight.w700,
                            ),
                      ),
                      const SizedBox(height: 4),
                      Text(capability.stateMessage),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 10),
              buildActionButton(
                label: '바로 요리 시작',
                icon: Icons.restaurant_menu_outlined,
                action: capability.quickCook,
                onPressed: () => _startQuickCook(context, recipe),
              ),
              const SizedBox(height: 8),
              buildActionButton(
                label: 'AI 요약 생성',
                icon: Icons.auto_awesome_outlined,
                action: capability.aiSummary,
                onPressed: () => _generateAiSummary(context, ref, recipe),
              ),
              const SizedBox(height: 8),
              buildActionButton(
                label: '장보기 리스트 만들기',
                icon: Icons.shopping_cart_checkout_outlined,
                action: capability.shoppingList,
                onPressed: () => _createShoppingList(context, ref, recipe),
              ),
              const SizedBox(height: 8),
              buildActionButton(
                label: '조리 완료 피드백',
                icon: Icons.thumb_up_alt_outlined,
                action: capability.cookFeedback,
                onPressed: () => _captureCookFeedback(context, recipe),
              ),
              const SizedBox(height: 8),
              buildActionButton(
                label: '조리 완료 기록',
                icon: Icons.task_alt_outlined,
                action: capability.cookRecord,
                onPressed: () => _recordCookCompletion(context, ref, recipe),
              ),
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
              if ((recipe.tips ?? '').trim().isNotEmpty) ...<Widget>[
                const SizedBox(height: 20),
                Text('팁', style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 8),
                Text(recipe.tips!),
              ],
              if ((recipe.youtubeUrl ?? '').trim().isNotEmpty) ...<Widget>[
                const SizedBox(height: 20),
                YouTubeLinkCard(
                  youtubeUrl: recipe.youtubeUrl!,
                  metadata: youtubeMetadata,
                  displayTitle: youtubeOverride?.displayTitle,
                  note: youtubeOverride?.note,
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: <Widget>[
                    FilledButton.tonalIcon(
                      onPressed: () => _editYoutubeMetadata(
                        context,
                        ref,
                        recipe,
                        youtubeMetadata,
                        youtubeOverride,
                      ),
                      icon: const Icon(Icons.edit_outlined),
                      label: const Text('메타데이터 편집'),
                    ),
                    OutlinedButton.icon(
                      onPressed: youtubeOverride == null
                          ? null
                          : () => _resetYoutubeMetadata(context, ref, recipe),
                      icon: const Icon(Icons.restart_alt),
                      label: const Text('초기화'),
                    ),
                  ],
                ),
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
