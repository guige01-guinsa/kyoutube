class KitchenShoppingItem {
  const KitchenShoppingItem({
    required this.id,
    required this.listId,
    required this.name,
    required this.isChecked,
    this.quantity,
    this.unit,
  });

  final String id;
  final String listId;
  final String name;
  final bool isChecked;
  final double? quantity;
  final String? unit;

  factory KitchenShoppingItem.fromJson(Map<String, dynamic> json) {
    double? parseQuantity(dynamic value) {
      if (value is num) {
        return value.toDouble();
      }
      return null;
    }

    return KitchenShoppingItem(
      id: (json['id'] ?? '').toString(),
      listId: (json['list_id'] ?? '').toString(),
      name: (json['name'] ?? '').toString(),
      isChecked: json['is_checked'] == true,
      quantity: parseQuantity(json['quantity']),
      unit: json['unit']?.toString(),
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
    this.createdAt,
    this.updatedAt,
  });

  final String id;
  final String status;
  final String title;
  final List<KitchenShoppingItem> items;
  final int openItemCount;
  final DateTime? createdAt;
  final DateTime? updatedAt;

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

    return KitchenShoppingList(
      id: (json['id'] ?? '').toString(),
      status: (json['status'] ?? '').toString(),
      title: (json['title'] ?? '').toString(),
      items: parsedItems,
      openItemCount: parseCount(json['open_item_count']),
      createdAt: DateTime.tryParse((json['created_at'] ?? '').toString()),
      updatedAt: DateTime.tryParse((json['updated_at'] ?? '').toString()),
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
