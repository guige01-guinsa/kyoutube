class KitchenIngredient {
  const KitchenIngredient({
    required this.id,
    required this.name,
    this.quantity,
    this.unit,
    this.storageLocation,
    this.expiresOn,
    this.note,
  });

  final String id;
  final String name;
  final double? quantity;
  final String? unit;
  final String? storageLocation;
  final String? expiresOn;
  final String? note;

  factory KitchenIngredient.fromJson(Map<String, dynamic> json) {
    double? parseQuantity(dynamic value) {
      if (value is num) {
        return value.toDouble();
      }
      return null;
    }

    return KitchenIngredient(
      id: (json['id'] ?? '').toString(),
      name: (json['name'] ?? '').toString(),
      quantity: parseQuantity(json['quantity']),
      unit: json['unit']?.toString(),
      storageLocation: json['storage_location']?.toString(),
      expiresOn: json['expires_on']?.toString(),
      note: json['note']?.toString(),
    );
  }
}

enum KitchenShoppingItemStatus {
  pending,
  purchased,
  skipped,
  unavailable,
}

extension KitchenShoppingItemStatusJson on KitchenShoppingItemStatus {
  String get value => name;

  static KitchenShoppingItemStatus parse(Object? value) {
    switch (value) {
      case 'pending':
        return KitchenShoppingItemStatus.pending;
      case 'purchased':
        return KitchenShoppingItemStatus.purchased;
      case 'skipped':
        return KitchenShoppingItemStatus.skipped;
      case 'unavailable':
        return KitchenShoppingItemStatus.unavailable;
      default:
        throw const FormatException('Unknown shopping item status');
    }
  }
}

enum KitchenShoppingItemReviewStatus {
  required,
  confirmed,
}

extension KitchenShoppingItemReviewStatusJson
    on KitchenShoppingItemReviewStatus {
  String get value => name;

  static KitchenShoppingItemReviewStatus parse(Object? value) {
    switch (value) {
      case 'required':
        return KitchenShoppingItemReviewStatus.required;
      case 'confirmed':
        return KitchenShoppingItemReviewStatus.confirmed;
      default:
        throw const FormatException('Unknown shopping item review status');
    }
  }
}

class KitchenShoppingItem {
  const KitchenShoppingItem({
    required this.id,
    required this.listId,
    required this.name,
    required this.ingredientText,
    required this.status,
    required this.reviewStatus,
    required this.needsReview,
    required this.isChecked,
    required this.revision,
    required this.updatedAt,
    this.quantity,
    this.unit,
  });

  final String id;
  final String listId;
  final String name;
  final String ingredientText;
  final KitchenShoppingItemStatus status;
  final KitchenShoppingItemReviewStatus reviewStatus;
  final bool needsReview;
  final bool isChecked;
  final double? quantity;
  final String? unit;
  final int revision;
  final DateTime updatedAt;

  /// Legacy UI compatibility; new state transitions must use [status].
  bool get isPurchased => status == KitchenShoppingItemStatus.purchased;

