import 'dart:convert';

import 'shopping_units.dart';

const int shoppingReviewDraftSchemaVersion = 1;
const int shoppingReviewDraftMaxItems = 100;
const int shoppingReviewDraftMaxSerializedBytes = 65536;

class ShoppingReviewDraftItem {
  const ShoppingReviewDraftItem({
    required this.localId,
    required this.ingredientText,
    required this.name,
    required this.quantityInput,
    required this.quantity,
    required this.unit,
    this.selected = true,
    this.needsReview = false,
    this.purchaseConfirmed = false,
  });

  final String localId;
  final String ingredientText;
  final String name;
  final String quantityInput;
  final double? quantity;
  final String? unit;
  final bool selected;
  final bool needsReview;

  /// True only after the user enters a purchase quantity, never from parsing
  /// the recipe's cooking amount. Missing on older automatically filled drafts.
  final bool purchaseConfirmed;

  ShoppingReviewDraftItem copyWith({
    String? name,
    String? quantityInput,
    double? quantity,
    String? unit,
    bool? selected,
    bool? needsReview,
    bool? purchaseConfirmed,
  }) =>
      ShoppingReviewDraftItem(
        localId: localId,
        ingredientText: ingredientText,
        name: name ?? this.name,
        quantityInput: quantityInput ?? this.quantityInput,
        quantity: quantity ?? this.quantity,
        unit: unit ?? this.unit,
        selected: selected ?? this.selected,
        needsReview: needsReview ?? this.needsReview,
        purchaseConfirmed: purchaseConfirmed ?? this.purchaseConfirmed,
      );

  Map<String, dynamic> toJson() => <String, dynamic>{
        'local_id': localId,
        'ingredient_text': ingredientText,
        'name': name,
        'quantity_input': quantityInput,
        'quantity': quantity,
        'unit': unit,
        'selected': selected,
        'needs_review': needsReview,
        'purchase_confirmed': purchaseConfirmed,
      };

  factory ShoppingReviewDraftItem.fromJson(Map<String, dynamic> json) {
    final localId = json['local_id'];
    final ingredientText = json['ingredient_text'];
    final name = json['name'];
    final quantityInput = json['quantity_input'];
    final quantity = json['quantity'];
    final unit = json['unit'];
    final selected = json['selected'];
    final needsReview = json['needs_review'];
    final purchaseConfirmed = json['purchase_confirmed'];
    if (localId is! String ||
        ingredientText is! String ||
        name is! String ||
        quantityInput is! String ||
        (quantity != null && quantity is! num) ||
        (unit != null && unit is! String) ||
        (selected != null && selected is! bool) ||
        (needsReview != null && needsReview is! bool) ||
        (purchaseConfirmed != null && purchaseConfirmed is! bool)) {
      throw const FormatException('Invalid shopping review draft item');
    }
    return ShoppingReviewDraftItem(
      localId: localId,
      ingredientText: ingredientText,
      name: name,
      quantityInput: quantityInput,
      quantity: quantity?.toDouble(),
      unit: unit as String?,
      selected: selected is bool ? selected : true,
      needsReview: needsReview is bool ? needsReview : false,
      purchaseConfirmed: purchaseConfirmed is bool ? purchaseConfirmed : false,
    );
  }
}

List<ShoppingReviewDraftItem> mergeShoppingReviewItems(
  Iterable<ShoppingReviewDraftItem> source,
) {
  final merged = <String, ShoppingReviewDraftItem>{};

  for (final item in source) {
    final key = item.name.trim().toLowerCase();
    final existing = merged[key];
    if (existing == null) {
      merged[key] = item;
      continue;
    }

    final amount = _mergeShoppingAmounts(existing, item);
    final rawTexts = <String>{
      ...existing.ingredientText.split(' / '),
      ...item.ingredientText.split(' / '),
    }.where((value) => value.trim().isNotEmpty).join(' / ');

    merged[key] = ShoppingReviewDraftItem(
      localId: existing.localId,
      ingredientText: rawTexts,
      name: existing.name.trim(),
      quantityInput: amount == null ? '' : _formatQuantity(amount.$1),
      quantity: amount?.$1,
      unit: amount?.$2,
      selected: existing.selected || item.selected,
      needsReview: existing.needsReview || item.needsReview || amount == null,
      purchaseConfirmed: existing.purchaseConfirmed && item.purchaseConfirmed,
    );
  }

  return List<ShoppingReviewDraftItem>.unmodifiable(merged.values);
}

