import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/config/env.dart';
import '../domain/recipe.dart';
import '../domain/recipe_search_exclusion.dart';
import 'recipe_repository.dart';

class SupabaseRecipeRepository implements RecipeRepository {
  static const Duration _requestTimeout = Duration(seconds: 20);

  SupabaseRecipeRepository({SupabaseClient? client, http.Client? httpClient})
      : _client = client ?? Supabase.instance.client,
        _httpClient = httpClient ?? http.Client(),
        _ownsHttpClient = httpClient == null;

  final SupabaseClient _client;
  final http.Client _httpClient;
  final bool _ownsHttpClient;

  void close() {
    if (_ownsHttpClient) {
      _httpClient.close();
    }
  }

  Future<Session> _requireSession() async {
    final session = _client.auth.currentSession;
    if (session == null) {
      throw StateError('로그인이 필요합니다.');
    }
    return session;
  }

  Future<String> _requireUserId() async {
    final user = _client.auth.currentUser;
    if (user == null) {
      throw StateError('로그인이 필요합니다.');
    }

    await _ensureOwnProfile(user.id);
    return user.id;
  }

  Future<void> _ensureOwnProfile(String userId) async {
    try {
      await _client.from('profiles').upsert(
        <String, dynamic>{
          'id': userId,
        },
        onConflict: 'id',
        ignoreDuplicates: true,
        defaultToNull: false,
      );
    } on PostgrestException catch (error) {
      if (error.code == '23503' ||
          error.message.contains('profiles_id_fkey') ||
          error.message.contains('users')) {
        await _client.auth.signOut();
        throw StateError('로컬 인증 세션이 만료되었습니다. 다시 로그인해 주세요.');
      }

      rethrow;
    }
  }

  Recipe _mapRecipe(Map<String, dynamic> map) {
    return Recipe(
      id: map['id'] as String,
      title: map['title'] as String,
      summary: map['summary'] as String?,
      tips: map['tips'] as String?,
      ingredients: (map['ingredients'] as List<dynamic>?)
              ?.map((dynamic e) => e.toString())
              .toList() ??
          const <String>[],
      steps: (map['steps'] as List<dynamic>?)
              ?.map((dynamic e) => e.toString())
              .toList() ??
          const <String>[],
      imageUrl: (map['image_url'] ?? map['image_path']) as String?,
      youtubeUrl: map['youtube_url'] as String?,
      notes: map['notes'] as String?,
      visibility: map['visibility'] as String?,
      sourceType: map['source_type'] as String?,
      contentStyles: map['content_styles'] is Map
          ? Map<String, dynamic>.from(map['content_styles'] as Map)
          : const <String, dynamic>{},
    );
  }

  @override
  Future<Map<String, int>> getKitchenSummary() async {
    final session = await _requireSession();
    final uri = Uri.parse('${Env.supabaseUrl}/functions/v1/recipe_api').replace(
      queryParameters: const <String, String>{
        'type': 'kitchen',
        'view': 'summary',
      },
    );

    final response = await _httpClient.get(
      uri,
      headers: <String, String>{
        'apikey': Env.supabaseAnonKey,
        'Authorization': 'Bearer ${session.accessToken}',
      },
    ).timeout(_requestTimeout);

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw StateError('주방 요약 정보를 불러오지 못했습니다.');
    }

    final payload = jsonDecode(response.body);
    if (payload is! Map<String, dynamic> || payload['status'] != 'ok') {
      throw StateError('주방 요약 정보를 불러오지 못했습니다.');
    }

    final data = payload['data'];
    if (data is! Map<String, dynamic>) {
      return const <String, int>{};
    }

    int parseInt(dynamic value) {
      if (value is int) {
        return value;
      }
      if (value is num) {
        return value.toInt();
      }
      return 0;
    }

