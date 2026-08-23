import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../ingredient_search/domain/shopping_plan.dart';

import '../../recipes/application/recipe_providers.dart';
import '../../recipes/domain/recipe.dart';
import '../../recipes/domain/recipe_source_reference.dart';
import '../application/kitchen_providers.dart';
import '../application/shopping_persistence_controllers.dart';
import '../domain/shopping_review_drafts.dart';

class ShoppingReviewPage extends ConsumerStatefulWidget {
  const ShoppingReviewPage({
    super.key,
    required this.sourceRecipeReference,
  });

  final String sourceRecipeReference;

  @override
  ConsumerState<ShoppingReviewPage> createState() => _ShoppingReviewPageState();
}

class _ShoppingReviewPageState extends ConsumerState<ShoppingReviewPage> {
  ShoppingReviewDraft? _draft;
  ShoppingReviewDraftController? _draftController;
  Timer? _saveTimer;

  bool _loadingDraft = false;
  bool _submitting = false;
  bool _popping = false;

  String? _error;
  RecipeSourceReference get _source =>
      RecipeSourceReference.parse(widget.sourceRecipeReference);

  @override
  void dispose() {
    _saveTimer?.cancel();
    super.dispose();
  }

  Future<List<String>> _loadAvailableIngredientNames() async {
    try {
      final ingredients =
          await ref.read(kitchenApiProvider).listIngredients(query: '');

      return ingredients
          .map((ingredient) => ingredient.name.trim())
          .where((name) => name.isNotEmpty)
          .toList(growable: false);
    } catch (_) {
      // 보유 재료 조회 실패가 장보기 기능 전체 실패로 이어지면 안 됩니다.
      // 실패 시 전체 재료를 기본 선택 상태로 보여주고 사용자가 직접 제외합니다.
      return const <String>[];
    }
  }

  Future<void> _loadDraft(Recipe recipe) async {
    if (_loadingDraft || _draft != null) {
      return;
    }

    _loadingDraft = true;

    try {
      final ShoppingReviewDraftController controller =
          await ref.read(shoppingReviewDraftControllerProvider.future);

      final availableIngredients = await _loadAvailableIngredientNames();

      final plan = ShoppingPlanBuilder.build(
        recipeIngredients: recipe.ingredients,
        availableIngredients: availableIngredients,
      );

      final ShoppingReviewDraft loadedDraft = await controller.getOrCreate(
        sourceRecipeId: _source.value,
        initialItems: List<ShoppingReviewDraftItem>.generate(
          plan.items.length,
          (int index) => _createInitialDraftItem(
            index,
            plan.items[index],
          ),
        ),
      );

      final ShoppingReviewDraft draft =
          _prefillEmptyIngredientNames(loadedDraft);

      if (draft != loadedDraft) {
        try {
          await controller.save(draft);
        } catch (_) {
          // 이름 자동 채우기 저장 실패는 화면 표시를 막지 않습니다.
        }
      }

      if (!mounted) {
        return;
      }
      setState(() {
        _draftController = controller;
        _draft = draft;
        _loadingDraft = false;
      });
    } catch (_) {
      if (!mounted) {
        return;
      }

      setState(() {
        _loadingDraft = false;
        _error = '재료 검토 초안을 불러올 수 없습니다.';
      });
    }
  }

  ShoppingReviewDraftItem _createInitialDraftItem(
    int index,
    ShoppingPlanItem planItem,
  ) {
    return ShoppingReviewDraftItem(
      localId: 'ingredient-$index',
      ingredientText: planItem.rawIngredientText,
      name: planItem.normalizedName,
      quantityInput: '',
      quantity: null,
      unit: null,
      selected: planItem.selected,
    );
  }

  ShoppingReviewDraft _prefillEmptyIngredientNames(ShoppingReviewDraft draft) {
    var changed = false;

    final List<ShoppingReviewDraftItem> items =
        draft.items.map((ShoppingReviewDraftItem item) {
      if (item.name.trim().isNotEmpty) {
        return item;
      }

      final String guessedName = _guessIngredientName(item.ingredientText);

      if (guessedName.trim().isEmpty) {
        return item;
      }

      changed = true;

      return ShoppingReviewDraftItem(
        localId: item.localId,
        ingredientText: item.ingredientText,
        name: guessedName,
        quantityInput: item.quantityInput,
        quantity: item.quantity,
        unit: item.unit,
        selected: item.selected,
      );
    }).toList(growable: false);

    if (!changed) {
      return draft;
    }

    return ShoppingReviewDraft(
      schemaVersion: draft.schemaVersion,
      draftId: draft.draftId,
      sourceRecipeId: draft.sourceRecipeId,
      createIdempotencyKey: draft.createIdempotencyKey,
      createdAt: draft.createdAt,
      updatedAt: DateTime.now().toUtc(),
      items: List<ShoppingReviewDraftItem>.unmodifiable(items),
    );
  }

