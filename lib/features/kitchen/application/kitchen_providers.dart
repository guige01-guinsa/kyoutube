import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../auth/application/auth_providers.dart';
import '../data/kitchen_api.dart';
import '../data/shopping_persistence.dart';
import '../domain/kitchen_models.dart';
import 'shopping_persistence_controllers.dart';

final kitchenApiProvider = Provider<KitchenApi>(
  (ref) => KitchenApi(),
);

final kitchenStorageProvider = FutureProvider<SharedPreferencesKeyValueStore>(
  (ref) async =>
      SharedPreferencesKeyValueStore(await SharedPreferences.getInstance()),
);

final shoppingReviewDraftStoreProvider =
    FutureProvider<ShoppingReviewDraftStore>(
  (ref) async => ShoppingReviewDraftStore(
      storage: await ref.watch(kitchenStorageProvider.future)),
);

final completionKeyStoreProvider = FutureProvider<CompletionKeyStore>(
  (ref) async => CompletionKeyStore(
      storage: await ref.watch(kitchenStorageProvider.future)),
);

final shoppingReviewDraftControllerProvider =
    FutureProvider<ShoppingReviewDraftController>((ref) async {
  return ShoppingReviewDraftController(
    store: await ref.watch(shoppingReviewDraftStoreProvider.future),
    currentUserId: () async => ref.read(authUserProvider).valueOrNull?.id,
  );
});

final shoppingListCompletionControllerProvider =
    FutureProvider<ShoppingListCompletionController>((ref) async {
  return ShoppingListCompletionController(
    api: ref.read(kitchenApiProvider),
    keyStore: await ref.watch(completionKeyStoreProvider.future),
    currentUserId: () async => ref.read(authUserProvider).valueOrNull?.id,
  );
});

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