    return <String, int>{
      'ingredient_count': parseInt(data['ingredient_count']),
      'expiring_soon_count': parseInt(data['expiring_soon_count']),
      'active_shopping_list_count':
          parseInt(data['active_shopping_list_count']),
      'open_shopping_item_count': parseInt(data['open_shopping_item_count']),
      'recent_cook_count_7d': parseInt(data['recent_cook_count_7d']),
    };
  }

  @override
  Future<Recipe> createSubscriberRecipeFromPublic({
    required Recipe source,
    String? notes,
  }) async {
    final userId = await _requireUserId();

    final row = await _client
        .from('recipes_user')
        .insert(
          <String, dynamic>{
            'owner_id': userId,
            'title': source.title,
            'summary': source.summary,
            'notes': notes,
            'image_url': source.imageUrl,
            'youtube_url': source.youtubeUrl,
            'source_type': 'public_import',
            'ingredients': source.ingredients,
            'steps': source.steps,
            'visibility': 'private',
          },
        )
        .select(
            'id,title,summary,notes,image_url,youtube_url,source_type,ingredients,steps,visibility')
        .single();

    return _mapRecipe(row);
  }

  Map<String, dynamic> _buildCreatorPayload({
    required String title,
    String? summary,
    required List<String> ingredients,
    required List<String> steps,
    String? tips,
    String? imagePath,
    String? youtubeUrl,
    Map<String, dynamic> contentStyles = const <String, dynamic>{},
  }) {
    return <String, dynamic>{
      'title': title,
      'summary': summary,
      'ingredients': ingredients,
      'steps': steps,
      'tips': tips,
      'image_path': imagePath,
      'youtube_url': youtubeUrl,
      'is_published': false,
      'content_styles': contentStyles,
    };
  }

  @override
  Future<Recipe> createCreatorRecipe({
    required String title,
    String? summary,
    required List<String> ingredients,
    required List<String> steps,
    String? tips,
    String? imagePath,
    String? youtubeUrl,
    Map<String, dynamic> contentStyles = const <String, dynamic>{},
  }) async {
    final session = _client.auth.currentSession;
    if (session == null) {
      throw StateError('로그인이 필요합니다.');
    }

    final response = await _httpClient
        .post(
          Uri.parse('${Env.supabaseUrl}/functions/v1/recipe_api?type=creator'),
          headers: <String, String>{
            'Content-Type': 'application/json',
            'apikey': Env.supabaseAnonKey,
            'Authorization': 'Bearer ${session.accessToken}',
          },
          body: jsonEncode(
            _buildCreatorPayload(
              title: title,
              summary: summary,
              ingredients: ingredients,
              steps: steps,
              tips: tips,
              imagePath: imagePath,
              youtubeUrl: youtubeUrl,
              contentStyles: contentStyles,
            ),
          ),
        )
        .timeout(_requestTimeout);

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw StateError('크리에이터 레시피를 저장하지 못했습니다.');
    }

    final payload = jsonDecode(response.body);
    if (payload is! Map<String, dynamic> || payload['status'] != 'ok') {
      throw StateError('크리에이터 레시피를 저장하지 못했습니다.');
    }

    final data = payload['data'];
    if (data is! Map<String, dynamic>) {
      throw StateError('저장 결과 형식이 올바르지 않습니다.');
    }

    return _mapRecipe(data);
  }

  @override
  Future<void> deleteCreatorRecipe(String id) async {
    final session = _client.auth.currentSession;
    if (session == null) {
      throw StateError('로그인이 필요합니다.');
    }

    final response = await _httpClient.delete(
      Uri.parse('${Env.supabaseUrl}/functions/v1/recipe_api/$id?type=creator'),
      headers: <String, String>{
        'apikey': Env.supabaseAnonKey,
        'Authorization': 'Bearer ${session.accessToken}',
      },
    ).timeout(_requestTimeout);

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw StateError('크리에이터 레시피를 삭제하지 못했습니다.');
    }
  }

  @override
  Future<void> deleteSubscriberRecipe(String id) async {
    await _requireUserId();

    await _client.from('recipes_user').delete().eq('id', id);
  }

  @override
  Future<Recipe> promoteSubscriberRecipeToCreator({
    required String id,
  }) async {
    await _requireUserId();

    final response = await _client.rpc(
      'promote_subscriber_recipe_to_creator',
      params: <String, dynamic>{
        'p_recipe_user_id': id,
        'p_delete_source': false,
        'p_include_summary': true,
        'p_include_youtube_url': true,
        'p_include_image_url': true,
        'p_include_notes_as_tips': true,
      },
    );

    final dynamic raw = response;

    final Map<String, dynamic> row;

    if (raw is List<dynamic> && raw.isNotEmpty && raw.first is Map) {
      row = Map<String, dynamic>.from(raw.first as Map);
    } else if (raw is Map) {
      row = Map<String, dynamic>.from(raw);
    } else {
      throw StateError('편집 가능한 내 레시피를 만들지 못했습니다.');
    }

    return _mapRecipe(row);
  }

  @override
  Future<List<RecipeSearchExclusion>> listRecipeSearchExclusions() async {
    final userId = await _requireUserId();

    final rows = await _client
        .from('recipe_search_exclusions')
        .select()
        .eq('user_id', userId)
        .neq('status', 'resolved')
        .order('created_at', ascending: false);

    return (rows as List<dynamic>)
        .whereType<Map<String, dynamic>>()
        .map(RecipeSearchExclusion.fromJson)
        .toList(growable: false);
  }

  @override
  Future<Set<String>> listExcludedRecipeSourceKeys() async {
    final userId = await _requireUserId();
    final rows = await _client
        .from('recipe_search_exclusions')
        .select('source_type,source_id')
        .eq('user_id', userId);

    return (rows as List<dynamic>)
        .whereType<Map<String, dynamic>>()
        .map((row) => '${row['source_type']}:${row['source_id']}')
        .toSet();
  }

  @override
  Future<void> excludeRecipeFromSearch({
    required String sourceType,
    required String sourceId,
    required String title,
    String? summary,
    List<String> ingredients = const <String>[],
    List<String> steps = const <String>[],
    String? imageUrl,
    String? youtubeUrl,
    List<String> reasonCodes = const <String>['user_hidden'],
    String status = 'hidden',
  }) async {
    final userId = await _requireUserId();
    await _client.from('recipe_search_exclusions').upsert(
      <String, dynamic>{
        'user_id': userId,
        'source_type': sourceType,
        'source_id': sourceId,
        'title': title,
        'summary': summary,
        'ingredients': ingredients,
        'steps': steps,
        'image_url': imageUrl,
        'youtube_url': youtubeUrl,
        'reason_codes': reasonCodes,
        'status': status,
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      },
      onConflict: 'user_id,source_type,source_id',
    );
  }

  @override
  Future<void> resolveRecipeSearchExclusion(String id) async {
    final userId = await _requireUserId();
    await _client
        .from('recipe_search_exclusions')
        .update(<String, dynamic>{
          'status': 'resolved',
          'updated_at': DateTime.now().toUtc().toIso8601String(),
        })
        .eq('id', id)
        .eq('user_id', userId);
  }

  @override
  Future<void> deleteRecipeSearchExclusion(String id) async {
    final userId = await _requireUserId();
    await _client
        .from('recipe_search_exclusions')
        .delete()
        .eq('id', id)
        .eq('user_id', userId);
  }

  @override
  Future<Recipe?> getCreatorRecipeById(String id) async {
    final session = _client.auth.currentSession;
    if (session == null) {
      throw StateError('로그인이 필요합니다.');
    }

    final response = await _httpClient.get(
      Uri.parse('${Env.supabaseUrl}/functions/v1/recipe_api/$id?type=creator'),
      headers: <String, String>{
        'apikey': Env.supabaseAnonKey,
        'Authorization': 'Bearer ${session.accessToken}',
      },
    ).timeout(_requestTimeout);

    if (response.statusCode == 404) {
      return null;
    }

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw StateError('크리에이터 레시피를 불러오지 못했습니다.');
    }

    final payload = jsonDecode(response.body);
    if (payload is! Map<String, dynamic> || payload['status'] != 'ok') {
      throw StateError('크리에이터 레시피를 불러오지 못했습니다.');
    }

    final data = payload['data'];
    if (data is! Map<String, dynamic>) {
      return null;
    }

    return _mapRecipe(data);
  }

  @override
  Future<Recipe?> getSubscriberRecipeById(String id) async {
    await _requireUserId();

    final row = await _client
        .from('recipes_user')
        .select(
            'id,title,summary,notes,image_url,youtube_url,source_type,ingredients,steps,visibility')
        .eq('id', id)
        .maybeSingle();

    if (row == null) {
      return null;
    }

    return _mapRecipe(row);
  }

  @override
  Future<List<Recipe>> listPublicRecipes({
    String? search,
    bool useAiSearch = false,
  }) async {
    final normalizedSearch = (search ?? '').trim();
    const requestedLimit = '10';
    final uri = Uri.parse('${Env.supabaseUrl}/functions/v1/recipe_api').replace(
      queryParameters: <String, String>{
        'type': 'public',
        'limit': requestedLimit,
        'offset': '0',
        'search_mode': useAiSearch ? 'ai' : 'keyword',
        if (normalizedSearch.isNotEmpty) 'search': normalizedSearch,
      },
    );

    final response = await _httpClient.get(
      uri,
      headers: <String, String>{
        'apikey': Env.supabaseAnonKey,
        'Authorization': 'Bearer ${Env.supabaseAnonKey}',
      },
    ).timeout(_requestTimeout);

    if (response.statusCode < 200 || response.statusCode >= 300) {
      _logPublicRecipeDiagnostics(statusCode: response.statusCode);
      throw StateError('공개 레시피를 불러오지 못했습니다.');
    }

    final payload = jsonDecode(response.body);
    if (payload is! Map<String, dynamic> || payload['status'] != 'ok') {
      throw StateError('공개 레시피를 불러오지 못했습니다.');
    }

    final rows = payload['data'];
    if (rows is! List<dynamic>) {
      _logPublicRecipeDiagnostics(statusCode: response.statusCode);
      throw StateError('공개 레시피 응답 형식이 올바르지 않습니다.');
    }

    _logPublicRecipeDiagnostics(
      statusCode: response.statusCode,
      dataCount: rows.length,
    );

    return rows
        .map((dynamic row) {
          final map = row as Map<String, dynamic>;
          return _mapRecipe(map);
        })
        .where((recipe) => (recipe.imageUrl ?? '').trim().isNotEmpty)
        .take(10)
        .toList();
  }

  void _logPublicRecipeDiagnostics({
    required int statusCode,
    int? dataCount,
  }) {
    if (!kReleaseMode) {
      debugPrint(
        'recipe_api public list status=$statusCode '
        'data-count=${dataCount ?? 'unavailable'}',
      );
    }
  }

  @override
  Future<List<Recipe>> listSubscriberRecipes() async {
    final userId = await _requireUserId();

    final rows = await _client
        .from('recipes_user')
        .select(
            'id,title,summary,notes,image_url,youtube_url,source_type,ingredients,steps,visibility')
        .eq('owner_id', userId)
        .order('created_at', ascending: false)
        .limit(50);

    return (rows as List<dynamic>).map((dynamic row) {
      final map = row as Map<String, dynamic>;
      return _mapRecipe(map);
    }).toList();
  }

  @override
  Future<Recipe> updateCreatorRecipe({
    required String id,
    required String title,
    String? summary,
    required List<String> ingredients,
    required List<String> steps,
    String? tips,
    String? imagePath,
    String? youtubeUrl,
    Map<String, dynamic> contentStyles = const <String, dynamic>{},
  }) async {
    final session = _client.auth.currentSession;
    if (session == null) {
      throw StateError('로그인이 필요합니다.');
    }

    final response = await _httpClient
        .patch(
          Uri.parse(
              '${Env.supabaseUrl}/functions/v1/recipe_api/$id?type=creator'),
          headers: <String, String>{
            'Content-Type': 'application/json',
            'apikey': Env.supabaseAnonKey,
            'Authorization': 'Bearer ${session.accessToken}',
          },
          body: jsonEncode(
            _buildCreatorPayload(
              title: title,
              summary: summary,
              ingredients: ingredients,
              steps: steps,
              tips: tips,
              imagePath: imagePath,
              youtubeUrl: youtubeUrl,
              contentStyles: contentStyles,
            ),
          ),
        )
        .timeout(_requestTimeout);

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw StateError('크리에이터 레시피를 수정하지 못했습니다.');
    }

    final payload = jsonDecode(response.body);
    if (payload is! Map<String, dynamic> || payload['status'] != 'ok') {
      throw StateError('크리에이터 레시피를 수정하지 못했습니다.');
    }

    final data = payload['data'];
    if (data is! Map<String, dynamic>) {
      throw StateError('수정 결과 형식이 올바르지 않습니다.');
    }

    return _mapRecipe(data);
  }

  @override
  Future<List<Recipe>> listCreatorRecipes({String? search}) async {
    final session = _client.auth.currentSession;
    if (session == null) {
      throw StateError('로그인이 필요합니다.');
    }

    final normalizedSearch = (search ?? '').trim();
    final uri = Uri.parse('${Env.supabaseUrl}/functions/v1/recipe_api').replace(
      queryParameters: <String, String>{
        'type': 'creator',
        'limit': '30',
        'offset': '0',
        if (normalizedSearch.isNotEmpty) 'search': normalizedSearch,
      },
    );

    final response = await _httpClient.get(
      uri,
      headers: <String, String>{
        'apikey': Env.supabaseAnonKey,
        'Authorization': 'Bearer ${session.accessToken}',
      },
    ).timeout(_requestTimeout);

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw StateError('크리에이터 레시피를 불러오지 못했습니다.');
    }

    final payload = jsonDecode(response.body);
    if (payload is! Map<String, dynamic> || payload['status'] != 'ok') {
      throw StateError('크리에이터 레시피를 불러오지 못했습니다.');
    }

    final rows = payload['data'];
    if (rows is! List<dynamic>) {
      return const <Recipe>[];
    }

    return rows.map((dynamic row) {
      final map = row as Map<String, dynamic>;
      return _mapRecipe(map);
    }).toList();
  }

  @override
  Future<Recipe?> getRecipeById(String id) async {
    final uri = Uri.parse(
      '${Env.supabaseUrl}/functions/v1/recipe_api/${Uri.encodeComponent(id)}',
    ).replace(
      queryParameters: const <String, String>{'type': 'public'},
    );
    final response = await _httpClient.get(
      uri,
      headers: <String, String>{
        'apikey': Env.supabaseAnonKey,
        'Authorization': 'Bearer ${Env.supabaseAnonKey}',
      },
    ).timeout(_requestTimeout);

    _logPublicRecipeDetailDiagnostics(statusCode: response.statusCode);
    if (response.statusCode == 404) {
      return null;
    }

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw StateError('공개 레시피 상세를 불러오지 못했습니다.');
    }

    final payload = jsonDecode(response.body);
    if (payload is! Map<String, dynamic> || payload['status'] != 'ok') {
      throw StateError('공개 레시피 상세를 불러오지 못했습니다.');
    }

    final data = payload['data'];
    if (data is! Map<String, dynamic>) {
      throw StateError('공개 레시피 상세 응답 형식이 올바르지 않습니다.');
    }

    return _mapRecipe(data);
  }

  void _logPublicRecipeDetailDiagnostics({required int statusCode}) {
    if (!kReleaseMode) {
      debugPrint('recipe_api public detail status=$statusCode');
    }
  }

  @override
  Future<Recipe> updateSubscriberRecipeNotes({
    required String id,
    required String notes,
  }) async {
    await _requireUserId();

    final row = await _client
        .from('recipes_user')
        .update(<String, dynamic>{
          'notes': notes.trim().isEmpty ? null : notes.trim(),
          'updated_at': DateTime.now().toIso8601String(),
        })
        .eq('id', id)
        .select(
            'id,title,summary,notes,image_url,youtube_url,source_type,ingredients,steps,visibility')
        .single();

    return _mapRecipe(row);
  }
}
