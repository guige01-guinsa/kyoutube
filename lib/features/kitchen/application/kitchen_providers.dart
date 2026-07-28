import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/kitchen_api.dart';
import '../domain/kitchen_models.dart';

class KitchenShoppingListsQuery {
  const KitchenShoppingListsQuery({
    this.includeCompleted = false,
    this.onlyWithOpenItems = true,
    this.completedWithinDays = 7,
  });

  final bool includeCompleted;
  final bool onlyWithOpenItems;
  final int completedWithinDays;

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) {
      return true;
    }

    return other is KitchenShoppingListsQuery &&
        other.includeCompleted == includeCompleted &&
        other.onlyWithOpenItems == onlyWithOpenItems &&
        other.completedWithinDays == completedWithinDays;
  }

  @override
  int get hashCode =>
      Object.hash(includeCompleted, onlyWithOpenItems, completedWithinDays);
}

const kitchenDefaultShoppingListsQuery = KitchenShoppingListsQuery();

final kitchenApiProvider = Provider<KitchenApi>(
  (ref) => KitchenApi(),
);

final kitchenShoppingListsProvider =
    FutureProvider.family<List<KitchenShoppingList>, KitchenShoppingListsQuery>(
  (ref, KitchenShoppingListsQuery query) async {
    final api = ref.watch(kitchenApiProvider);
    try {
      await api.archiveOldCompletedShoppingLists(retentionDays: 30);
    } catch (_) {
      // Cleanup failure should not block loading current shopping lists.
    }
    final status = query.includeCompleted ? 'all' : 'active';
    final lists = await api.listShoppingLists(status: status);

    final now = DateTime.now();
    final completedCutoff = now.subtract(
      Duration(days: query.completedWithinDays),
    );

    return lists.where((KitchenShoppingList list) {
      if (!query.includeCompleted && list.status == 'completed') {
        return false;
      }

      if (query.includeCompleted &&
          list.status == 'completed' &&
          query.completedWithinDays > 0) {
        final referenceTime = list.updatedAt ?? list.createdAt;
        if (referenceTime != null && referenceTime.isBefore(completedCutoff)) {
          return false;
        }
      }

      if (query.onlyWithOpenItems && list.openItemCount <= 0) {
        return false;
      }

      return true;
    }).toList(growable: false);
  },
);

final kitchenCookSessionsProvider = FutureProvider<List<KitchenCookSession>>(
  (ref) async {
    final api = ref.watch(kitchenApiProvider);
    return api.listCookSessions();
  },
);
