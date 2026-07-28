import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/config/env.dart';
import '../domain/kitchen_models.dart';

class KitchenApi {
  KitchenApi({SupabaseClient? client})
      : _client = client ?? Supabase.instance.client;

  final SupabaseClient _client;

  Future<Session> _requireSession() async {
    final session = _client.auth.currentSession;
    if (session == null) {
      throw StateError('로그인이 필요합니다.');
    }
    return session;
  }

  Future<dynamic> _request({
    required String method,
    Map<String, String>? query,
    Map<String, dynamic>? body,
  }) async {
    final session = await _requireSession();
    final uri = Uri.parse('${Env.supabaseUrl}/functions/v1/recipe_api').replace(
      queryParameters: <String, String>{
        'type': 'kitchen',
        ...?query,
      },
    );

    final headers = <String, String>{
      'apikey': Env.supabaseAnonKey,
      'Authorization': 'Bearer ${session.accessToken}',
    };

    http.Response response;
    switch (method) {
      case 'GET':
        response = await http.get(uri, headers: headers);
        break;
      case 'POST':
        response = await http.post(
          uri,
          headers: <String, String>{
            ...headers,
            'Content-Type': 'application/json',
          },
          body: body == null ? null : jsonEncode(body),
        );
        break;
      case 'PATCH':
        response = await http.patch(
          uri,
          headers: <String, String>{
            ...headers,
            'Content-Type': 'application/json',
          },
          body: body == null ? null : jsonEncode(body),
        );
        break;
      case 'DELETE':
        response = await http.delete(uri, headers: headers);
        break;
      default:
        throw StateError('Unsupported method: $method');
    }

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw StateError('주방 API 요청에 실패했습니다.');
    }

    final payload = jsonDecode(response.body);
    if (payload is! Map<String, dynamic> || payload['status'] != 'ok') {
      throw StateError('주방 API 응답 형식이 올바르지 않습니다.');
    }

    return payload['data'];
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
  }) async {
    await _request(
      method: 'PATCH',
      query: <String, String>{
        'view': 'shopping-item',
        'id': id,
      },
      body: <String, dynamic>{'is_checked': isChecked},
    );
  }

  Future<void> completeShoppingList(String id) async {
    await _request(
      method: 'POST',
      query: <String, String>{
        'action': 'complete-shopping-list',
        'id': id,
      },
    );
  }

  Future<void> resetShoppingList(String id) async {
    await _request(
      method: 'POST',
      query: <String, String>{
        'action': 'reset-shopping-list',
        'id': id,
      },
    );
  }

  Future<int> archiveOldCompletedShoppingLists({
    int retentionDays = 30,
  }) async {
    final data = await _request(
      method: 'POST',
      query: <String, String>{
        'action': 'archive-old-completed-shopping-lists',
        'days': '$retentionDays',
      },
    );

    if (data is! Map<String, dynamic>) {
      return 0;
    }

    final archivedCount = data['archived_count'];
    if (archivedCount is int) {
      return archivedCount;
    }
    if (archivedCount is num) {
      return archivedCount.toInt();
    }
    return 0;
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
