import '../data/kitchen_api.dart';
import '../data/shopping_persistence.dart';
import '../domain/shopping_review_drafts.dart';

typedef CurrentUserId = Future<String?> Function();

class ShoppingReviewDraftController {
  ShoppingReviewDraftController(
      {required ShoppingReviewDraftStore store,
      required CurrentUserId currentUserId})
      : _store = store,
        _currentUserId = currentUserId;

  final ShoppingReviewDraftStore _store;
  final CurrentUserId _currentUserId;

  Future<ShoppingReviewDraft> getOrCreate(
      {required String sourceRecipeId,
      required List<ShoppingReviewDraftItem> initialItems}) async {
    final userId = await _requireUserId();
    return _store.getOrCreateDraft(
        userId: userId,
        sourceRecipeId: sourceRecipeId,
        initialItems: initialItems);
  }

  Future<void> save(ShoppingReviewDraft draft) async {
    final userId = await _requireUserId();
    await _store.saveDraft(userId: userId, draft: draft);
  }

  Future<void> cancel(String sourceRecipeId) async {
    final userId = await _requireUserId();
    await _store.clearDraft(userId: userId, sourceRecipeId: sourceRecipeId);
  }

  Future<String> _requireUserId() async {
    final userId = await _currentUserId();
    if (userId == null || userId.trim().isEmpty) {
      throw StateError('로그인이 필요합니다.');
    }
    return userId;
  }
}

class ShoppingListCompletionController {
  ShoppingListCompletionController(
      {required KitchenApi api,
      required CompletionKeyStore keyStore,
      required CurrentUserId currentUserId})
      : _api = api,
        _keyStore = keyStore,
        _currentUserId = currentUserId;

  final KitchenApi _api;
  final CompletionKeyStore _keyStore;
  final CurrentUserId _currentUserId;

  Future<KitchenShoppingListCompletion> complete(String listId) async {
    final userId = await _requireUserId();
    final key = await _keyStore.getOrCreateCompletionKey(
        userId: userId, listId: listId);
    final result =
        await _api.completeShoppingList(listId: listId, idempotencyKey: key);
    await _keyStore.clearCompletionKey(userId: userId, listId: listId);
    return result;
  }

  Future<String> _requireUserId() async {
    final userId = await _currentUserId();
    if (userId == null || userId.trim().isEmpty) {
      throw StateError('로그인이 필요합니다.');
    }
    return userId;
  }
}
