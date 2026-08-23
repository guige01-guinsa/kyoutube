import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

import 'package:k_youtube/features/kitchen/data/kitchen_api.dart';
import 'package:k_youtube/features/kitchen/domain/kitchen_models.dart';
import 'package:k_youtube/features/kitchen/domain/shopping_review_drafts.dart';

class _FakeClient extends http.BaseClient {
  _FakeClient(this.handler);

  final Future<http.Response> Function(http.BaseRequest request) handler;
  http.BaseRequest? lastRequest;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    lastRequest = request;
    final response = await handler(request);
    return http.StreamedResponse(
      Stream<List<int>>.value(response.bodyBytes),
      response.statusCode,
      headers: response.headers,
      request: request,
    );
  }
}

Map<String, dynamic> _item() => <String, dynamic>{
      'id': 'item-1',
      'list_id': 'list-1',
      'name': 'Potato',
      'ingredient_text': '2 kg potato',
      'quantity': 2,
      'unit': 'kg',
      'status': 'purchased',
      'review_status': 'confirmed',
      'needs_review': false,
      'is_checked': true,
      'revision': 4,
      'updated_at': '2026-01-01T00:00:00Z',
    };

http.Response _ok(Object data) => http.Response(
      jsonEncode(<String, dynamic>{'status': 'ok', 'data': data}),
      200,
      headers: const <String, String>{'content-type': 'application/json'},
    );

