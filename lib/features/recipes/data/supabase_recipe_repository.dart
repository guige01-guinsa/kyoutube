import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/config/env.dart';
import '../domain/bookmarked_recipe.dart';
import '../domain/recipe.dart';
import 'recipe_repository.dart';

class SupabaseRecipeRepository implements RecipeRepository {
  SupabaseRecipeRepository({SupabaseClient? client, http.Client? httpClient})
      : _client = client ?? Supabase.instance.client,
        _httpClient = httpClient ?? http.Client();

  final SupabaseClient _client;
  final http.Client _httpClient;

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
          'role': 'user',
        },
        onConflict: 'id',
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
    );

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
  Future<int> createKitchenShoppingFromRecipe({
    required String recipeType,
    required Recipe recipe,
  }) async {
    final session = await _requireSession();
    final uri = Uri.parse('${Env.supabaseUrl}/functions/v1/recipe_api').replace(
      queryParameters: const <String, String>{
        'type': 'kitchen',
        'action': 'create-shopping-from-recipe',
      },
    );

    final response = await http.post(
      uri,
      headers: <String, String>{
        'Content-Type': 'application/json',
        'apikey': Env.supabaseAnonKey,
        'Authorization': 'Bearer ${session.accessToken}',
      },
      body: jsonEncode(<String, dynamic>{
        'recipe_type': recipeType,
        'recipe_id': recipe.id,
        'recipe_title': recipe.title,
        'required_ingredients': recipe.ingredients,
      }),
    );

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw StateError('장보기 목록 생성에 실패했습니다.');
    }

    final payload = jsonDecode(response.body);
    if (payload is! Map<String, dynamic> || payload['status'] != 'ok') {
      throw StateError('장보기 목록 생성에 실패했습니다.');
    }

    final data = payload['data'];
    if (data is! Map<String, dynamic>) {
      return 0;
    }

    final missingCount = data['missing_count'];
    if (missingCount is int) {
      return missingCount;
    }
    if (missingCount is num) {
      return missingCount.toInt();
    }
    return 0;
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
            'notes': notes,
            'ingredients': source.ingredients,
            'steps': source.steps,
            'visibility': 'private',
          },
        )
        .select('id,title,notes,ingredients,steps,visibility')
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
  }) {
    return <String, dynamic>{
      'title': title,
      'summary': summary,
      'ingredients': ingredients,
      'steps': steps,
      'tips': tips,
      'image_path': imagePath,
      'youtube_url': youtubeUrl,
      'is_published': true,
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
  }) async {
    final session = _client.auth.currentSession;
    if (session == null) {
      throw StateError('로그인이 필요합니다.');
    }

    final response = await http.post(
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
        ),
      ),
    );

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

    final response = await http.delete(
      Uri.parse('${Env.supabaseUrl}/functions/v1/recipe_api/$id?type=creator'),
      headers: <String, String>{
        'apikey': Env.supabaseAnonKey,
        'Authorization': 'Bearer ${session.accessToken}',
      },
    );

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
  Future<bool> isBookmarked({
    required String recipeType,
    required String recipeId,
  }) async {
    final userId = await _requireUserId();

    final row = await _client
        .from('bookmarks')
        .select('id')
        .eq('user_id', userId)
        .eq('recipe_type', recipeType)
        .eq('recipe_id', recipeId)
        .maybeSingle();

    return row != null;
  }

  @override
  Future<void> addBookmark({
    required String recipeType,
    required String recipeId,
  }) async {
    final userId = await _requireUserId();

    await _client.from('bookmarks').upsert(
      <String, dynamic>{
        'user_id': userId,
        'recipe_type': recipeType,
        'recipe_id': recipeId,
      },
      onConflict: 'user_id,recipe_type,recipe_id',
    );
  }

  @override
  Future<void> removeBookmark({
    required String recipeType,
    required String recipeId,
  }) async {
    final userId = await _requireUserId();

    await _client
        .from('bookmarks')
        .delete()
        .eq('user_id', userId)
        .eq('recipe_type', recipeType)
        .eq('recipe_id', recipeId);
  }

  @override
  Future<List<BookmarkedRecipe>> listBookmarkedRecipes() async {
    final userId = await _requireUserId();

    final rows = await _client
        .from('bookmarks')
        .select('recipe_type,recipe_id,created_at')
        .eq('user_id', userId)
        .order('created_at', ascending: false);

    final bookmarks = rows as List<dynamic>;
    final items = <BookmarkedRecipe>[];

    for (final dynamic row in bookmarks) {
      final map = row as Map<String, dynamic>;
      final recipeType = map['recipe_type'] as String? ?? '';
      final recipeId = map['recipe_id'] as String? ?? '';

      if (recipeType.isEmpty || recipeId.isEmpty) {
        continue;
      }

      Recipe? recipe;
      switch (recipeType) {
        case 'public':
          recipe = await getRecipeById(recipeId);
          break;
        case 'creator':
          recipe = await getCreatorRecipeById(recipeId);
          break;
        case 'user':
          recipe = await getSubscriberRecipeById(recipeId);
          break;
      }

      if (recipe != null) {
        items.add(BookmarkedRecipe(recipeType: recipeType, recipe: recipe));
      }
    }

    return items;
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
    );

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
        .select('id,title,notes,ingredients,steps,visibility')
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
    final requestedLimit = normalizedSearch.isEmpty ? '30' : '5';
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
    );

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

    return rows.map((dynamic row) {
      final map = row as Map<String, dynamic>;
      return _mapRecipe(map);
    }).toList();
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
        .select('id,title,notes,ingredients,steps,visibility')
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
  }) async {
    final session = _client.auth.currentSession;
    if (session == null) {
      throw StateError('로그인이 필요합니다.');
    }

    final response = await http.patch(
      Uri.parse('${Env.supabaseUrl}/functions/v1/recipe_api/$id?type=creator'),
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
        ),
      ),
    );

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
    );

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
    );

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
        .select('id,title,notes,ingredients,steps,visibility')
        .single();

    return _mapRecipe(row);
  }
}
