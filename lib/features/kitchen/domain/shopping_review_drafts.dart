import 'dart:convert';

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
  });

  final String localId;
  final String ingredientText;
  final String name;
  final String quantityInput;
  final double? quantity;
  final String? unit;

  Map<String, dynamic> toJson() => <String, dynamic>{
        'local_id': localId,
        'ingredient_text': ingredientText,
        'name': name,
        'quantity_input': quantityInput,
        'quantity': quantity,
        'unit': unit,
      };

  factory ShoppingReviewDraftItem.fromJson(Map<String, dynamic> json) {
    final localId = json['local_id'];
    final ingredientText = json['ingredient_text'];
    final name = json['name'];
    final quantityInput = json['quantity_input'];
    final quantity = json['quantity'];
    final unit = json['unit'];
    if (localId is! String ||
        ingredientText is! String ||
        name is! String ||
        quantityInput is! String ||
        (quantity != null && quantity is! num) ||
        (unit != null && unit is! String)) {
      throw const FormatException('Invalid shopping review draft item');
    }
    return ShoppingReviewDraftItem(
      localId: localId,
      ingredientText: ingredientText,
      name: name,
      quantityInput: quantityInput,
      quantity: quantity?.toDouble(),
      unit: unit as String?,
    );
  }
}

class ShoppingReviewDraft {
  const ShoppingReviewDraft({
    required this.schemaVersion,
    required this.draftId,
    required this.sourceRecipeId,
    required this.createIdempotencyKey,
    required this.createdAt,
    required this.updatedAt,
    required this.items,
  });

  final int schemaVersion;
  final String draftId;
  final String sourceRecipeId;
  final String createIdempotencyKey;
  final DateTime createdAt;
  final DateTime updatedAt;
  final List<ShoppingReviewDraftItem> items;

  Map<String, dynamic> toJson() => <String, dynamic>{
        'schema_version': schemaVersion,
        'draft_id': draftId,
        'source_recipe_id': sourceRecipeId,
        'create_idempotency_key': createIdempotencyKey,
        'created_at': createdAt.toUtc().toIso8601String(),
        'updated_at': updatedAt.toUtc().toIso8601String(),
        'items': items.map((item) => item.toJson()).toList(),
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
    final names = <String>{};
    for (final item in items) {
      if (item.localId.isEmpty ||
          item.ingredientText.isEmpty ||
          item.ingredientText.length > 500 ||
          item.name.length > 200 ||
          item.quantityInput.length > 32 ||
          (item.unit?.length ?? 0) > 32) {
        throw const FormatException('Invalid shopping review draft item');
      }
      if (forSubmission && item.name.trim().isEmpty) {
        throw const FormatException('Shopping review name is required');
      }
      if ((item.quantity == null) != (item.unit == null)) {
        throw const FormatException(
            'Shopping review quantity and unit must be provided together');
      }
      if (item.quantity != null &&
          (item.quantity! <= 0 ||
              !item.quantity!.isFinite ||
              !_units.contains(item.unit))) {
        throw const FormatException('Invalid shopping review quantity or unit');
      }
      if (forSubmission) {
        final normalized = item.name.trim().toLowerCase();
        if (!names.add(normalized)) {
          throw const FormatException('Duplicate shopping review name');
        }
      }
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
    );
    draft.validate();
    return draft;
  }

  static const _units = <String>{'g', 'kg', 'ml', 'l', 'ea'};
}