  String _guessIngredientName(String rawIngredientText) {
    var value = rawIngredientText.trim();

    if (value.isEmpty) {
      return '';
    }

    value = value.replaceAll(RegExp(r'^[\s\-•·]+'), '');

    value = value.replaceAll(
      RegExp(r'\([^)]*\)'),
      ' ',
    );

    value = value.replaceAll(
      RegExp(
        r'\d+(?:\.\d+)?\s*(kg|g|ml|l|L|개|큰술|작은술|컵|대|쪽|알|장|봉|팩|줌|꼬집|cm)?',
        caseSensitive: false,
      ),
      ' ',
    );

    value = value.replaceAll(RegExp(r'\s+'), ' ').trim();

    return value.isEmpty ? rawIngredientText.trim() : value;
  }

  ShoppingReviewDraft _replaceItems(List<ShoppingReviewDraftItem> items) {
    final ShoppingReviewDraft draft = _draft!;

    return ShoppingReviewDraft(
      schemaVersion: draft.schemaVersion,
      draftId: draft.draftId,
      sourceRecipeId: draft.sourceRecipeId,
      createIdempotencyKey: draft.createIdempotencyKey,
      createdAt: draft.createdAt,
      updatedAt: DateTime.now().toUtc(),
      items: List<ShoppingReviewDraftItem>.unmodifiable(items),
    );
  }

  void _updateItem(int index, ShoppingReviewDraftItem item) {
    final List<ShoppingReviewDraftItem> items =
        List<ShoppingReviewDraftItem>.from(_draft!.items);

    items[index] = item;

    setState(() {
      _draft = _replaceItems(items);
    });

    _scheduleSave();
  }

  void _scheduleSave() {
    _saveTimer?.cancel();

    _saveTimer = Timer(const Duration(milliseconds: 450), () async {
      final ShoppingReviewDraft? draft = _draft;
      final ShoppingReviewDraftController? controller = _draftController;

      if (draft == null || controller == null) {
        return;
      }

      try {
        await controller.save(draft);
      } catch (_) {
        if (mounted) {
          setState(() {
            _error = '초안을 저장하지 못했습니다.';
          });
        }
      }
    });
  }

  Future<void> _saveNow() async {
    _saveTimer?.cancel();

    final ShoppingReviewDraft? draft = _draft;
    final ShoppingReviewDraftController? controller = _draftController;

    if (draft != null && controller != null) {
      await controller.save(draft);
    }
  }

  Future<void> _continueLater() async {
    try {
      await _saveNow();

      if (!mounted) {
        return;
      }

      setState(() {
        _popping = true;
      });

      context.pop();
    } catch (_) {
      if (mounted) {
        setState(() {
          _error = '초안을 저장하지 못했습니다.';
        });
      }
    }
  }

