import 'dart:convert';
import 'dart:math';

import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/config/env.dart';
import '../domain/kitchen_models.dart';
import '../domain/shopping_review_drafts.dart';

enum KitchenApiErrorKind {
  badRequest,
  unauthorized,
  notFound,
  conflict,
  validation,
  server,
}

class KitchenApiException implements Exception {
  const KitchenApiException({
    required this.kind,
    required this.statusCode,
    required this.message,
    this.code,
  });

  final KitchenApiErrorKind kind;
  final int statusCode;
  final String message;
  final String? code;

  @override
  String toString() => 'KitchenApiException($statusCode, $kind, $code)';
}

class KitchenShoppingListCompletion {
  const KitchenShoppingListCompletion({
    required this.listId,
    required this.status,
    this.completedAt,
    required this.inventoryChangeCount,
  });

  final String listId;
  final String status;
  final DateTime? completedAt;
  final int inventoryChangeCount;

  factory KitchenShoppingListCompletion.fromJson(Map<String, dynamic> json) {
    final listId = json['list_id'];
    final status = json['status'];
    final count = json['inventory_change_count'];
    if (listId is! String ||
        listId.isEmpty ||
        status is! String ||
        status.isEmpty ||
        count is! num ||
        count < 0) {
      throw const FormatException('Invalid shopping list completion response');
    }
    final completedAtValue = json['completed_at'];
    final completedAt = completedAtValue == null
        ? null
        : DateTime.tryParse(completedAtValue.toString());
    if (completedAtValue != null && completedAt == null) {
      throw const FormatException('Invalid shopping list completion timestamp');
    }
    return KitchenShoppingListCompletion(
      listId: listId,
      status: status,
      completedAt: completedAt,
      inventoryChangeCount: count.toInt(),
    );
  }
}

class KitchenShoppingListCreateResult {
  const KitchenShoppingListCreateResult({
    required this.listId,
    required this.status,
    required this.created,
    required this.replayed,
    required this.idempotencyKey,
  });

  final String listId;
  final String status;
  final bool created;
  final bool replayed;
  final String idempotencyKey;

  factory KitchenShoppingListCreateResult.fromJson(Map<String, dynamic> json) {
    final listId = json['list_id'];
    final status = json['status'];
    final created = json['created'];
    final replayed = json['replayed'];
    final key = json['idempotency_key'];
    if (listId is! String ||
        listId.isEmpty ||
        status is! String ||
        status.isEmpty ||
        created is! bool ||
        replayed is! bool ||
        key is! String ||
        key.isEmpty) {
      throw const FormatException('Invalid shopping list create response');
    }
    return KitchenShoppingListCreateResult(
      listId: listId,
      status: status,
      created: created,
      replayed: replayed,
      idempotencyKey: key,
    );
  }
}

class KitchenApi {
  KitchenApi({
    SupabaseClient? client,
    http.Client? httpClient,
    Future<String?> Function()? accessTokenProvider,
  })  : _client = client,
        _httpClient = httpClient ?? http.Client(),
        _accessTokenProvider = accessTokenProvider;

  final SupabaseClient? _client;
  final http.Client _httpClient;
  final Future<String?> Function()? _accessTokenProvider;

  Future<String> _requireAccessToken() async {
    final providedToken = await _accessTokenProvider?.call();
    if (providedToken != null && providedToken.trim().isNotEmpty) {
      return providedToken;
    }
    final session = (_client ?? Supabase.instance.client).auth.currentSession;
    if (session == null) {
      throw StateError('로그인이 필요합니다.');
    }
    return session.accessToken;
  }

  Future<dynamic> _request({
    required String method,
    Map<String, String>? query,
    Map<String, dynamic>? body,
    Map<String, String>? extraHeaders,
  }) async {
    final accessToken = await _requireAccessToken();
    final uri = Uri.parse('${Env.supabaseUrl}/functions/v1/recipe_api').replace(
      queryParameters: <String, String>{
        'type': 'kitchen',
        ...?query,
      },
    );

    final headers = <String, String>{
      'apikey': Env.supabaseAnonKey,
      'Authorization': 'Bearer $accessToken',
      ...?extraHeaders,
    };

    http.Response response;
    switch (method) {
      case 'GET':
        response = await _httpClient.get(uri, headers: headers);
        break;
      case 'POST':
        response = await _httpClient.post(
          uri,
          headers: <String, String>{
            ...headers,
            'Content-Type': 'application/json',
          },
          body: body == null ? null : jsonEncode(body),
        );
        break;
      case 'PATCH':
        response = await _httpClient.patch(
          uri,
          headers: <String, String>{
            ...headers,
            'Content-Type': 'application/json',
          },
          body: body == null ? null : jsonEncode(body),
        );
        break;
      case 'DELETE':
        response = await _httpClient.delete(uri, headers: headers);
        break;
      default:
        throw StateError('Unsupported method: $method');
    }

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw _apiException(response);
    }

