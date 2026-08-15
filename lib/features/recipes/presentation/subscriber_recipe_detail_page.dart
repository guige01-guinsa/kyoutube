import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'widgets/unified_recipe_detail_layout.dart';
import '../application/recipe_providers.dart';
import '../domain/recipe.dart';

class SubscriberRecipeDetailPage extends ConsumerStatefulWidget {
  const SubscriberRecipeDetailPage({super.key, required this.recipeId});

  final String recipeId;

  @override
  ConsumerState<SubscriberRecipeDetailPage> createState() =>
      _SubscriberRecipeDetailPageState();
}

class _SubscriberRecipeDetailPageState
    extends ConsumerState<SubscriberRecipeDetailPage> {
  final TextEditingController _notesController = TextEditingController();
  bool _isSaving = false;

  Future<void> _deleteRecipe(Recipe recipe) async {
    final repository = ref.read(recipeRepositoryProvider);
    final container = ProviderScope.containerOf(context, listen: false);
    final messenger = ScaffoldMessenger.of(context);

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('개인 레시피 삭제'),
          content: const Text('이 개인 레시피를 삭제하시겠습니까?'),
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
      await repository.deleteSubscriberRecipe(recipe.id);
      ref.invalidate(subscriberRecipesProvider);

      if (!mounted) {
        return;
      }

      messenger.showSnackBar(
        SnackBar(
          content: const Text('개인 레시피를 삭제했습니다.'),
          action: SnackBarAction(
            label: '되돌리기',
            onPressed: () async {
              try {
                await repository.createSubscriberRecipeFromPublic(
                  source: recipe,
                  notes: recipe.notes,
                );
                container.invalidate(subscriberRecipesProvider);
                messenger.showSnackBar(
                  const SnackBar(content: Text('삭제를 되돌렸습니다.')),
                );
              } catch (undoErr) {
                messenger.showSnackBar(
                  SnackBar(
                    content: Text('삭제 되돌리기에 실패했습니다.\n$undoErr'),
                  ),
                );
              }
            },
          ),
          duration: const Duration(seconds: 8),
        ),
      );

      Navigator.of(context).pop(true);
    } catch (err) {
      if (!mounted) {
        return;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('개인 레시피 삭제에 실패했습니다.\n$err')),
      );
    }
  }

  @override
  void dispose() {
    _notesController.dispose();
    super.dispose();
  }

  Future<void> _saveNotes() async {
    setState(() {
      _isSaving = true;
    });

    try {
      final repository = ref.read(recipeRepositoryProvider);
      await repository.updateSubscriberRecipeNotes(
        id: widget.recipeId,
        notes: _notesController.text,
      );
      ref.invalidate(subscriberRecipeByIdProvider(widget.recipeId));
      ref.invalidate(subscriberRecipesProvider);

      if (!mounted) {
        return;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('메모를 저장했습니다.')),
      );
    } catch (err) {
      if (!mounted) {
        return;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('메모 저장에 실패했습니다.\n$err')),
      );
    } finally {
      if (mounted) {
        setState(() {
          _isSaving = false;
        });
      }
    }
  }

  void _goShoppingReview(BuildContext context) {
    final source = Uri.encodeQueryComponent('user:${widget.recipeId}');
    context.push('/shopping-review?source=$source');
  }

  @override
  Widget build(BuildContext context) {
    final recipeAsync = ref.watch(
      subscriberRecipeByIdProvider(widget.recipeId),
    );

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

        if (!_isSaving && _notesController.text != (recipe.notes ?? '')) {
          _notesController.text = recipe.notes ?? '';
        }

        return UnifiedRecipeDetailLayout(
          recipe: recipe,
          appBarTitle: '레시피 상세',
          appBarActions: <Widget>[
            IconButton(
              onPressed: () => _deleteRecipe(recipe),
              icon: const Icon(Icons.delete_outline),
              tooltip: '삭제',
            ),
          ],
          primaryActions: <Widget>[
            FilledButton.icon(
              onPressed: () => _goShoppingReview(context),
              icon: const Icon(Icons.shopping_cart_outlined),
              label: const Text('장보기 준비'),
            ),
          ],
          extraSections: <Widget>[
            const _SubscriberExtraSectionTitle(
              title: '개인 메모',
              icon: Icons.note_alt_outlined,
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _notesController,
              maxLines: 5,
              decoration: const InputDecoration(
                hintText: '조리 중 수정 사항이나 메모를 기록해 보세요.',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            FilledButton(
              onPressed: _isSaving ? null : _saveNotes,
              child: Text(_isSaving ? '저장 중...' : '메모 저장'),
            ),
          ],
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
                '개인 레시피를 불러오지 못했습니다.\n$err',
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

class _SubscriberExtraSectionTitle extends StatelessWidget {
  const _SubscriberExtraSectionTitle({
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