(double, String)? _mergeShoppingAmounts(
  ShoppingReviewDraftItem left,
  ShoppingReviewDraftItem right,
) {
  if (left.quantity == null ||
      left.unit == null ||
      right.quantity == null ||
      right.unit == null) {
    return null;
  }
  if (left.unit == right.unit) {
    return (left.quantity! + right.quantity!, left.unit!);
  }
  if (<String>{left.unit!, right.unit!}.every(<String>{'g', 'kg'}.contains)) {
    final leftGrams =
        left.unit == 'kg' ? left.quantity! * 1000 : left.quantity!;
    final rightGrams =
        right.unit == 'kg' ? right.quantity! * 1000 : right.quantity!;
    return (leftGrams + rightGrams, 'g');
  }
  if (<String>{left.unit!, right.unit!}.every(<String>{'ml', 'l'}.contains)) {
    final leftMl = left.unit == 'l' ? left.quantity! * 1000 : left.quantity!;
    final rightMl =
        right.unit == 'l' ? right.quantity! * 1000 : right.quantity!;
    return (leftMl + rightMl, 'ml');
  }
  return null;
}

String _formatQuantity(double value) => value == value.roundToDouble()
    ? value.toInt().toString()
    : value
        .toStringAsFixed(2)
        .replaceFirst(RegExp(r'0+$'), '')
        .replaceFirst(RegExp(r'\.$'), '');

class ShoppingReviewDraft {
  const ShoppingReviewDraft({
    required this.schemaVersion,
    required this.draftId,
    required this.sourceRecipeId,
    required this.createIdempotencyKey,
    required this.createdAt,
    required this.updatedAt,
    required this.items,
    this.recipeServings = 1,
    this.targetServings = 1,
  });

  final int schemaVersion;
  final String draftId;
  final String sourceRecipeId;
  final String createIdempotencyKey;
  final DateTime createdAt;
  final DateTime updatedAt;
  final List<ShoppingReviewDraftItem> items;

  /// The recipe's original servings and the amount the shopper plans to cook.
  /// Both default to one so saved drafts from earlier versions remain valid.
  final double recipeServings, targetServings;

  Map<String, dynamic> toJson() => <String, dynamic>{
        'schema_version': schemaVersion,
        'draft_id': draftId,
        'source_recipe_id': sourceRecipeId,
        'create_idempotency_key': createIdempotencyKey,
        'created_at': createdAt.toUtc().toIso8601String(),
        'updated_at': updatedAt.toUtc().toIso8601String(),
        'items': items.map((item) => item.toJson()).toList(),
        'recipe_servings': recipeServings,
        'target_servings': targetServings,
      };

  String serialize() => jsonEncode(toJson());

  void validate({bool forSubmission = false}) {
    if (schemaVersion != shoppingReviewDraftSchemaVersion ||
        draftId.isEmpty ||
        sourceRecipeId.isEmpty ||
        createIdempotencyKey.isEmpty ||
        items.isEmpty ||
        items.length > shoppingReviewDraftMaxItems) {
      throw const FormatException('Invalid shopping review draft');
    }
    if (!isValidShoppingServings(recipeServings) ||
        !isValidShoppingServings(targetServings)) {
      throw const FormatException('Invalid shopping review servings');
    }
    for (final item in items) {
      if (item.localId.isEmpty ||
          item.ingredientText.isEmpty ||
          item.ingredientText.length > 500 ||
          item.name.length > 200 ||
          item.quantityInput.length > 32 ||
          (item.unit?.length ?? 0) > 32) {
        throw const FormatException('Invalid shopping review draft item');
      }
      if (forSubmission && item.selected && item.name.trim().isEmpty) {
        throw const FormatException('Shopping review name is required');
      }
      if ((item.quantity == null) != (item.unit == null)) {
        throw const FormatException(
            'Shopping review quantity and unit must be provided together');
      }
      if (item.quantity != null &&
          (item.quantity! <= 0 ||
              !item.quantity!.isFinite ||
              !isSupportedShoppingUnit(item.unit))) {
        throw const FormatException('Invalid shopping review quantity or unit');
      }
    }
    if (forSubmission && !items.any((item) => item.selected)) {
      throw const FormatException('Select at least one shopping item');
    }
    if (utf8.encode(serialize()).length >
        shoppingReviewDraftMaxSerializedBytes) {
      throw const FormatException('Shopping review draft is too large');
    }
  }

