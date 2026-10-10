import '../../../core/auth/auth_return.dart';
import '../../auth/application/auth_providers.dart';
import 'package:k_youtube/core/widgets/scout_page.dart';
import '../../guide/presentation/guide_help_button.dart';
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:k_youtube/core/localization/localized_text.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/widgets/centered_state_view.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/format/user_number.dart';
import '../../ingredient_search/domain/shopping_plan.dart';
import '../../ingredient_search/domain/ingredient_matcher.dart';
import '../../recipes/application/recipe_providers.dart';
import '../../recipes/domain/recipe.dart';
import '../../recipes/domain/recipe_source_reference.dart';
import '../application/kitchen_providers.dart';
import '../application/shopping_persistence_controllers.dart';
import '../data/kitchen_api.dart';
import '../domain/shopping_review_drafts.dart';
import '../domain/shopping_units.dart';
import 'shopping_purchase_quantity_dialog.dart';

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
  final _recipeServings = TextEditingController(text: '1');
  final _targetServings = TextEditingController(text: '1');

  bool _loadingDraft = false;
  bool _submitting = false;
  bool _popping = false;

  String? _error;
  bool _needsLogin = false;
  RecipeSourceReference get _source =>
      RecipeSourceReference.parse(widget.sourceRecipeReference);

  @override
  void dispose() {
    _saveTimer?.cancel();
    _recipeServings.dispose();
    _targetServings.dispose();
    super.dispose();
  }

  Future<void> _loadDraft(Recipe recipe) async {
    if (!mounted || _loadingDraft || _draft != null) {
      return;
    }

    _loadingDraft = true;

    try {
      final ShoppingReviewDraftController controller =
          await ref.read(shoppingReviewDraftControllerProvider.future);

      final plan = ShoppingPlanBuilder.build(
        recipeIngredients: recipe.ingredients,
        // Cooking does not track stock consumption. A past inventory record
        // cannot establish what is available now; shoppers exclude it explicitly.
        availableIngredients: const <String>[],
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
      _recipeServings.text = _shoppingNumber(draft.recipeServings);
      _targetServings.text = _shoppingNumber(draft.targetServings);
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
      needsReview: planItem.needsReview,
    );
  }

  ShoppingReviewDraft _prefillEmptyIngredientNames(ShoppingReviewDraft draft) {
    var changed = false;

    final List<ShoppingReviewDraftItem> items =
        draft.items.map((ShoppingReviewDraftItem item) {
      final String existingName = item.name.trim();
      final String guessedName = _guessIngredientName(item.ingredientText);
      final bool isLegacyGeneratedName = RegExp(
        r'(?:큰스푼|작은스푼|티스푼|스푼|숟가락|종이컵|컵|모|줄기|단|개|그램|리터|tsp|tbsp|t)$',
        caseSensitive: false,
      ).hasMatch(existingName);

      // Old automatic drafts could retain a measuring word, such as
      // "다진마늘 스푼". Only replace an empty or clearly generated name;
      // an operator-edited name remains untouched.
      if ((existingName.isNotEmpty && !isLegacyGeneratedName) ||
          guessedName.isEmpty ||
          guessedName == existingName) {
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
        needsReview: item.needsReview,
        purchaseConfirmed: item.purchaseConfirmed,
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
      recipeServings: draft.recipeServings,
      targetServings: draft.targetServings,
    );
  }

  String _shoppingNumber(double value) => value == value.roundToDouble()
      ? value.toInt().toString()
      : value
          .toStringAsFixed(3)
          .replaceFirst(RegExp(r'0+$'), '')
          .replaceFirst(RegExp(r'\.$'), '');

  void _applyServings() {
    final base = parseUserNumber(_recipeServings.text);
    final target = parseUserNumber(_targetServings.text);
    if (base == null ||
        target == null ||
        !isValidShoppingServings(base) ||
        !isValidShoppingServings(target)) {
      setState(() => _error = '레시피 기준 인분과 만들 인분을 0.1~1,000 사이로 입력해 주세요.');
      return;
    }
    try {
      setState(() {
        _draft = rescaleShoppingReviewDraftServings(_draft!,
            recipeServings: base, targetServings: target);
        _error = null;
      });
      _scheduleSave();
    } on FormatException {
      setState(() => _error = '인분에 맞춰 수량을 계산하지 못했습니다. 수량을 직접 확인해 주세요.');
    }
  }

  String _guessIngredientName(String rawIngredientText) {
    return IngredientMatcher.normalize(rawIngredientText);
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
          title: const LocalizedText('검토 취소'),
          content: const LocalizedText('저장된 검토 초안을 삭제할까요?'),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const LocalizedText('계속 검토'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const LocalizedText('삭제'),
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

      context.go(Uri(
        path: '/shopping',
        queryParameters: <String, String>{
          'stage': 'prepare',
          'list': result.listId,
        },
      ).toString());
    } catch (err) {
      if (!mounted) {
        return;
      }

      setState(() {
        _submitting = false;
        _needsLogin = err is KitchenApiException &&
            err.kind == KitchenApiErrorKind.unauthorized;
        _error = switch (err) {
          KitchenApiException(kind: KitchenApiErrorKind.unauthorized) =>
            '로그인이 만료되었습니다. 다시 로그인한 뒤 장보기 목록을 만들어 주세요.',
          KitchenApiException(code: 'shopping_request_rejected') =>
            '서버가 장보기 요청을 처리하지 못했습니다. 다시 시도하거나 고객지원에 문의해 주세요.',
          KitchenApiException(kind: KitchenApiErrorKind.validation) ||
          KitchenApiException(kind: KitchenApiErrorKind.badRequest) =>
            '선택한 재료의 이름·수량·단위를 확인해 주세요. 수량이 없으면 수량과 단위를 함께 비워 둘 수 있습니다.',
          _ => '장보기 목록을 만들지 못했어요. 연결 상태를 확인한 뒤 다시 시도해 주세요.',
        };
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
          title: const LocalizedText('장보기 준비'),
          actions: <Widget>[
            TextButton(
              onPressed: _submitting ? null : _continueLater,
              child: const LocalizedText('나중에 계속'),
            ),
            IconButton(
              onPressed: _submitting ? null : _cancel,
              icon: const Icon(Icons.close),
              tooltip: context.tr('취소'),
            ),
          ],
        ),
        body: ScoutPageBody(
            maxWidth: 900,
            child: recipeAsync.when(
              loading: () => const Center(
                child: CircularProgressIndicator(),
              ),
              error: (_, __) => CenteredStateView(
                  icon: Icons.refresh,
                  title: '레시피를 불러올 수 없습니다.',
                  message: '',
                  actionLabel: context.tr('다시 시도'),
                  onAction: () {
                    switch (source.type) {
                      case 'public':
                        ref.invalidate(recipeByIdProvider(source.id));
                      case 'creator':
                        ref.invalidate(creatorRecipeByIdProvider(source.id));
                      default:
                        ref.invalidate(subscriberRecipeByIdProvider(source.id));
                    }
                  }),
              data: (Recipe? recipe) {
                if (recipe == null) {
                  return const Center(
                    child: LocalizedText('레시피를 찾을 수 없습니다.'),
                  );
                }

                if (_draft == null && _error != null) {
                  return CenteredStateView(
                    icon: Icons.refresh,
                    title: '장보기 준비를 불러오지 못했어요',
                    message: _error!,
                    actionLabel: context.tr('다시 시도'),
                    onAction: () {
                      setState(() {
                        _error = null;
                      });
                      _loadDraft(recipe);
                    },
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
            )),
      ),
    );
  }

  Widget _buildForm(BuildContext context, Recipe recipe) {
    final ShoppingReviewDraft draft = _draft!;
    final bool canSubmit = !_submitting && _isValid(draft);

    final selectedCount = draft.items.where((item) => item.selected).length;
    return SafeArea(
      child: Center(
          child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: ScoutStyle.contentWidth),
        child: Column(children: <Widget>[
          Expanded(
              child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
            children: <Widget>[
              Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Expanded(
                    child: LocalizedText(recipe.title,
                        style: Theme.of(context).textTheme.headlineSmall)),
                GuideHelpButton(lesson: 'buy-quantity', enabled: !_submitting),
              ]),
              const SizedBox(height: 8),
              const LocalizedText('필요한 재료만 골라 담으세요. 이미 있는 재료는 선택을 해제할 수 있어요.'),
              const SizedBox(height: 8),
              const LocalizedText(
                  '조리 원문은 참고용입니다. 구매 수량·단위는 따로 입력하며, 비워 두어도 목록을 만들 수 있습니다.'),
              const SizedBox(height: 12),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const LocalizedText('인분에 맞춰 필요한 양 계산',
                          style: TextStyle(fontWeight: FontWeight.w700)),
                      const SizedBox(height: 4),
                      const LocalizedText(
                          '레시피 기준 인분과 만들 인분을 입력하면, 레시피에서 읽은 수량만 다시 계산합니다. 직접 수정한 구매 수량은 유지됩니다.'),
                      const SizedBox(height: 12),
                      Wrap(spacing: 12, runSpacing: 8, children: [
                        SizedBox(
                          width: 170,
                          child: TextField(
                            controller: _recipeServings,
                            key: const ValueKey('recipe-base-servings'),
                            keyboardType: const TextInputType.numberWithOptions(
                                decimal: true),
                            decoration: InputDecoration(
                                labelText: context.tr('레시피 기준 인분')),
                          ),
                        ),
                        SizedBox(
                          width: 170,
                          child: TextField(
                            controller: _targetServings,
                            key: const ValueKey('recipe-target-servings'),
                            keyboardType: const TextInputType.numberWithOptions(
                                decimal: true),
                            onSubmitted: (_) => _applyServings(),
                            decoration:
                                InputDecoration(labelText: context.tr('만들 인분')),
                          ),
                        ),
                        OutlinedButton.icon(
                          key: const ValueKey('apply-recipe-servings'),
                          onPressed: _submitting ? null : _applyServings,
                          icon: const Icon(Icons.calculate_outlined),
                          label: const LocalizedText('필요량 계산'),
                        ),
                      ]),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                    color: ScoutStyle.mint,
                    borderRadius: BorderRadius.circular(18)),
                child: Row(children: <Widget>[
                  const Icon(Icons.shopping_basket_outlined,
                      color: ScoutStyle.forest),
                  const SizedBox(width: 12),
                  Expanded(
                      child: LocalizedText(
                          '전체 ${draft.items.length}개 중 $selectedCount개 선택',
                          style: Theme.of(context).textTheme.titleMedium)),
                ]),
              ),
              if (_needsLogin)
                TextButton(
                    onPressed: () async {
                      final account = ref.read(activeAccountIdProvider);
                      await context.push(loginFor(
                          GoRouterState.of(context).uri.toString(),
                          resume: true,
                          account: account));
                      if (mounted) setState(() => _needsLogin = false);
                    },
                    child: const LocalizedText('로그인 후 계속')),
              if (_error != null) ...<Widget>[
                const SizedBox(height: 12),
                LocalizedText(_error!,
                    style:
                        TextStyle(color: Theme.of(context).colorScheme.error)),
              ],
              const SizedBox(height: 20),
              LocalizedText('장볼 재료 선택',
                  style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 10),
              for (var index = 0; index < draft.items.length; index++)
                _itemTile(index, draft.items[index]),
            ],
          )),
          Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
              child: SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: canSubmit ? () => _submit(recipe) : null,
                  icon: _submitting
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.shopping_basket_outlined),
                  label: LocalizedText(_submitting
                      ? '목록을 만드는 중이에요'
                      : '장보기 목록 만들기 · $selectedCount개'),
                ),
              )),
        ]),
      )),
    );
  }

  Widget _itemTile(
    int index,
    ShoppingReviewDraftItem item,
  ) {
    final colorScheme = Theme.of(context).colorScheme;
    final selected = item.selected;
    final quantity = item.quantity;
    final quantityLabel = quantity == null
        ? ''
        : quantity % 1 == 0
            ? quantity.toInt().toString()
            : quantity.toString();

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      elevation: 0,
      color: selected ? colorScheme.surface : ScoutStyle.cream,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(
          color: selected
              ? colorScheme.primary.withValues(alpha: 0.42)
              : colorScheme.outlineVariant,
        ),
      ),
      child: CheckboxListTile(
        value: selected,
        secondary: IconButton(
          icon: const Icon(Icons.edit_outlined),
          tooltip: context.tr('구매 수량·단위'),
          onPressed: _submitting
              ? null
              : () async {
                  final updated =
                      await showShoppingPurchaseQuantityDialog(context, item);
                  if (updated != null && mounted) _updateItem(index, updated);
                },
        ),
        controlAffinity: ListTileControlAffinity.leading,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 10,
          vertical: 4,
        ),
        title: LocalizedText(
          item.ingredientText,
          semanticsLabel: context.tr('레시피 재료 ${item.ingredientText}'),
          style: Theme.of(context).textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w600,
              ),
        ),
        subtitle: LocalizedText(
          !selected
              ? '이번 장보기에서 제외'
              : item.quantity == null
                  ? '구매 수량·단위 미입력 · 나중에 입력 가능'
                  : '구매 $quantityLabel ${shoppingUnitLabel(item.unit)}',
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: selected
                    ? colorScheme.primary
                    : colorScheme.onSurfaceVariant,
                fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
              ),
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
                    needsReview: item.needsReview,
                    purchaseConfirmed: item.purchaseConfirmed,
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
