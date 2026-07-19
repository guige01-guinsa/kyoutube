import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/kitchen_api.dart';
import '../domain/kitchen_models.dart';

final kitchenApiProvider = Provider<KitchenApi>(
  (ref) => KitchenApi(),
);

final kitchenIngredientSearchProvider = StateProvider<String>(
  (ref) => '',
);

final kitchenIngredientsProvider = FutureProvider<List<KitchenIngredient>>(
  (ref) async {
    final api = ref.watch(kitchenApiProvider);
    final query = ref.watch(kitchenIngredientSearchProvider);
    return api.listIngredients(query: query);
  },
);

final kitchenShoppingListsProvider = FutureProvider<List<KitchenShoppingList>>(
  (ref) async {
    final api = ref.watch(kitchenApiProvider);
    return api.listShoppingLists(status: 'active');
  },
);

final kitchenCookSessionsProvider = FutureProvider<List<KitchenCookSession>>(
  (ref) async {
    final api = ref.watch(kitchenApiProvider);
    return api.listCookSessions();
  },
);
