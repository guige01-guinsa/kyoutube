import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/config/env.dart';
import '../domain/recipe.dart';
import 'recipe_repository.dart';

class SupabaseRecipeRepository implements RecipeRepository {
  SupabaseRecipeRepository({SupabaseClient? client})
      : _client = client ?? Supabase.instance.client;

  final SupabaseClient _client;

  Recipe _mapRecipe(Map<String, dynamic> map) {
    return Recipe(
      id: map['id'] as String,
      title: map['title'] as String,
      summary: map['summary'] as String?,
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
    );
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
  Future<List<Recipe>> listPublicRecipes() async {
    final rows = await _client
        .from('recipes_public')
        .select('id,title,summary,ingredients,steps,image_url')
        .limit(30);

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
  Future<List<Recipe>> listCreatorRecipes() async {
    final session = _client.auth.currentSession;
    if (session == null) {
      throw StateError('로그인이 필요합니다.');
    }

    final response = await http.get(
      Uri.parse(
          '${Env.supabaseUrl}/functions/v1/recipe_api?type=creator&limit=30&offset=0'),
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
    final row = await _client
        .from('recipes_public')
        .select('id,title,summary,ingredients,steps,image_url')
        .eq('id', id)
        .maybeSingle();

    if (row == null) return null;

    final map = row;
    return _mapRecipe(map);
  }
}