  factory ShoppingReviewDraft.fromJson(Map<String, dynamic> json) {
    final version = json['schema_version'];
    if (version != shoppingReviewDraftSchemaVersion) {
      throw const FormatException('Unsupported shopping review draft schema');
    }
    final draftId = json['draft_id'];
    final sourceRecipeId = json['source_recipe_id'];
    final key = json['create_idempotency_key'];
    final createdAt = json['created_at'];
    final updatedAt = json['updated_at'];
    final rawItems = json['items'];
    final recipeServings = json['recipe_servings'];
    final targetServings = json['target_servings'];
    if (draftId is! String ||
        sourceRecipeId is! String ||
        key is! String ||
        createdAt is! String ||
        updatedAt is! String ||
        rawItems is! List) {
      throw const FormatException('Invalid shopping review draft');
    }
    final created = DateTime.tryParse(createdAt);
    final updated = DateTime.tryParse(updatedAt);
    if (created == null || updated == null) {
      throw const FormatException('Invalid shopping review draft timestamp');
    }
    final draft = ShoppingReviewDraft(
      schemaVersion: version as int,
      draftId: draftId,
      sourceRecipeId: sourceRecipeId,
      createIdempotencyKey: key,
      createdAt: created,
      updatedAt: updated,
      items: rawItems.map((item) {
        if (item is! Map<String, dynamic>) {
          throw const FormatException('Invalid shopping review draft item');
        }
        return ShoppingReviewDraftItem.fromJson(item);
      }).toList(),
      recipeServings: recipeServings is num ? recipeServings.toDouble() : 1,
      targetServings: targetServings is num ? targetServings.toDouble() : 1,
    );
    draft.validate();
    return draft;
  }
}

bool isValidShoppingServings(double value) =>
    value.isFinite && value >= 0.1 && value <= 1000;

/// Rescale only amounts inferred from the recipe. Values the shopper entered in
/// the purchase editor stay fixed because they describe a chosen package or
/// purchase quantity, not the cooking recipe.
ShoppingReviewDraft rescaleShoppingReviewDraftServings(
  ShoppingReviewDraft draft, {
  required double recipeServings,
  required double targetServings,
}) {
  if (!isValidShoppingServings(recipeServings) ||
      !isValidShoppingServings(targetServings)) {
    throw const FormatException('Invalid shopping review servings');
  }
  final oldFactor = draft.targetServings / draft.recipeServings;
  final nextFactor = targetServings / recipeServings;
  final adjustment = nextFactor / oldFactor;
  if (!adjustment.isFinite || adjustment <= 0 || adjustment > 10000) {
    throw const FormatException('Invalid shopping review servings');
  }
  return ShoppingReviewDraft(
    schemaVersion: draft.schemaVersion,
    draftId: draft.draftId,
    sourceRecipeId: draft.sourceRecipeId,
    createIdempotencyKey: draft.createIdempotencyKey,
    createdAt: draft.createdAt,
    updatedAt: DateTime.now().toUtc(),
    recipeServings: recipeServings,
    targetServings: targetServings,
    items: List<ShoppingReviewDraftItem>.unmodifiable(draft.items.map((item) {
      final quantity = item.quantity;
      if (item.purchaseConfirmed || quantity == null) return item;
      final scaled = quantity * adjustment;
      if (!scaled.isFinite || scaled <= 0 || scaled > 1e9) {
        throw const FormatException('Invalid scaled shopping quantity');
      }
      return item.copyWith(quantity: scaled);
    })),
  );
}