  Future<void> _cancel() async {
    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('검토 취소'),
          content: const Text('저장된 검토 초안을 삭제할까요?'),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('계속 검토'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('삭제'),
            ),
          ],
        );
      },
    );

    if (confirmed != true || !mounted) {
      return;
    }

    try {
      await _draftController?.cancel(_source.value);

      if (!mounted) {
        return;
      }

      setState(() {
        _popping = true;
      });

      context.pop();
    } catch (_) {
      if (mounted) {
        setState(() {
          _error = '초안을 삭제하지 못했습니다.';
        });
      }
    }
  }

  Future<void> _submit(Recipe recipe) async {
    final ShoppingReviewDraft? draft = _draft;

    if (draft == null || _submitting) {
      return;
    }

    try {
      draft.validate(forSubmission: true);
    } on FormatException catch (error) {
      setState(() {
        _error = error.message;
      });
      return;
    }

    final selectedItems =
        draft.items.where((item) => item.selected).toList(growable: false);

    setState(() {
      _submitting = true;
      _error = null;
    });

    try {
      // 초안 저장 실패가 장보기 목록 생성을 막지 않도록 합니다.
      try {
        await _saveNow();
      } catch (_) {
        // 초안 저장 실패는 무시하고 현재 입력값으로 장보기 목록 생성을 진행합니다.
      }

      final result = await ref.read(kitchenApiProvider).createShoppingList(
            sourceRecipeId: draft.sourceRecipeId,
            recipeTitle: recipe.title,
            items: selectedItems,
            idempotencyKey: draft.createIdempotencyKey,
          );

      if (result.idempotencyKey != draft.createIdempotencyKey) {
        throw const FormatException('Invalid shopping list create response');
      }

      try {
        await _draftController?.cancel(_source.value);
      } catch (_) {
        // 장보기 목록 생성 후 초안 삭제 실패는 무시합니다.
      }

      if (!mounted) {
        return;
      }

      ref.invalidate(kitchenShoppingListsProvider);

      context.go('/kitchen?tab=shopping');
    } catch (err) {
      if (!mounted) {
        return;
      }

      setState(() {
        _submitting = false;
        _error = '장보기 목록 생성에 실패했습니다. 입력값을 확인한 뒤 다시 시도해 주세요.\n$err';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final RecipeSourceReference source = _source;

    final AsyncValue<Recipe?> recipeAsync = switch (source.type) {
      'public' => ref.watch(recipeByIdProvider(source.id)),
      'creator' => ref.watch(creatorRecipeByIdProvider(source.id)),
      _ => ref.watch(subscriberRecipeByIdProvider(source.id)),
    };

    return PopScope<void>(
      canPop: _popping,
      onPopInvokedWithResult: (bool didPop, _) {
        if (!didPop && !_popping) {
          unawaited(_continueLater());
        }
      },
      child: Scaffold(
        appBar: AppBar(
          title: const Text('장보기 준비'),
          actions: <Widget>[
            TextButton(
              onPressed: _submitting ? null : _continueLater,
              child: const Text('나중에 계속'),
            ),
            IconButton(
              onPressed: _submitting ? null : _cancel,
              icon: const Icon(Icons.close),
              tooltip: '취소',
            ),
          ],
        ),
        body: recipeAsync.when(
          loading: () => const Center(
            child: CircularProgressIndicator(),
          ),
          error: (_, __) => const Center(
            child: Text('레시피를 불러올 수 없습니다.'),
          ),
          data: (Recipe? recipe) {
            if (recipe == null) {
              return const Center(
                child: Text('레시피를 찾을 수 없습니다.'),
              );
            }

            WidgetsBinding.instance.addPostFrameCallback(
              (_) => _loadDraft(recipe),
            );

            if (_draft == null) {
              return const Center(
                child: CircularProgressIndicator(),
              );
            }

            return _buildForm(context, recipe);
          },
        ),
      ),
    );
  }

  Widget _buildForm(BuildContext context, Recipe recipe) {
    final ShoppingReviewDraft draft = _draft!;
    final bool canSubmit = !_submitting && _isValid(draft);

    return SafeArea(
      child: Column(
        children: <Widget>[
          if (_error != null)
            MaterialBanner(
              content: Text(_error!),
              actions: <Widget>[
                TextButton(
                  onPressed: () {
                    setState(() {
                      _error = null;
                    });
                  },
                  child: const Text('닫기'),
                ),
              ],
            ),
          const Padding(
            padding: EdgeInsets.all(16),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text('원문 재료를 확인하고 이름·수량·단위를 입력하세요.'),
            ),
          ),
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              itemCount: draft.items.length,
              itemBuilder: (BuildContext context, int index) {
                return _itemTile(index, draft.items[index]);
              },
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: canSubmit ? () => _submit(recipe) : null,
                icon: _submitting
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.playlist_add),
                label: const Text('장보기 목록 만들기'),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _itemTile(
    int index,
    ShoppingReviewDraftItem item,
  ) {
    return Card(
      child: CheckboxListTile(
        value: item.selected,
        controlAffinity: ListTileControlAffinity.leading,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 12,
          vertical: 4,
        ),
        title: Text(
          item.ingredientText,
          semanticsLabel: '레시피 재료 ${item.ingredientText}',
        ),
        subtitle: Text(
          item.selected ? '장보기 목록에 포함됨' : '보유 중이거나 장보기에서 제외됨',
        ),
        onChanged: _submitting
            ? null
            : (bool? selected) {
                _updateItem(
                  index,
                  ShoppingReviewDraftItem(
                    localId: item.localId,
                    ingredientText: item.ingredientText,
                    name: item.name,
                    quantityInput: item.quantityInput,
                    quantity: item.quantity,
                    unit: item.unit,
                    selected: selected ?? false,
                  ),
                );
              },
      ),
    );
  }

  bool _isValid(ShoppingReviewDraft draft) {
    try {
      draft.validate(forSubmission: true);
      return true;
    } catch (_) {
      return false;
    }
  }
}
