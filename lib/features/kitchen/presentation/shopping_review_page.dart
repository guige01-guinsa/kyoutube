import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../recipes/application/recipe_providers.dart';
import '../../recipes/domain/recipe.dart';
import '../../recipes/domain/recipe_source_reference.dart';
import '../application/kitchen_providers.dart';
import '../application/shopping_persistence_controllers.dart';
import '../domain/shopping_review_drafts.dart';

class ShoppingReviewPage extends ConsumerStatefulWidget {
  const ShoppingReviewPage({super.key, required this.sourceRecipeReference});

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
  final Map<String, TextEditingController> _nameControllers = {};
  final Map<String, TextEditingController> _quantityControllers = {};

  RecipeSourceReference get _source =>
      RecipeSourceReference.parse(widget.sourceRecipeReference);

  @override
  void dispose() {
    _saveTimer?.cancel();
    for (final controller in _nameControllers.values) {
      controller.dispose();
    }
    for (final controller in _quantityControllers.values) {
      controller.dispose();
    }
    super.dispose();
  }

  Future<void> _loadDraft(Recipe recipe) async {
    if (_loadingDraft || _draft != null) return;
    _loadingDraft = true;
    try {
      final controller =
          await ref.read(shoppingReviewDraftControllerProvider.future);
      final draft = await controller.getOrCreate(
        sourceRecipeId: _source.value,
        initialItems: List<ShoppingReviewDraftItem>.generate(
          recipe.ingredients.length,
          (index) => ShoppingReviewDraftItem(
            localId: 'ingredient-$index',
            ingredientText: recipe.ingredients[index],
            name: '',
            quantityInput: '',
            quantity: null,
            unit: null,
          ),
        ),
      );
      if (!mounted) return;
      for (final item in draft.items) {
        _nameControllers[item.localId] = TextEditingController(text: item.name);
        _quantityControllers[item.localId] =
            TextEditingController(text: item.quantityInput);
      }
      setState(() {
        _draftController = controller;
        _draft = draft;
        _loadingDraft = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loadingDraft = false;
        _error = '재료 검토 초안을 불러오지 못했습니다.';
      });
    }
  }

  ShoppingReviewDraft _replaceItems(List<ShoppingReviewDraftItem> items) {
    final draft = _draft!;
    return ShoppingReviewDraft(
      schemaVersion: draft.schemaVersion,
      draftId: draft.draftId,
      sourceRecipeId: draft.sourceRecipeId,
      createIdempotencyKey: draft.createIdempotencyKey,
      createdAt: draft.createdAt,
      updatedAt: DateTime.now().toUtc(),
      items: List.unmodifiable(items),
    );
  }

  void _updateItem(int index, ShoppingReviewDraftItem item) {
    final items = List<ShoppingReviewDraftItem>.from(_draft!.items);
    items[index] = item;
    setState(() => _draft = _replaceItems(items));
    _scheduleSave();
  }

  void _scheduleSave() {
    _saveTimer?.cancel();
    _saveTimer = Timer(const Duration(milliseconds: 450), () async {
      final draft = _draft;
      final controller = _draftController;
      if (draft == null || controller == null) return;
      try {
        await controller.save(draft);
      } catch (_) {
        if (mounted) setState(() => _error = '초안을 저장하지 못했습니다.');
      }
    });
  }

  Future<void> _saveNow() async {
    _saveTimer?.cancel();
    final draft = _draft;
    final controller = _draftController;
    if (draft != null && controller != null) await controller.save(draft);
  }

  Future<void> _continueLater() async {
    try {
      await _saveNow();
      if (mounted) {
        setState(() => _popping = true);
        context.pop();
      }
    } catch (_) {
      if (mounted) setState(() => _error = '초안을 저장하지 못했습니다.');
    }
  }

