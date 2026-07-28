import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/config/env.dart';
import '../domain/bookmarked_recipe.dart';
import '../domain/recipe.dart';
import '../domain/youtube_metadata.dart';
import 'recipe_repository.dart';

class SupabaseRecipeRepository implements RecipeRepository {
  SupabaseRecipeRepository({SupabaseClient? client})
      : _client = client ?? Supabase.instance.client;

  final SupabaseClient _client;
  static const int _defaultPublicListLimit = 30;
  static const int _searchPublicFetchLimit = 100;
  static const Duration _httpTimeout = Duration(seconds: 12);
  static const int _maxGetAttempts = 3;
  static const List<Duration> _retryDelays = <Duration>[
    Duration(milliseconds: 450),
    Duration(milliseconds: 1200),
  ];

  Future<Session> _requireSession() async {
    final current = _client.auth.currentSession;
    if (current != null) {
      return current;
    }

    try {
      final refreshed = await _client.auth.refreshSession();
      final session = refreshed.session;
      if (session != null) {
        return session;
      }
    } catch (_) {
      // Fall through to a user-facing auth error.
    }

    throw StateError('로그인이 필요합니다.');
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
        throw StateError('프로필 동기화에 실패했습니다.');
      }

      rethrow;
    }
  }

  Future<http.Response> _getWithRetry(
    Uri uri, {
    required Map<String, String> headers,
  }) async {
    Object? lastError;

    for (var attempt = 1; attempt <= _maxGetAttempts; attempt++) {
      try {
        final response = await http
            .get(uri, headers: headers)
            .timeout(_httpTimeout);
        if (_isRetryableStatus(response.statusCode) && attempt < _maxGetAttempts) {
          await Future<void>.delayed(_retryDelays[attempt - 1]);
          continue;
        }
        return response;
      } on TimeoutException catch (error) {
        lastError = error;
        if (attempt >= _maxGetAttempts) {
          rethrow;
        }
        await Future<void>.delayed(_retryDelays[attempt - 1]);
      } on SocketException catch (error) {
        lastError = error;
        if (attempt >= _maxGetAttempts) {
          rethrow;
        }
        await Future<void>.delayed(_retryDelays[attempt - 1]);
      } on http.ClientException catch (error) {
        lastError = error;
        if (attempt >= _maxGetAttempts) {
          rethrow;
        }
        await Future<void>.delayed(_retryDelays[attempt - 1]);
      }
    }

    throw lastError ?? StateError('네트워크 요청에 실패했습니다.');
  }

  bool _isRetryableStatus(int statusCode) {
    return statusCode == 408 ||
        statusCode == 429 ||
        statusCode == 500 ||
        statusCode == 502 ||
        statusCode == 503 ||
        statusCode == 504;
  }

  String _readRequiredString(Map<String, dynamic> map, String key) {
    final value = map[key];
    if (value == null) {
      throw StateError('missing_field:$key');
    }

    final normalized = value.toString().trim();
    if (normalized.isEmpty) {
      throw StateError('empty_field:$key');
    }

    return normalized;
  }

  String? _readOptionalString(Map<String, dynamic> map, String key) {
    final value = map[key];
    if (value == null) {
      return null;
    }

    final normalized = value.toString().trim();
    return normalized.isEmpty ? null : normalized;
  }

  List<String> _readStringList(Map<String, dynamic> map, String key) {
    final value = map[key];
    if (value is! List) {
      return const <String>[];
    }

    return value.map((dynamic e) => e.toString()).toList(growable: false);
  }

  Recipe _mapRecipe(Map<String, dynamic> map) {
    return Recipe(
      id: _readRequiredString(map, 'id'),
      title: _readRequiredString(map, 'title'),
      summary: _readOptionalString(map, 'summary'),
      tips: _readOptionalString(map, 'tips'),
      ingredients: _readStringList(map, 'ingredients'),
      steps: _readStringList(map, 'steps'),
      imageUrl: _readOptionalString(map, 'image_url') ??
          _readOptionalString(map, 'image_path'),
      youtubeUrl: _readOptionalString(map, 'youtube_url'),
      notes: _readOptionalString(map, 'notes'),
      visibility: _readOptionalString(map, 'visibility'),
      sourceType: _readOptionalString(map, 'source_type'),
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

    final response = await http.get(
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
      'active_shopping_list_count': parseInt(data['active_shopping_list_count']),
      'open_shopping_item_count': parseInt(data['open_shopping_item_count']),
      'recent_cook_count_7d': parseInt(data['recent_cook_count_7d']),
    };
  }

  @override
  Future<KitchenShoppingCreateResult> createKitchenShoppingFromRecipe({
    required String recipeType,
    required Recipe recipe,
  }) async {
    final uri = Uri.parse('${Env.supabaseUrl}/functions/v1/recipe_api').replace(
      queryParameters: const <String, String>{
        'type': 'kitchen',
        'action': 'create-shopping-from-recipe',
      },
    );

    Future<http.Response> sendWithToken(String accessToken) {
      return http.post(
        uri,
        headers: <String, String>{
          'Content-Type': 'application/json',
          'apikey': Env.supabaseAnonKey,
          'Authorization': 'Bearer $accessToken',
        },
        body: jsonEncode(<String, dynamic>{
          'recipe_type': recipeType,
          'recipe_id': recipe.id,
          'recipe_title': recipe.title,
          'required_ingredients': recipe.ingredients,
        }),
      );
    }

    var session = await _requireSession();
    var response = await sendWithToken(session.accessToken);

    if (response.statusCode == 401) {
      final bodyLower = response.body.toLowerCase();
      final canRetry = bodyLower.contains('invalid or expired access token') ||
          bodyLower.contains('invalid token') ||
          bodyLower.contains('expired');
      if (canRetry) {
        try {
          final refreshed = await _client.auth.refreshSession();
          final refreshedSession = refreshed.session;
          if (refreshedSession != null) {
            session = refreshedSession;
            response = await sendWithToken(session.accessToken);
          }
        } catch (_) {
          // Keep original unauthorized response handling below.
        }
      }
    }

    if (response.statusCode < 200 || response.statusCode >= 300) {
      String reason = '장보기 목록 생성에 실패했습니다.';
      try {
        final payload = jsonDecode(response.body);
        if (payload is Map<String, dynamic>) {
          final message = payload['message']?.toString().trim() ?? '';
          if (message.isNotEmpty) {
            reason = '$reason ($message)';
          }
        }
      } catch (_) {
        // Keep default reason when response body is not JSON.
      }
      throw StateError(reason);
    }

    final payload = jsonDecode(response.body);
    if (payload is! Map<String, dynamic> || payload['status'] != 'ok') {
      throw StateError('장보기 목록 생성에 실패했습니다.');
    }

    final data = payload['data'];
    if (data is! Map<String, dynamic>) {
      return const KitchenShoppingCreateResult(missingCount: 0);
    }

    int parseCount(dynamic value) {
      if (value is int) {
        return value;
      }
      if (value is num) {
        return value.toInt();
      }
      return 0;
    }

    final missingCount = data['missing_count'];
    return KitchenShoppingCreateResult(
      missingCount: parseCount(missingCount),
      reusedActiveList: data['reused_active_list'] == true,
      reopenedFromCompleted: data['reopened_from_completed'] == true,
      resetFromFullyChecked: data['reset_from_fully_checked'] == true,
      noMissingItems: data['no_missing_items'] == true,
    );
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
            'ingredients': source.ingredients,
            'steps': source.steps,
            'image_url': source.imageUrl,
            'youtube_url': source.youtubeUrl,
            'visibility': 'private',
            'source_type': RecipeSourceType.publicImport,
          },
        )
        .select(
          'id,title,summary,notes,ingredients,steps,image_url,youtube_url,visibility,source_type',
        )
        .single();

    return _mapRecipe(row);
  }

  @override
  Future<Recipe> createSubscriberRecipe({
    required String title,
    required List<String> ingredients,
    required List<String> steps,
    String? summary,
    String? notes,
    String? imageUrl,
    String? youtubeUrl,
    String? sourceType,
  }) async {
    final userId = await _requireUserId();

    final row = await _client
        .from('recipes_user')
        .insert(
          <String, dynamic>{
            'owner_id': userId,
            'title': title,
            'summary': summary?.trim().isEmpty ?? true ? null : summary!.trim(),
            'notes': notes?.trim().isEmpty ?? true ? null : notes!.trim(),
            'ingredients': ingredients,
            'steps': steps,
            'image_url':
                imageUrl?.trim().isEmpty ?? true ? null : imageUrl!.trim(),
            'youtube_url':
                youtubeUrl?.trim().isEmpty ?? true ? null : youtubeUrl!.trim(),
            'visibility': 'private',
            'source_type':
                sourceType?.trim().isEmpty ?? true ? RecipeSourceType.manual : sourceType!.trim(),
          },
        )
        .select(
          'id,title,summary,notes,ingredients,steps,image_url,youtube_url,visibility,source_type',
        )
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

    final response = await http.get(
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
  Future<RecipeYoutubeMetadata?> getCreatorRecipeYoutubeMetadata(String id) async {
    final session = _client.auth.currentSession;
    if (session == null) {
      return null;
    }

    await _requireUserId();

    final row = await _client
        .from('recipe_youtube_metadata')
        .select(
          'recipe_creator_id,youtube_url,youtube_video_id,title,channel_name,author_url,thumbnail_url,provider_name,fetched_at,last_status,last_error',
        )
        .eq('recipe_creator_id', id)
        .maybeSingle();

    if (row == null) {
      return null;
    }

    final metadata = RecipeYoutubeMetadata.fromJson(row);
    if (metadata == null) {
      return null;
    }

    return metadata;
  }

  @override
  Future<Recipe?> getSubscriberRecipeById(String id) async {
    await _requireUserId();

    final row = await _client
        .from('recipes_user')
        .select(
          'id,title,summary,notes,ingredients,steps,image_url,youtube_url,visibility,source_type',
        )
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
    final requestedLimit = normalizedSearch.isEmpty
        ? _defaultPublicListLimit
        : _searchPublicFetchLimit;
    final uri = Uri.parse('${Env.supabaseUrl}/functions/v1/recipe_api').replace(
      queryParameters: <String, String>{
        'type': 'public',
        'limit': '$requestedLimit',
        'offset': '0',
        'search_mode': useAiSearch ? 'ai' : 'keyword',
        if (normalizedSearch.isNotEmpty) 'search': normalizedSearch,
      },
    );

    final response = await _getWithRetry(
      uri,
      headers: <String, String>{
        'apikey': Env.supabaseAnonKey,
      },
    );

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw StateError(
        '공개 레시피를 불러오지 못했습니다. (HTTP ${response.statusCode})',
      );
    }

    final payload = jsonDecode(response.body);
    if (payload is! Map<String, dynamic> || payload['status'] != 'ok') {
      throw StateError('공개 레시피 응답 형식이 올바르지 않습니다.');
    }

    final rows = payload['data'];
    if (rows is! List<dynamic>) {
      return const <Recipe>[];
    }

    final recipes = <Recipe>[];
    for (final row in rows.whereType<Map<String, dynamic>>()) {
      try {
        recipes.add(_mapRecipe(row));
      } on StateError {
        // Skip malformed rows so one bad record does not break the whole list.
        continue;
      }
    }

    if (rows.isNotEmpty && recipes.isEmpty) {
      throw StateError('공개 레시피 데이터 형식이 올바르지 않습니다.');
    }

    return recipes;
  }

  @override
  Future<List<Recipe>> listSubscriberRecipes() async {
    final userId = await _requireUserId();

    final rows = await _client
        .from('recipes_user')
        .select(
          'id,title,summary,notes,ingredients,steps,image_url,youtube_url,visibility,source_type',
        )
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

    final response = await http.get(
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
    final response = await _getWithRetry(
      Uri.parse('${Env.supabaseUrl}/functions/v1/recipe_api/$id?type=public'),
      headers: <String, String>{
        'apikey': Env.supabaseAnonKey,
      },
    );

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
      return null;
    }

    return _mapRecipe(data);
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
          'id,title,summary,notes,ingredients,steps,image_url,youtube_url,visibility,source_type',
        )
        .single();

    return _mapRecipe(row);
  }

  @override
  Future<Recipe> updateSubscriberRecipe({
    required String id,
    required String title,
    required List<String> ingredients,
    required List<String> steps,
    String? summary,
    String? notes,
    String? imageUrl,
    String? youtubeUrl,
  }) async {
    await _requireUserId();

    final row = await _client
        .from('recipes_user')
        .update(<String, dynamic>{
          'title': title,
          'summary': summary?.trim().isEmpty ?? true ? null : summary!.trim(),
          'ingredients': ingredients,
          'steps': steps,
          'notes': notes?.trim().isEmpty ?? true ? null : notes!.trim(),
          'image_url':
              imageUrl?.trim().isEmpty ?? true ? null : imageUrl!.trim(),
          'youtube_url':
              youtubeUrl?.trim().isEmpty ?? true ? null : youtubeUrl!.trim(),
          'updated_at': DateTime.now().toIso8601String(),
        })
        .eq('id', id)
        .select(
          'id,title,summary,notes,ingredients,steps,image_url,youtube_url,visibility,source_type',
        )
        .single();

    return _mapRecipe(row);
  }

  @override
  Future<Recipe> promoteSubscriberRecipeToCreator({
    required String id,
    bool deleteSource = false,
    bool includeSummary = true,
    bool includeYoutubeUrl = true,
    bool includeImageUrl = true,
    bool includeNotesAsTips = true,
  }) async {
    await _requireUserId();

    final result = await _client.rpc(
      'promote_subscriber_recipe_to_creator',
      params: <String, dynamic>{
        'p_recipe_user_id': id,
        'p_delete_source': deleteSource,
        'p_include_summary': includeSummary,
        'p_include_youtube_url': includeYoutubeUrl,
        'p_include_image_url': includeImageUrl,
        'p_include_notes_as_tips': includeNotesAsTips,
      },
    );

    Map<String, dynamic>? row;
    if (result is Map<String, dynamic>) {
      row = result;
    } else if (result is List && result.isNotEmpty) {
      final first = result.first;
      if (first is Map<String, dynamic>) {
        row = first;
      }
    }

    if (row == null) {
      throw StateError('내 레시피 승격 결과를 확인하지 못했습니다.');
    }

    return _mapRecipe(row);
  }
}