  factory KitchenShoppingItem.fromJson(Map<String, dynamic> json) {
    if (json['id'] is! String ||
        (json['id'] as String).trim().isEmpty ||
        json['list_id'] is! String ||
        (json['list_id'] as String).trim().isEmpty ||
        json['name'] is! String ||
        (json['name'] as String).trim().isEmpty ||
        json['ingredient_text'] is! String ||
        (json['ingredient_text'] as String).isEmpty) {
      throw const FormatException(
          'Invalid shopping item identity or ingredient text');
    }
    double? parseQuantity(dynamic value) {
      if (value is num) {
        return value.toDouble();
      }
      if (value != null) {
        throw const FormatException('Invalid shopping item quantity');
      }
      return null;
    }

    final status = KitchenShoppingItemStatusJson.parse(json['status']);
    final reviewStatus =
        KitchenShoppingItemReviewStatusJson.parse(json['review_status']);
    final unit = json['unit'];
    if (unit != null &&
        (unit is! String ||
            !<String>{'g', 'kg', 'ml', 'l', 'ea'}.contains(unit))) {
      throw const FormatException('Invalid shopping item unit');
    }
    final needsReview = json['needs_review'];
    if (needsReview is! bool ||
        needsReview !=
            (reviewStatus == KitchenShoppingItemReviewStatus.required)) {
      throw const FormatException('Shopping item review state is inconsistent');
    }
    final isChecked = json['is_checked'];
    if (isChecked is! bool ||
        isChecked != (status == KitchenShoppingItemStatus.purchased)) {
      throw const FormatException(
          'Shopping item status and legacy check state are inconsistent');
    }
    final revision = json['revision'];
    if (revision is! int || revision < 0) {
      throw const FormatException('Invalid shopping item revision');
    }
    final updatedAtValue = json['updated_at'];
    if (updatedAtValue is! String) {
      throw const FormatException('Invalid shopping item updated_at');
    }
    final updatedAt = DateTime.tryParse(updatedAtValue);
    if (updatedAt == null) {
      throw const FormatException('Invalid shopping item updated_at');
    }

    return KitchenShoppingItem(
      id: (json['id'] as String).trim(),
      listId: (json['list_id'] as String).trim(),
      name: (json['name'] as String).trim(),
      ingredientText: json['ingredient_text'] as String,
      status: status,
      reviewStatus: reviewStatus,
      needsReview: needsReview,
      isChecked: isChecked,
      quantity: parseQuantity(json['quantity']),
      unit: unit as String?,
      revision: revision,
      updatedAt: updatedAt,
    );
  }
}

class KitchenShoppingList {
  const KitchenShoppingList({
    required this.id,
    required this.status,
    required this.title,
    required this.items,
    required this.openItemCount,
    this.sourceRecipeId,
  });

  final String id;
  final String status;
  final String title;
  final List<KitchenShoppingItem> items;
  final int openItemCount;
  final String? sourceRecipeId;

  factory KitchenShoppingList.fromJson(Map<String, dynamic> json) {
    final rawItems = json['items'];
    final parsedItems = rawItems is List
        ? rawItems
            .whereType<Map<String, dynamic>>()
            .map(KitchenShoppingItem.fromJson)
            .toList()
        : <KitchenShoppingItem>[];

    int parseCount(dynamic value) {
      if (value is int) {
        return value;
      }
      if (value is num) {
        return value.toInt();
      }
      return 0;
    }

    final rawSourceRecipeId = json['source_recipe_id'];
    final sourceRecipeId =
        rawSourceRecipeId is String && rawSourceRecipeId.trim().isNotEmpty
            ? rawSourceRecipeId.trim()
            : null;

    return KitchenShoppingList(
      id: (json['id'] ?? '').toString(),
      status: (json['status'] ?? '').toString(),
      title: (json['title'] ?? '').toString(),
      items: parsedItems,
      openItemCount: parseCount(json['open_item_count']),
      sourceRecipeId: sourceRecipeId,
    );
  }
}

class KitchenCookSession {
  const KitchenCookSession({
    required this.id,
    required this.recipeType,
    required this.recipeRefId,
    required this.recipeTitle,
    required this.createdAt,
    this.rating,
    this.liked,
    this.note,
  });

  final String id;
  final String recipeType;
  final String recipeRefId;
  final String recipeTitle;
  final String createdAt;
  final int? rating;
  final bool? liked;
  final String? note;

  factory KitchenCookSession.fromJson(Map<String, dynamic> json) {
    int? parseRating(dynamic value) {
      if (value is int) {
        return value;
      }
      if (value is num) {
        return value.toInt();
      }
      return null;
    }

    return KitchenCookSession(
      id: (json['id'] ?? '').toString(),
      recipeType: (json['recipe_type'] ?? '').toString(),
      recipeRefId: (json['recipe_ref_id'] ?? '').toString(),
      recipeTitle: (json['recipe_title'] ?? '').toString(),
      createdAt: (json['created_at'] ?? '').toString(),
      rating: parseRating(json['rating']),
      liked: json['liked'] is bool ? json['liked'] as bool : null,
      note: json['note']?.toString(),
    );
  }
}
