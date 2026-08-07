import '../data/kitchen_api.dart';
import '../domain/kitchen_models.dart';

class ShoppingItemMutationController {
  ShoppingItemMutationController({required KitchenApi api}) : _api = api;

  final KitchenApi _api;
  final Map<String, Future<KitchenShoppingItem>> _inFlight = {};

  bool isProcessing(String itemId) => _inFlight.containsKey(itemId);

  Future<KitchenShoppingItem> setStatus({
    required String itemId,
    required KitchenShoppingItemStatus status,
    required int expectedRevision,
  }) {
    return _inFlight[itemId] ??= _runStatus(
      itemId: itemId,
      status: status,
      expectedRevision: expectedRevision,
    );
  }

  Future<KitchenShoppingItem> review({
    required String itemId,
    required String name,
    required double? quantity,
    required String? unit,
    required int expectedRevision,
  }) {
    return _inFlight[itemId] ??= _runReview(
      itemId: itemId,
      name: name,
      quantity: quantity,
      unit: unit,
      expectedRevision: expectedRevision,
    );
  }

  Future<KitchenShoppingItem> reviewThenStatus({
    required String itemId,
    required String name,
    required double quantity,
    required String unit,
    required int expectedRevision,
    required KitchenShoppingItemStatus status,
  }) {
    return _inFlight[itemId] ??= _runReviewThenStatus(
      itemId: itemId,
      name: name,
      quantity: quantity,
      unit: unit,
      expectedRevision: expectedRevision,
      status: status,
    );
  }

  Future<KitchenShoppingItem> _runStatus({
    required String itemId,
    required KitchenShoppingItemStatus status,
    required int expectedRevision,
  }) async {
    try {
      return await _api.setShoppingItemStatus(
        itemId: itemId,
        status: status,
        expectedRevision: expectedRevision,
      );
    } finally {
      _inFlight.remove(itemId);
    }
  }

  Future<KitchenShoppingItem> _runReview({
    required String itemId,
    required String name,
    required double? quantity,
    required String? unit,
    required int expectedRevision,
  }) async {
    try {
      return await _api.reviewShoppingItem(
        itemId: itemId,
        name: name,
        quantity: quantity,
        unit: unit,
        expectedRevision: expectedRevision,
      );
    } finally {
      _inFlight.remove(itemId);
    }
  }

  Future<KitchenShoppingItem> _runReviewThenStatus({
    required String itemId,
    required String name,
    required double quantity,
    required String unit,
    required int expectedRevision,
    required KitchenShoppingItemStatus status,
  }) async {
    try {
      final reviewed = await _api.reviewShoppingItem(
        itemId: itemId,
        name: name,
        quantity: quantity,
        unit: unit,
        expectedRevision: expectedRevision,
      );
      return await _api.setShoppingItemStatus(
        itemId: itemId,
        status: status,
        expectedRevision: reviewed.revision,
      );
    } finally {
      _inFlight.remove(itemId);
    }
  }
}