    final payload = jsonDecode(response.body);
    if (payload is! Map<String, dynamic> || payload['status'] != 'ok') {
      throw const KitchenApiException(
        kind: KitchenApiErrorKind.server,
        statusCode: 502,
        message: '주방 API 응답 형식이 올바르지 않습니다.',
      );
    }

    return payload['data'];
  }

  KitchenApiException _apiException(http.Response response) {
    String? code;
    try {
      final payload = jsonDecode(response.body);
      if (payload is Map<String, dynamic> &&
          payload['error'] is Map<String, dynamic>) {
        final rawCode = (payload['error'] as Map<String, dynamic>)['code'];
        if (rawCode is String && rawCode.length <= 80) code = rawCode;
      }
    } catch (_) {
      // Never expose the response body to the app.
    }
    final kind = switch (response.statusCode) {
      400 => KitchenApiErrorKind.badRequest,
      401 => KitchenApiErrorKind.unauthorized,
      404 => KitchenApiErrorKind.notFound,
      409 => KitchenApiErrorKind.conflict,
      422 => KitchenApiErrorKind.validation,
      _ => KitchenApiErrorKind.server,
    };
    final message = switch (kind) {
      KitchenApiErrorKind.unauthorized => '로그인이 필요합니다.',
      KitchenApiErrorKind.notFound => '장보기 항목을 찾을 수 없습니다.',
      KitchenApiErrorKind.conflict => '장보기 항목이 다른 요청으로 변경되었습니다.',
      KitchenApiErrorKind.validation => '장보기 요청을 확인해 주세요.',
      KitchenApiErrorKind.badRequest => '장보기 요청 형식이 올바르지 않습니다.',
      KitchenApiErrorKind.server => '주방 API 요청에 실패했습니다.',
    };
    return KitchenApiException(
        kind: kind,
        statusCode: response.statusCode,
        message: message,
        code: code);
  }

  Future<List<KitchenIngredient>> listIngredients({String? query}) async {
    final data = await _request(
      method: 'GET',
      query: <String, String>{
        'view': 'ingredients',
        if (query != null && query.trim().isNotEmpty) 'q': query.trim(),
      },
    );

    if (data is! List) {
      return <KitchenIngredient>[];
    }

    return data
        .whereType<Map<String, dynamic>>()
        .map(KitchenIngredient.fromJson)
        .toList();
  }

  Future<KitchenIngredient> createIngredient({required String name}) async {
    final data = await _request(
      method: 'POST',
      query: const <String, String>{'view': 'ingredients'},
      body: <String, dynamic>{'name': name.trim()},
    );

    if (data is! Map<String, dynamic>) {
      throw StateError('재료 생성 응답이 올바르지 않습니다.');
    }

    return KitchenIngredient.fromJson(data);
  }

  Future<void> deleteIngredient(String id) async {
    await _request(
      method: 'DELETE',
      query: <String, String>{
        'view': 'ingredients',
        'id': id,
      },
    );
  }

  Future<List<KitchenShoppingList>> listShoppingLists({
    String status = 'active',
  }) async {
    final data = await _request(
      method: 'GET',
      query: <String, String>{
        'view': 'shopping-lists',
        'status': status,
      },
    );

    if (data is! List) {
      return <KitchenShoppingList>[];
    }

    return data
        .whereType<Map<String, dynamic>>()
        .map(KitchenShoppingList.fromJson)
        .toList();
  }

  Future<void> patchShoppingItem({
    required String id,
    required bool isChecked,
    required int expectedRevision,
  }) async {
    await setShoppingItemStatus(
      itemId: id,
      status: isChecked
          ? KitchenShoppingItemStatus.purchased
          : KitchenShoppingItemStatus.pending,
      expectedRevision: expectedRevision,
    );
  }

  Future<KitchenShoppingItem> reviewShoppingItem({
    required String itemId,
    required String name,
    double? quantity,
    String? unit,
    required int expectedRevision,
  }) async {
    final data = await _request(
      method: 'POST',
      query: <String, String>{
        'action': 'review-shopping-item',
        'id': itemId,
      },
      body: <String, dynamic>{
        'name': name,
        'quantity': quantity,
        'unit': unit,
        'expected_revision': expectedRevision,
      },
    );
    if (data is! Map<String, dynamic>) {
      throw const FormatException('Invalid shopping item response');
    }
    return KitchenShoppingItem.fromJson(data);
  }

  Future<KitchenShoppingItem> setShoppingItemStatus({
    required String itemId,
    required KitchenShoppingItemStatus status,
    required int expectedRevision,
  }) async {
    final data = await _request(
      method: 'POST',
      query: <String, String>{
        'action': 'set-shopping-item-status',
        'id': itemId,
      },
      body: <String, dynamic>{
        'status': status.value,
        'expected_revision': expectedRevision,
      },
    );
    if (data is! Map<String, dynamic>) {
      throw const FormatException('Invalid shopping item response');
    }
    return KitchenShoppingItem.fromJson(data);
  }

  Future<KitchenShoppingListCompletion> completeShoppingList({
    required String listId,
    required String idempotencyKey,
  }) async {
    final key = idempotencyKey.trim();
    if (!_isUuid(key)) {
      throw const KitchenApiException(
        kind: KitchenApiErrorKind.badRequest,
        statusCode: 400,
        message: 'Idempotency key is invalid.',
      );
    }
    final data = await _request(
      method: 'POST',
      query: <String, String>{'action': 'complete-shopping-list', 'id': listId},
      extraHeaders: <String, String>{'Idempotency-Key': key},
    );
    if (data is! Map<String, dynamic> ||
        data['shopping_list'] is! Map<String, dynamic>) {
      throw const FormatException('Invalid shopping list completion response');
    }
    return KitchenShoppingListCompletion.fromJson(
        data['shopping_list'] as Map<String, dynamic>);
  }

  Future<KitchenShoppingListCreateResult> createShoppingList({
    required String sourceRecipeId,
    required List<ShoppingReviewDraftItem> items,
    required String idempotencyKey,
  }) async {
    final key = idempotencyKey.trim();
    if (!_isUuid(key)) {
      throw const KitchenApiException(
        kind: KitchenApiErrorKind.badRequest,
        statusCode: 400,
        message: 'Idempotency key is invalid.',
      );
    }
    final data = await _request(
      method: 'POST',
      query: const <String, String>{'action': 'create-shopping-from-recipe'},
      extraHeaders: <String, String>{'Idempotency-Key': key},
      body: <String, dynamic>{
        'source_recipe_id': sourceRecipeId,
        'items': items
            .map((item) => <String, dynamic>{
                  'name': item.name.trim(),
                  'ingredient_text': item.ingredientText,
                  'quantity': item.quantity,
                  'unit': item.unit,
                })
            .toList(),
      },
    );
    if (data is! Map<String, dynamic>) {
      throw const FormatException('Invalid shopping list create response');
    }
    final result = KitchenShoppingListCreateResult.fromJson(data);
    if (result.idempotencyKey != key || (!result.created && !result.replayed)) {
      throw const FormatException('Invalid shopping list create response');
    }
    return result;
  }

  static bool _isUuid(String value) => RegExp(
          r'^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
          caseSensitive: false)
      .hasMatch(value);

  static String newIdempotencyKey() {
    final random = Random.secure();
    final bytes = List<int>.generate(16, (_) => random.nextInt(256));
    bytes[6] = (bytes[6] & 0x0f) | 0x40;
    bytes[8] = (bytes[8] & 0x3f) | 0x80;
    final hex =
        bytes.map((value) => value.toRadixString(16).padLeft(2, '0')).join();
    return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-${hex.substring(12, 16)}-${hex.substring(16, 20)}-${hex.substring(20)}';
  }

  Future<List<KitchenCookSession>> listCookSessions() async {
    final data = await _request(
      method: 'GET',
      query: const <String, String>{
        'view': 'cook-sessions',
      },
    );

    if (data is! List) {
      return <KitchenCookSession>[];
    }

    return data
        .whereType<Map<String, dynamic>>()
        .map(KitchenCookSession.fromJson)
        .toList();
  }

  Future<void> completeCook({
    required String recipeType,
    required String recipeId,
    required String recipeTitle,
    int? rating,
    bool? liked,
    String? note,
  }) async {
    await _request(
      method: 'POST',
      query: const <String, String>{
        'action': 'complete-cook',
      },
      body: <String, dynamic>{
        'recipe_type': recipeType,
        'recipe_id': recipeId,
        'recipe_title': recipeTitle,
        if (rating != null) 'rating': rating,
        if (liked != null) 'liked': liked,
        if (note != null && note.trim().isNotEmpty) 'note': note.trim(),
      },
    );
  }
}