void main() {
  test('review and status send only client-owned fields plus revision',
      () async {
    final client = _FakeClient((request) async => _ok(_item()));
    final api =
        KitchenApi(httpClient: client, accessTokenProvider: () async => 'jwt');

    await api.reviewShoppingItem(
      itemId: 'item-1',
      name: 'Potato',
      quantity: 2,
      unit: 'kg',
      expectedRevision: 3,
    );
    final reviewBody = jsonDecode((client.lastRequest! as http.Request).body)
        as Map<String, dynamic>;
    expect(reviewBody, <String, dynamic>{
      'name': 'Potato',
      'quantity': 2,
      'unit': 'kg',
      'expected_revision': 3,
    });
    expect(reviewBody.containsKey('ingredient_text'), isFalse);
    expect(reviewBody.containsKey('revision'), isFalse);

    await api.setShoppingItemStatus(
      itemId: 'item-1',
      status: KitchenShoppingItemStatus.purchased,
      expectedRevision: 4,
    );
    final statusBody = jsonDecode((client.lastRequest! as http.Request).body)
        as Map<String, dynamic>;
    expect(statusBody,
        <String, dynamic>{'status': 'purchased', 'expected_revision': 4});
  });

  test('completion sends caller-provided UUID idempotency key', () async {
    final client = _FakeClient((request) async => _ok(<String, dynamic>{
          'shopping_list': <String, dynamic>{
            'list_id': 'list-1',
            'status': 'completed',
            'completed_at': '2026-01-01T00:00:00Z',
            'inventory_change_count': 1,
          },
        }));
    final api =
        KitchenApi(httpClient: client, accessTokenProvider: () async => 'jwt');
    final result = await api.completeShoppingList(
      listId: 'list-1',
      idempotencyKey: '550e8400-e29b-41d4-a716-446655440000',
    );
    expect(result.status, 'completed');
    expect(client.lastRequest!.headers['Idempotency-Key'],
        '550e8400-e29b-41d4-a716-446655440000');
  });

  test('maps conflict without exposing response body', () async {
    final client = _FakeClient((request) async => http.Response(
          jsonEncode(<String, dynamic>{
            'status': 'error',
            'error': <String, dynamic>{
              'code': 'shopping_item_conflict',
              'message': 'secret SQL text'
            }
          }),
          409,
        ));
    final api =
        KitchenApi(httpClient: client, accessTokenProvider: () async => 'jwt');
    expect(
      () => api.setShoppingItemStatus(
          itemId: 'item-1',
          status: KitchenShoppingItemStatus.pending,
          expectedRevision: 4),
      throwsA(isA<KitchenApiException>()
          .having((error) => error.kind, 'kind', KitchenApiErrorKind.conflict)),
    );
  });

  test('maps not found and validation responses to typed safe errors',
      () async {
    for (final entry in <({int status, KitchenApiErrorKind kind})>[
      (status: 404, kind: KitchenApiErrorKind.notFound),
      (status: 422, kind: KitchenApiErrorKind.validation),
    ]) {
      final client =
          _FakeClient((request) async => http.Response('{}', entry.status));
      final api = KitchenApi(
          httpClient: client, accessTokenProvider: () async => 'jwt');
      await expectLater(
        api.setShoppingItemStatus(
          itemId: 'item-1',
          status: KitchenShoppingItemStatus.pending,
          expectedRevision: 0,
        ),
        throwsA(isA<KitchenApiException>()
            .having((error) => error.kind, 'kind', entry.kind)),
      );
    }
  });

  test('structured create sends only reviewed item fields and the draft key',
      () async {
    final client = _FakeClient((request) async => _ok(<String, dynamic>{
          'list_id': 'list-1',
          'status': 'active',
          'created': true,
          'replayed': false,
          'idempotency_key': '550e8400-e29b-41d4-a716-446655440000',
        }));
    final api =
        KitchenApi(httpClient: client, accessTokenProvider: () async => 'jwt');
    final result = await api.createShoppingList(
      sourceRecipeId: 'public:recipe-1',
      idempotencyKey: '550e8400-e29b-41d4-a716-446655440000',
      items: const <ShoppingReviewDraftItem>[
        ShoppingReviewDraftItem(
          localId: 'local-1',
          ingredientText: '2 kg potato',
          name: 'Potato',
          quantityInput: '2',
          quantity: 2,
          unit: 'kg',
        ),
      ],
    );
    expect(result.created, isTrue);
    final body = jsonDecode((client.lastRequest! as http.Request).body)
        as Map<String, dynamic>;
    expect(body['source_recipe_id'], 'public:recipe-1');
    expect(body['items'], <Map<String, dynamic>>[
      <String, dynamic>{
        'name': 'Potato',
        'ingredient_text': '2 kg potato',
        'quantity': 2,
        'unit': 'kg'
      },
    ]);
    expect(client.lastRequest!.headers['Idempotency-Key'],
        '550e8400-e29b-41d4-a716-446655440000');
    expect(body.containsKey('owner_id'), isFalse);
    expect((body['items'] as List).single.containsKey('revision'), isFalse);
  });

  test('create sends selected shopping items only', () async {
    final client = _FakeClient((request) async => _ok(<String, dynamic>{
          'list_id': 'list-1',
          'status': 'active',
          'created': true,
          'replayed': false,
          'idempotency_key': '550e8400-e29b-41d4-a716-446655440000',
        }));

    final api =
        KitchenApi(httpClient: client, accessTokenProvider: () async => 'jwt');

    await api.createShoppingList(
      sourceRecipeId: 'public:recipe-1',
      idempotencyKey: '550e8400-e29b-41d4-a716-446655440000',
      items: const <ShoppingReviewDraftItem>[
        ShoppingReviewDraftItem(
          localId: 'selected-item',
          ingredientText: '감자 2개',
          name: '감자',
          quantityInput: '',
          quantity: null,
          unit: null,
          selected: true,
        ),
        ShoppingReviewDraftItem(
          localId: 'available-item',
          ingredientText: '고추장 1큰술',
          name: '고추장',
          quantityInput: '',
          quantity: null,
          unit: null,
          selected: false,
        ),
      ],
    );

    final body = jsonDecode((client.lastRequest! as http.Request).body)
        as Map<String, dynamic>;

    expect(body['items'], <Map<String, dynamic>>[
      <String, dynamic>{
        'name': '감자',
        'ingredient_text': '감자 2개',
        'quantity': null,
        'unit': null,
      },
    ]);
  });

  test('create rejects a draft with no selected shopping items', () async {
    final client = _FakeClient((request) async => _ok(<String, dynamic>{}));

    final api =
        KitchenApi(httpClient: client, accessTokenProvider: () async => 'jwt');

    await expectLater(
      api.createShoppingList(
        sourceRecipeId: 'public:recipe-1',
        idempotencyKey: '550e8400-e29b-41d4-a716-446655440000',
        items: const <ShoppingReviewDraftItem>[
          ShoppingReviewDraftItem(
            localId: 'available-item',
            ingredientText: '고추장 1큰술',
            name: '고추장',
            quantityInput: '',
            quantity: null,
            unit: null,
            selected: false,
          ),
        ],
      ),
      throwsA(
        isA<KitchenApiException>().having(
          (error) => error.kind,
          'kind',
          KitchenApiErrorKind.badRequest,
        ),
      ),
    );

    expect(client.lastRequest, isNull);
  });
}
