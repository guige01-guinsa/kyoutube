import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:k_youtube/features/kitchen/application/shopping_item_mutation_controller.dart';
import 'package:k_youtube/features/kitchen/data/kitchen_api.dart';
import 'package:k_youtube/features/kitchen/domain/kitchen_models.dart';

class _Client extends http.BaseClient {
  int calls = 0;
  final requests = <Map<String, dynamic>>[];

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    calls++;
    final body = request is http.Request && request.body.isNotEmpty
        ? jsonDecode(request.body) as Map<String, dynamic>
        : <String, dynamic>{};
    requests.add(body);
    final revision = calls == 1 ? 2 : 3;
    final payload = <String, dynamic>{
      'status': 'ok',
      'data': <String, dynamic>{
        'id': 'item-1',
        'list_id': 'list-1',
        'name': 'Potato',
        'ingredient_text': 'raw potato',
        'quantity': 2,
        'unit': 'kg',
        'status': body['status'] ?? 'pending',
        'review_status': 'confirmed',
        'needs_review': false,
        'is_checked': body['status'] == 'purchased',
        'revision': revision,
        'updated_at': '2026-01-01T00:00:00Z',
      },
    };
    final response = http.Response(jsonEncode(payload), 200);
    return http.StreamedResponse(
        Stream<List<int>>.value(response.bodyBytes), 200,
        request: request);
  }
}

void main() {
  test('same item concurrent status calls share one request', () async {
    final client = _Client();
    final controller = ShoppingItemMutationController(
      api: KitchenApi(
          httpClient: client, accessTokenProvider: () async => 'jwt'),
    );
    final futures = <Future<KitchenShoppingItem>>[
      controller.setStatus(
          itemId: 'item-1',
          status: KitchenShoppingItemStatus.purchased,
          expectedRevision: 1),
      controller.setStatus(
          itemId: 'item-1',
          status: KitchenShoppingItemStatus.purchased,
          expectedRevision: 1),
    ];
    await Future.wait(futures);
    expect(client.calls, 1);
  });

  test('review then status uses the review response revision', () async {
    final client = _Client();
    final controller = ShoppingItemMutationController(
      api: KitchenApi(
          httpClient: client, accessTokenProvider: () async => 'jwt'),
    );
    await controller.reviewThenStatus(
      itemId: 'item-1',
      name: 'Potato',
      quantity: 2,
      unit: 'kg',
      expectedRevision: 1,
      status: KitchenShoppingItemStatus.purchased,
    );
    expect(client.calls, 2);
    expect(client.requests[1]['expected_revision'], 2);
  });
}