  Future<void> _cancel() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('검토 취소'),
        content: const Text('저장된 검토 초안을 삭제할까요?'),
        actions: <Widget>[
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('계속 검토')),
          FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('삭제')),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    try {
      await _draftController?.cancel(_source.value);
      if (mounted) {
        setState(() => _popping = true);
        context.pop();
      }
    } catch (_) {
      if (mounted) setState(() => _error = '초안을 삭제하지 못했습니다.');
    }
  }

  Future<void> _submit() async {
    final draft = _draft;
    if (draft == null || _submitting) return;
    try {
      draft.validate(forSubmission: true);
    } on FormatException catch (error) {
      setState(() => _error = error.message);
      return;
    }
    setState(() {
      _submitting = true;
      _error = null;
    });
    try {
      await _saveNow();
      final result = await ref.read(kitchenApiProvider).createShoppingList(
            sourceRecipeId: draft.sourceRecipeId,
            items: draft.items,
            idempotencyKey: draft.createIdempotencyKey,
          );
      if (result.idempotencyKey != draft.createIdempotencyKey) {
        throw const FormatException('Invalid shopping list create response');
      }
      await _draftController?.cancel(_source.value);
      if (!mounted) return;
      ref.invalidate(kitchenShoppingListsProvider);
      context.go('/kitchen?tab=shopping');
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _submitting = false;
        _error = '장보기 목록 생성에 실패했습니다. 입력과 초안은 유지됩니다.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final source = _source;
    final recipeAsync = switch (source.type) {
      'public' => ref.watch(recipeByIdProvider(source.id)),
      'creator' => ref.watch(creatorRecipeByIdProvider(source.id)),
      _ => ref.watch(subscriberRecipeByIdProvider(source.id)),
    };
    return PopScope<void>(
      canPop: _popping,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && !_popping) {
          unawaited(_continueLater());
        }
      },
      child: Scaffold(
        appBar: AppBar(
          title: const Text('장보기 재료 검토'),
          actions: <Widget>[
            TextButton(
                onPressed: _submitting ? null : _continueLater,
                child: const Text('나중에 계속')),
            IconButton(
                onPressed: _submitting ? null : _cancel,
                icon: const Icon(Icons.close),
                tooltip: '취소'),
          ],
        ),
        body: recipeAsync.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (_, __) => const Center(child: Text('레시피를 불러오지 못했습니다.')),
          data: (recipe) {
            if (recipe == null) {
              return const Center(child: Text('레시피를 찾을 수 없습니다.'));
            }
            WidgetsBinding.instance
                .addPostFrameCallback((_) => _loadDraft(recipe));
            if (_draft == null) {
              return const Center(child: CircularProgressIndicator());
            }
            return _buildForm(context);
          },
        ),
      ),
    );
  }

  Widget _buildForm(BuildContext context) {
    final draft = _draft!;
    final canSubmit = !_submitting && _isValid(draft);
    return SafeArea(
      child: Column(
        children: <Widget>[
          if (_error != null)
            MaterialBanner(content: Text(_error!), actions: <Widget>[
              TextButton(
                  onPressed: () => setState(() => _error = null),
                  child: const Text('닫기'))
            ]),
          const Padding(
            padding: EdgeInsets.all(16),
            child: Align(
                alignment: Alignment.centerLeft,
                child: Text('원문 재료를 확인하고 이름·수량·단위를 입력하세요.')),
          ),
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              itemCount: draft.items.length,
              itemBuilder: (context, index) =>
                  _itemEditor(context, index, draft.items[index]),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                    onPressed: canSubmit ? _submit : null,
                    icon: _submitting
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2))
                        : const Icon(Icons.playlist_add),
                    label: const Text('장보기 목록 만들기'))),
          ),
        ],
      ),
    );
  }

  Widget _itemEditor(
      BuildContext context, int index, ShoppingReviewDraftItem item) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              children: <Widget>[
                Expanded(
                  child: Text(
                    '원문: ${item.ingredientText}',
                    semanticsLabel: '읽기 전용 원문 재료 ${item.ingredientText}',
                  ),
                ),
                IconButton(
                  onPressed: _draft!.items.length <= 1
                      ? null
                      : () {
                          _nameControllers.remove(item.localId)?.dispose();
                          _quantityControllers.remove(item.localId)?.dispose();
                          final items =
                              List<ShoppingReviewDraftItem>.from(_draft!.items)
                                ..removeAt(index);
                          setState(() => _draft = _replaceItems(items));
                          _scheduleSave();
                        },
                  icon: const Icon(Icons.delete_outline),
                  tooltip: '재료 제거',
                ),
              ],
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _nameControllers[item.localId],
              decoration: const InputDecoration(
                  labelText: '검토한 재료 이름', helperText: '필수'),
              textInputAction: TextInputAction.next,
              onChanged: (value) => _updateItem(
                index,
                ShoppingReviewDraftItem(
                  localId: item.localId,
                  ingredientText: item.ingredientText,
                  name: value,
                  quantityInput: item.quantityInput,
                  quantity: item.quantity,
                  unit: item.unit,
                ),
              ),
            ),
            const SizedBox(height: 8),
            Row(
              children: <Widget>[
                Expanded(
                  child: TextField(
                    controller: _quantityControllers[item.localId],
                    decoration: const InputDecoration(labelText: '수량'),
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                    textInputAction: TextInputAction.next,
                    onChanged: (value) => _updateItem(
                      index,
                      ShoppingReviewDraftItem(
                        localId: item.localId,
                        ingredientText: item.ingredientText,
                        name: item.name,
                        quantityInput: value,
                        quantity: double.tryParse(value.trim()),
                        unit: item.unit,
                      ),
                    ),
                  ),
                ),
                Expanded(
                  child: DropdownButtonFormField<String>(
                    initialValue: item.unit,
                    decoration: const InputDecoration(labelText: '단위'),
                    items: const <DropdownMenuItem<String>>[
                      DropdownMenuItem(value: 'g', child: Text('g')),
                      DropdownMenuItem(value: 'kg', child: Text('kg')),
                      DropdownMenuItem(value: 'ml', child: Text('ml')),
                      DropdownMenuItem(value: 'l', child: Text('L')),
                      DropdownMenuItem(value: 'ea', child: Text('개')),
                    ],
                    onChanged: (value) => _updateItem(
                      index,
                      ShoppingReviewDraftItem(
                        localId: item.localId,
                        ingredientText: item.ingredientText,
                        name: item.name,
                        quantityInput: item.quantityInput,
                        quantity: item.quantity,
                        unit: value,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
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
